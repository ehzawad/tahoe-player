import AppKit
import CMpv
import Foundation

@MainActor
final class MPVPlaybackEngine {
    private var handle: OpaquePointer?
    private var renderContext: OpaquePointer?
    private weak var openGLContext: NSOpenGLContext?
    private var renderUpdateTarget: MPVRenderUpdateTarget?
    private var renderUpdateContext: UnsafeMutableRawPointer?
    private var currentURL: URL?
    private var loadedURL: URL?
    private var playbackState = MPVPlaybackState()
    private var requestedRate = 1.0
    private var requestedVolume = 0.9
    private var requestedMuted = false
    private var pendingSeekCompletion: (@MainActor () -> Void)?
    private var seekGeneration = 0

    var onError: ((String) -> Void)?

    isolated deinit {
        shutdownHandle()
        currentURL = nil
    }

    var duration: Double {
        readDoubleProperty("duration") ?? 0
    }

    var currentTime: Double {
        readDoubleProperty("time-pos") ?? 0
    }

    var isPlaying: Bool {
        guard currentURL != nil else { return false }
        return !(readFlagProperty("pause") ?? playbackState.wantsPaused)
    }

    static func prefersDirectPlayback(for url: URL) -> Bool {
        let directContainerExtensions: Set<String> = [
            "avi",
            "flv",
            "m2ts",
            "mkv",
            "mts",
            "ts",
            "webm"
        ]
        return directContainerExtensions.contains(url.pathExtension.lowercased())
    }

    func attach(to context: NSOpenGLContext, updateView: NSView) {
        do {
            if openGLContext !== context {
                releaseRenderContext()
                openGLContext = context
            }

            try startHandleIfNeeded()
            try createRenderContextIfNeeded(updateView: updateView)

            if let currentURL, loadedURL != currentURL {
                try loadCurrentURL(currentURL)
            }
        } catch {
            onError?(error.localizedDescription)
        }
    }

    func load(url: URL) async throws -> PreparedMedia {
        currentURL = url
        loadedURL = nil
        playbackState.prepareForLoad()

        if handle != nil, renderContext != nil {
            try loadCurrentURL(url)
        }

        return PreparedMedia(
            sourceURL: url,
            playbackURL: url,
            compatibilityNote: "Playing directly with libmpv.",
            durationOverride: nil
        )
    }

    func play(rate: Double) {
        if playbackState.prepareForPlay() {
            runCommand(["seek", "0", "absolute+exact"])
        }

        requestedRate = rate
        applyPlaybackState()
    }

    func pause() {
        playbackState.prepareForPause()
        applyPlaybackState()
    }

