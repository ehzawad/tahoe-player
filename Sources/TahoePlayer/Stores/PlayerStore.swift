import AppKit
import AVFoundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class PlayerStore {
    // MARK: – Engine

    @ObservationIgnored private let engine = AVFoundationPlaybackEngine()

    /// Stable player reference for the surface view.
    var player: AVPlayer { engine.avPlayer }

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
        }
    }
    var volume = 0.9 {
        didSet {
            let clampedVolume = max(0, min(volume, 1))
            player.volume = Float(clampedVolume)

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
            player.rate = Float(playbackRate)
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
    @ObservationIgnored private var loadingURL: URL?
    @ObservationIgnored private var legibleGroup: AVMediaSelectionGroup?
    @ObservationIgnored private var subtitleOptions: [String: AVMediaSelectionOption] = [:]
    @ObservationIgnored private var lastAudibleVolume = 0.9

    // MARK: – Init

    init() {
        player.volume = Float(volume)
        player.isMuted = isMuted
        installTimeObserver()
        installPlayerStatusObserver()
    }

    isolated deinit {
        if let timeObserver {
            engine.avPlayer.removeTimeObserver(timeObserver)
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

        loadingURL = url
        errorMessage = nil
        isPreparing = true
        currentTime = 0
        duration = 0
        resetSubtitleTracks()

        let canPlayDirectly = await engine.canAttemptPlayback(of: url)
        preparationMessage = canPlayDirectly
            ? "Opening \(url.lastPathComponent)…"
            : "Converting the container, audio, and subtitles for AVPlayer. Large MKV files can take a few minutes."

        do {
            clearItemObservers()

            let prepared = try await engine.load(url: url)
            guard loadingURL == url else { return }

            media = MediaFile(
                sourceURL: prepared.sourceURL,
                playbackURL: prepared.playbackURL,
                title: prepared.sourceURL.deletingPathExtension().lastPathComponent,
                compatibilityNote: prepared.compatibilityNote
            )
            currentTime = 0
            duration = engine.duration
            isPreparing = false

            if let item = engine.avPlayer.currentItem {
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
        guard player.currentItem != nil else { return }
        player.rate = Float(playbackRate)
    }

    func pause() {
        engine.pause()
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
        engine.seek(to: target) { [weak self] in
            self?.isScrubbing = false
        }
    }

    func seek(to seconds: Double) {
        let target = clampedPlaybackTime(seconds)
        currentTime = target
        engine.seek(to: target)
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

    func selectSubtitle(id: String) {
        let normalizedID = id == SubtitleTrack.offID || subtitleOptions[id] != nil
            ? id
            : SubtitleTrack.offID
        selectedSubtitleID = normalizedID

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
        engine.pause()
        engine.cancelPreparation()
    }

    // MARK: – Observers

    private func installTimeObserver() {
        timeObserver = engine.avPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                guard seconds.isFinite else { return }
                guard !self.isScrubbing else { return }
                self.currentTime = seconds
            }
        }
    }

    private func installPlayerStatusObserver() {
        timeControlStatusObservation = engine.avPlayer.observe(
            \.timeControlStatus, options: [.initial, .new]
        ) { [weak self] player, _ in
            Task { @MainActor in
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

    private func resetSubtitleTracks() {
        legibleGroup = nil
        subtitleOptions = [:]
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
