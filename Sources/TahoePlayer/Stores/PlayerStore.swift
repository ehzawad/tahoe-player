import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class PlayerStore {
    // MARK: – Engine

    enum Backend {
        case avFoundation
        case mpv
    }

    @ObservationIgnored private let avEngine = AVFoundationPlaybackEngine()
    @ObservationIgnored let mpvEngine = MPVPlaybackEngine()

    /// Stable player reference for the surface view.
    var player: AVPlayer { avEngine.avPlayer }
    var activeBackend = Backend.avFoundation
    var usesMPVPlayback: Bool { activeBackend == .mpv }

    // MARK: – UI State

    var media: MediaFile?
    var isPreparing = false
    var preparationMessage = ""
    var errorMessage: String?
    var currentTime = 0.0
    var duration = 0.0
    var isPlaying = false
    var isDropTargeted = false
    var isScrubbing = false
    var subtitleTracks = [SubtitleTrack.off]
    var selectedSubtitleID = SubtitleTrack.offID
    var isMuted = false {
        didSet {
            player.isMuted = isMuted
            mpvEngine.setMuted(isMuted)
        }
    }
    var volume = 0.9 {
        didSet {
            let clampedVolume = max(0, min(volume, 1))
            player.volume = Float(clampedVolume)
            mpvEngine.setVolume(clampedVolume)

            if clampedVolume > 0 {
                lastAudibleVolume = clampedVolume
                if isMuted {
                    isMuted = false
                }
            } else if !isMuted {
                isMuted = true
            }
        }
    }
    var playbackRate = 1.0 {
        didSet {
            guard isPlaying else { return }
            switch activeBackend {
            case .avFoundation:
                player.rate = Float(playbackRate)
            case .mpv:
                mpvEngine.setPlaybackRate(playbackRate)
            }
        }
    }

    var hasMedia: Bool { media != nil }
    var selectedSubtitleTitle: String {
        subtitleTracks.first { $0.id == selectedSubtitleID }?.title ?? SubtitleTrack.off.title
    }

    // MARK: – Observation tokens

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var itemEndObserver: NSObjectProtocol?
    @ObservationIgnored private var itemStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var timeControlStatusObservation: NSKeyValueObservation?
    @ObservationIgnored private var mpvPollingTask: Task<Void, Never>?
    @ObservationIgnored private var loadingURL: URL?
    @ObservationIgnored private var legibleGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var subtitleOptions: [String: AVMediaSelectionOption] = [:]
    @ObservationIgnored private var mpvSubtitleTrackIDs = Set<String>()
    @ObservationIgnored private var lastAudibleVolume = 0.9

    // MARK: – Init

    init() {
        player.volume = Float(volume)
        player.isMuted = isMuted
        mpvEngine.setVolume(volume)
        mpvEngine.setMuted(isMuted)
        mpvEngine.onError = { [weak self] message in
            self?.errorMessage = message
        }
        installTimeObserver()
        installPlayerStatusObserver()
    }

    isolated deinit {
        mpvPollingTask?.cancel()
        if let timeObserver {
            avEngine.avPlayer.removeTimeObserver(timeObserver)
        }

        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
        }

        itemStatusObservation?.invalidate()
        timeControlStatusObservation?.invalidate()
    }

    // MARK: – File Opening

    func presentOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Open Media"
        panel.message = "Choose an MP4, MOV, MKV, WebM, or other movie file."
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = Self.supportedContentTypes

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                await self?.load(url: url)
            }
        }
    }

    func load(url: URL) async {
        if isPreparing, loadingURL == url {
            return
        }

        avEngine.cancelPreparation()
        loadingURL = url
        errorMessage = nil
        isPreparing = true
        currentTime = 0
        duration = 0
        resetSubtitleTracks()

        let useMPV = MPVPlaybackEngine.prefersDirectPlayback(for: url)
        activeBackend = useMPV ? .mpv : .avFoundation
        preparationMessage = useMPV
            ? "Opening \(url.lastPathComponent) directly with libmpv…"
            : "Opening \(url.lastPathComponent)…"

        do {
            clearItemObservers()
            stopMPVPolling()

            let prepared: PreparedMedia
            if useMPV {
                avEngine.pause()
                prepared = try await mpvEngine.load(url: url)
            } else {
                mpvEngine.pause()
                let canPlayDirectly = await avEngine.canAttemptPlayback(of: url)
                if !canPlayDirectly {
                    preparationMessage = "Converting the container, audio, and subtitles for AVPlayer. Large files can take a few minutes."
                }
                prepared = try await avEngine.load(url: url)
            }

            guard loadingURL == url else { return }

            media = MediaFile(
                sourceURL: prepared.sourceURL,
                playbackURL: prepared.playbackURL,
                title: prepared.sourceURL.deletingPathExtension().lastPathComponent,
                compatibilityNote: prepared.compatibilityNote
            )
            currentTime = 0
            duration = useMPV ? mpvEngine.duration : avEngine.duration
            isPreparing = false

            if useMPV {
                refreshMPVSubtitleTracks()
                startMPVPolling()
            } else if let item = avEngine.avPlayer.currentItem {
                installObservers(for: item)
                await refreshSubtitleTracks(for: item)
            }

            play()
        } catch {
            guard loadingURL == url else { return }
            isPreparing = false
            resetSubtitleTracks()
            errorMessage = error.localizedDescription
        }

        if loadingURL == url {
            loadingURL = nil
        }
    }

    // MARK: – Drag & Drop

    func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
            let url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = item as? URL
            }
            guard let url else { return }
            Task { @MainActor in
                await self?.load(url: url)
            }
        }
        return true
    }

    // MARK: – Transport (for menu commands)

    func play() {
        switch activeBackend {
        case .avFoundation:
            guard player.currentItem != nil else { return }
            player.rate = Float(playbackRate)
        case .mpv:
            guard media != nil else { return }
            mpvEngine.play(rate: playbackRate)
        }
    }

    func pause() {
        switch activeBackend {
        case .avFoundation:
            avEngine.pause()
        case .mpv:
            mpvEngine.pause()
        }
    }

    func togglePlayback() {
        isPlaying ? pause() : play()
    }

    func skip(by seconds: Double) {
        seek(to: currentTime + seconds)
    }

    func seekPreview(to seconds: Double) {
        isScrubbing = true
        currentTime = clampedPlaybackTime(seconds)
    }

    func finishSeek() {
        let target = clampedPlaybackTime(currentTime)
        currentTime = target
        seekActiveBackend(to: target) { [weak self] in
            self?.isScrubbing = false
        }
    }

    func seek(to seconds: Double) {
        let target = clampedPlaybackTime(seconds)
        currentTime = target
        seekActiveBackend(to: target)
    }

    func toggleFullScreen() {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.toggleFullScreen(nil)
    }

    func toggleMute() {
        if isMuted {
            if volume == 0 {
                volume = max(lastAudibleVolume, 0.1)
            }
            isMuted = false
        } else {
            if volume > 0 {
                lastAudibleVolume = volume
            }
            isMuted = true
        }
    }

    func adjustVolume(by delta: Double) {
        volume = max(0, min(volume + delta, 1))
    }

    func selectSubtitle(id: String) {
        if activeBackend == .mpv {
            let normalizedID = id == SubtitleTrack.offID || mpvSubtitleTrackIDs.contains(id)
                ? id
                : SubtitleTrack.offID
            selectedSubtitleID = normalizedID
            mpvEngine.selectSubtitle(id: normalizedID)
            refreshMPVSubtitleTracks()
            return
        }

        let normalizedID = id == SubtitleTrack.offID || subtitleOptions[id] != nil
            ? id
            : SubtitleTrack.offID
        selectedSubtitleID = normalizedID

        guard activeBackend == .avFoundation else { return }
        guard let item = player.currentItem, let legibleGroup else { return }
        item.select(subtitleOptions[normalizedID], in: legibleGroup)
    }

    // MARK: – Utilities

    func revealSourceInFinder() {
        guard let media else { return }
        NSWorkspace.shared.activateFileViewerSelecting([media.sourceURL])
    }

    func dismissError() {
        errorMessage = nil
    }

    func shutdown() {
        avEngine.pause()
        avEngine.cancelPreparation()
        mpvEngine.shutdown()
        stopMPVPolling()
    }

    // MARK: – Observers

    private func installTimeObserver() {
        timeObserver = avEngine.avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                guard self.activeBackend == .avFoundation else { return }
                let seconds = time.seconds
                guard seconds.isFinite else { return }
                guard !self.isScrubbing else { return }
                self.currentTime = seconds
            }
        }
    }

    private func installPlayerStatusObserver() {
        timeControlStatusObservation = avEngine.avPlayer.observe(
            \.timeControlStatus, options: [.initial, .new]
        ) { [weak self] player, _ in
            Task { @MainActor in
                guard self?.activeBackend == .avFoundation else { return }
                self?.isPlaying = player.timeControlStatus == .playing
            }
        }
    }

    private func installObservers(for item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                if item.status == .failed {
                    self?.errorMessage = item.error?.localizedDescription ?? "Playback failed."
                }
            }
        }

        itemEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.seek(to: 0)
            }
        }
    }

    private func clearItemObservers() {
        itemStatusObservation = nil
        if let itemEndObserver {
            NotificationCenter.default.removeObserver(itemEndObserver)
            self.itemEndObserver = nil
        }
    }

    private func refreshSubtitleTracks(for item: AVPlayerItem) async {
        guard let group = try? await item.asset.loadMediaSelectionGroup(for: .legible),
              !group.options.isEmpty
        else {
            resetSubtitleTracks()
            return
        }

        var tracks = [SubtitleTrack.off]
        var options: [String: AVMediaSelectionOption] = [:]

        for (index, option) in group.options.enumerated() {
            let id = "subtitle-\(index)"
            let title = subtitleTitle(for: option, fallbackIndex: index + 1)
            tracks.append(SubtitleTrack(id: id, title: title))
            options[id] = option
        }

        legibleGroup = group
        subtitleOptions = options
        subtitleTracks = tracks
        selectedSubtitleID = SubtitleTrack.offID
        item.select(nil, in: group)
    }

    private func refreshMPVSubtitleTracks() {
        let state = mpvEngine.subtitleState()
        let ids = Set(state.tracks.map(\.id))
        mpvSubtitleTrackIDs = ids

        if subtitleTracks != state.tracks {
            subtitleTracks = state.tracks
        }

        let selectedID = ids.contains(state.selectedID) ? state.selectedID : SubtitleTrack.offID
        if selectedSubtitleID != selectedID {
            selectedSubtitleID = selectedID
        }
    }

    private func resetSubtitleTracks() {
        legibleGroup = nil
        subtitleOptions = [:]
        mpvSubtitleTrackIDs = []
        subtitleTracks = [SubtitleTrack.off]
        selectedSubtitleID = SubtitleTrack.offID
    }

    private func subtitleTitle(for option: AVMediaSelectionOption, fallbackIndex: Int) -> String {
        let displayName = option.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !displayName.isEmpty {
            return displayName
        }

        if let language = option.extendedLanguageTag, !language.isEmpty {
            return language.uppercased()
        }

        return "Subtitle \(fallbackIndex)"
    }

    private func clampedPlaybackTime(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return 0 }
        guard duration > 0 else { return 0 }
        return max(0, min(seconds, duration))
    }

    private func seekActiveBackend(to seconds: Double, completion: @escaping @MainActor () -> Void = {}) {
        switch activeBackend {
        case .avFoundation:
            avEngine.seek(to: seconds, completion: completion)
        case .mpv:
            mpvEngine.seek(to: seconds, completion: completion)
        }
    }

    private func startMPVPolling() {
        mpvPollingTask?.cancel()
        mpvPollingTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.activeBackend == .mpv else { return }
                self.mpvEngine.drainEvents()
                self.refreshMPVSubtitleTracks()

                if !self.isScrubbing {
                    self.currentTime = self.mpvEngine.currentTime
                }

                let mpvDuration = self.mpvEngine.duration
                if mpvDuration.isFinite, mpvDuration > 0 {
                    self.duration = mpvDuration
                }
                self.isPlaying = self.mpvEngine.isPlaying

                try? await Task.sleep(for: .milliseconds(250))
            }
        }
    }

    private func stopMPVPolling() {
        mpvPollingTask?.cancel()
        mpvPollingTask = nil
    }

    // MARK: – Supported Types

    static let supportedContentTypes: [UTType] = {
        var types: [UTType] = [.movie, .mpeg4Movie, .quickTimeMovie]
        ["mkv", "webm", "avi"].forEach { ext in
            if let type = UTType(filenameExtension: ext) {
                types.append(type)
            }
        }
        return types
    }()
}