    func seek(to seconds: Double, completion: @escaping @MainActor () -> Void) {
        playbackState.prepareForSeek()
        seekGeneration += 1
        let generation = seekGeneration
        pendingSeekCompletion = completion
        runCommand(["seek", "\(seconds)", "absolute+exact"])

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(750))
            guard let self, self.seekGeneration == generation else { return }
            self.completePendingSeek()
        }
    }

    func setVolume(_ volume: Double) {
        requestedVolume = max(0, min(volume, 1))
        runCommand(["set", "volume", "\(requestedVolume * 100)"])
    }

    func setMuted(_ muted: Bool) {
        requestedMuted = muted
        runCommand(["set", "mute", muted ? "yes" : "no"])
    }

    func setPlaybackRate(_ rate: Double) {
        requestedRate = rate
        runCommand(["set", "speed", "\(requestedRate)"])
    }

    func subtitleState() -> (tracks: [SubtitleTrack], selectedID: String) {
        var node = mpv_node()
        guard let handle else { return ([.off], SubtitleTrack.offID) }
        let status = "track-list".withCString { cName in
            mpv_get_property(handle, cName, MPV_FORMAT_NODE, &node)
        }
        guard status >= 0 else { return ([.off], SubtitleTrack.offID) }
        defer { mpv_free_node_contents(&node) }

        guard node.format == MPV_FORMAT_NODE_ARRAY,
              let list = node.u.list,
              list.pointee.num > 0,
              let values = list.pointee.values
        else {
            return ([.off], SubtitleTrack.offID)
        }

        var tracks = [SubtitleTrack.off]
        var selectedID = SubtitleTrack.offID
        var subtitleIndex = 1

        for index in 0..<Int(list.pointee.num) {
            let trackNode = values.advanced(by: index).pointee
            guard stringValue(named: "type", in: trackNode) == "sub",
                  let mpvID = intValue(named: "id", in: trackNode)
            else {
                continue
            }

            let id = Self.subtitleTrackID(forMPVID: mpvID)
            let title = subtitleTitle(
                for: trackNode,
                fallbackIndex: subtitleIndex
            )
            tracks.append(SubtitleTrack(id: id, title: title))

            if flagValue(named: "selected", in: trackNode) == true {
                selectedID = id
            }

            subtitleIndex += 1
        }

        return (tracks, selectedID)
    }

    func selectSubtitle(id: String) {
        if id == SubtitleTrack.offID {
            runCommand(["set", "sid", "no"])
            return
        }

        guard let mpvID = Self.mpvID(forSubtitleTrackID: id) else {
            runCommand(["set", "sid", "no"])
            return
        }
        runCommand(["set", "sid", "\(mpvID)"])
    }

    func drainEvents() {
        guard let handle else { return }

        while true {
            guard let event = mpv_wait_event(handle, 0) else { return }
            switch event.pointee.event_id {
            case MPV_EVENT_NONE:
                return
            case MPV_EVENT_END_FILE:
                let endFileEvent = event.pointee.data?.assumingMemoryBound(to: mpv_event_end_file.self)
                if let reason = endFileEvent?.pointee.reason {
                    playbackState.handleEndFile(reason: reason)
                }
            case MPV_EVENT_LOG_MESSAGE:
                logMessage(from: event)
            case MPV_EVENT_PLAYBACK_RESTART:
                playbackState.handlePlaybackRestart()
                completePendingSeek()
            case MPV_EVENT_SHUTDOWN:
                return
            default:
                break
            }
        }
    }

    func render(width: Int32, height: Int32) {
        guard width > 0, height > 0, let renderContext else { return }

        openGLContext?.makeCurrentContext()
        _ = mpv_render_context_update(renderContext)

        var fbo = mpv_opengl_fbo(
            fbo: 0,
            w: width,
            h: height,
            internal_format: 0
        )
        var flipY: Int32 = 1

        withUnsafeMutablePointer(to: &fbo) { fboPointer in
            withUnsafeMutablePointer(to: &flipY) { flipPointer in
                var params = [
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_OPENGL_FBO,
                        data: UnsafeMutableRawPointer(fboPointer)
                    ),
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_FLIP_Y,
                        data: UnsafeMutableRawPointer(flipPointer)
                    ),
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_INVALID,
                        data: nil
                    )
                ]
                let status = mpv_render_context_render(renderContext, &params)
                if status < 0 {
                    reportError(status)
                }
            }
        }

        openGLContext?.flushBuffer()
        mpv_render_context_report_swap(renderContext)
    }

    func shutdown() {
        shutdownHandle()
        currentURL = nil
        loadedURL = nil
        playbackState.reset()
    }

    private func startHandleIfNeeded() throws {
        guard handle == nil else { return }
        guard let nextHandle = mpv_create() else {
            throw MPVPlaybackError.startFailed("libmpv could not create a playback handle.")
        }

        handle = nextHandle

        try setOption("terminal", "no")
        try setOption("input-default-bindings", "no")
        try setOption("input-vo-keyboard", "no")
        try setOption("keep-open", "yes")
        try setOption("force-window", "yes")
        try setOption("hwdec", "auto-safe")
        try setOption("vo", "libmpv")
        try setOption("video-sync", "display-resample")

        try check(mpv_initialize(nextHandle))
        _ = "warn".withCString { mpv_request_log_messages(nextHandle, $0) }
        applyPlaybackState()
    }

    private func createRenderContextIfNeeded(updateView: NSView) throws {
        guard renderContext == nil else { return }
        guard let handle else { return }

        openGLContext?.makeCurrentContext()

        var initParams = mpv_opengl_init_params(
            get_proc_address: tahoe_mpv_get_proc_address,
            get_proc_address_ctx: nil
        )
        var nextRenderContext: OpaquePointer?

        let status = "opengl".withCString { apiType in
            withUnsafeMutablePointer(to: &initParams) { initParamsPointer in
                var params = [
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_API_TYPE,
                        data: UnsafeMutableRawPointer(mutating: apiType)
                    ),
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS,
                        data: UnsafeMutableRawPointer(initParamsPointer)
                    ),
                    mpv_render_param(
                        type: MPV_RENDER_PARAM_INVALID,
                        data: nil
                    )
                ]
                return mpv_render_context_create(&nextRenderContext, handle, &params)
            }
        }

        try check(status)
        renderContext = nextRenderContext

        if let renderContext {
            let target = MPVRenderUpdateTarget(view: updateView)
            renderUpdateTarget = target
            let targetContext = Unmanaged.passRetained(target).toOpaque()
            renderUpdateContext = targetContext
            mpv_render_context_set_update_callback(
                renderContext,
                mpvRenderUpdateCallback,
                targetContext
            )
        }
    }

    private func loadCurrentURL(_ url: URL) throws {
        playbackState.prepareForLoad()
        try checkedCommand(["loadfile", url.path(percentEncoded: false), "replace"])
        loadedURL = url
        applyPlaybackState()
    }

    private func applyPlaybackState() {
        setVolume(requestedVolume)
        setMuted(requestedMuted)
        setPlaybackRate(requestedRate)
        runCommand(["set", "pause", playbackState.wantsPaused ? "yes" : "no"])
    }

    private func setOption(_ name: String, _ value: String) throws {
        guard let handle else { return }
        let status = name.withCString { cName in
            value.withCString { cValue in
                mpv_set_option_string(handle, cName, cValue)
            }
        }
        try check(status)
    }

    private func checkedCommand(_ arguments: [String]) throws {
        try check(command(arguments))
    }

    private func runCommand(_ arguments: [String]) {
        do {
            try checkedCommand(arguments)
        } catch {
            onError?(error.localizedDescription)
        }
    }

    @discardableResult
    private func command(_ arguments: [String]) -> Int32 {
        guard let handle else { return 0 }

        let duplicatedArguments = arguments.map { strdup($0) }
        defer {
            for argument in duplicatedArguments {
                free(argument)
            }
        }

        var cArguments = duplicatedArguments.map { UnsafePointer<CChar>($0) }
        cArguments.append(nil)

        return mpv_command(handle, &cArguments)
    }

    private func readDoubleProperty(_ name: String) -> Double? {
        guard let handle else { return nil }
        var value = 0.0
        let status = name.withCString { cName in
            mpv_get_property(handle, cName, MPV_FORMAT_DOUBLE, &value)
        }
        guard status >= 0, value.isFinite else { return nil }
        return value
    }

    private func readFlagProperty(_ name: String) -> Bool? {
        guard let handle else { return nil }
        var value: Int32 = 0
        let status = name.withCString { cName in
            mpv_get_property(handle, cName, MPV_FORMAT_FLAG, &value)
        }
        guard status >= 0 else { return nil }
        return value != 0
    }

    private func subtitleTitle(for trackNode: mpv_node, fallbackIndex: Int) -> String {
        let title = stringValue(named: "title", in: trackNode)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let language = stringValue(named: "lang", in: trackNode)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = []
        if let title, !title.isEmpty {
            parts.append(title)
        } else if let language, !language.isEmpty {
            parts.append(language.uppercased())
        } else {
            parts.append("Subtitle \(fallbackIndex)")
        }

        if flagValue(named: "forced", in: trackNode) == true {
            parts.append("Forced")
        }
        if flagValue(named: "default", in: trackNode) == true {
            parts.append("Default")
        }
        if flagValue(named: "external", in: trackNode) == true {
            parts.append("External")
        }

        return parts.joined(separator: " - ")
    }

    private func stringValue(named key: String, in node: mpv_node) -> String? {
        guard let value = value(named: key, in: node),
              value.format == MPV_FORMAT_STRING,
              let string = value.u.string
        else {
            return nil
        }
        return String(cString: string)
    }

    private func intValue(named key: String, in node: mpv_node) -> Int64? {
        guard let value = value(named: key, in: node),
              value.format == MPV_FORMAT_INT64
        else {
            return nil
        }
        return value.u.int64
    }

    private func flagValue(named key: String, in node: mpv_node) -> Bool? {
        guard let value = value(named: key, in: node),
              value.format == MPV_FORMAT_FLAG
        else {
            return nil
        }
        return value.u.flag != 0
    }

    private func value(named key: String, in node: mpv_node) -> mpv_node? {
        guard node.format == MPV_FORMAT_NODE_MAP,
              let list = node.u.list,
              list.pointee.num > 0,
              let keys = list.pointee.keys,
              let values = list.pointee.values
        else {
            return nil
        }

        for index in 0..<Int(list.pointee.num) {
            guard let cKey = keys.advanced(by: index).pointee else { continue }
            if String(cString: cKey) == key {
                return values.advanced(by: index).pointee
            }
        }

        return nil
    }

    private static func subtitleTrackID(forMPVID mpvID: Int64) -> String {
        "mpv-subtitle-\(mpvID)"
    }

    private static func mpvID(forSubtitleTrackID trackID: String) -> Int64? {
        let prefix = "mpv-subtitle-"
        guard trackID.hasPrefix(prefix) else { return nil }
        return Int64(trackID.dropFirst(prefix.count))
    }

    private func check(_ status: Int32) throws {
        guard status < 0 else { return }

        let message: String
        if let errorString = mpv_error_string(status) {
            message = String(cString: errorString)
        } else {
            message = "libmpv returned error \(status)."
        }
        throw MPVPlaybackError.startFailed(message)
    }

    private func reportError(_ status: Int32) {
        guard status < 0 else { return }
        if let errorString = mpv_error_string(status) {
            onError?(String(cString: errorString))
        } else {
            onError?("libmpv returned error \(status).")
        }
    }

    private func logMessage(from event: UnsafeMutablePointer<mpv_event>) {
        guard let data = event.pointee.data else { return }
        let message = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
        guard let text = message.text, let level = message.level, let prefix = message.prefix else {
            return
        }
        NSLog("libmpv [%s] %s: %s", level, prefix, text)
    }

    private func completePendingSeek() {
        guard let completion = pendingSeekCompletion else { return }
        pendingSeekCompletion = nil
        completion()
    }

    private func releaseRenderContext() {
        guard let renderContext else {
            releaseRenderUpdateTarget()
            renderUpdateTarget = nil
            return
        }

        openGLContext?.makeCurrentContext()
        mpv_render_context_set_update_callback(renderContext, nil, nil)
        mpv_render_context_free(renderContext)
        self.renderContext = nil
        releaseRenderUpdateTarget()
    }

    private func releaseRenderUpdateTarget() {
        if let renderUpdateContext {
            Unmanaged<MPVRenderUpdateTarget>.fromOpaque(renderUpdateContext).release()
            self.renderUpdateContext = nil
        }
        renderUpdateTarget = nil
    }

    private func shutdownHandle() {
        releaseRenderContext()
        completePendingSeek()
        if let handle {
            mpv_terminate_destroy(handle)
        }
        handle = nil
        openGLContext = nil
        loadedURL = nil
        playbackState.reset()
    }
}

enum MPVPlaybackError: LocalizedError {
    case startFailed(String)

    var errorDescription: String? {
        switch self {
        case .startFailed(let message):
            "libmpv playback failed: \(message)"
        }
    }
}

private final class MPVRenderUpdateTarget {
    weak var view: NSView?

    init(view: NSView) {
        self.view = view
    }

    nonisolated func requestRender() {
        DispatchQueue.main.async { [weak view] in
            view?.needsDisplay = true
        }
    }
}

private let mpvRenderUpdateCallback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { context in
    guard let context else { return }
    let target = Unmanaged<MPVRenderUpdateTarget>.fromOpaque(context).takeUnretainedValue()
    target.requestRender()
}
