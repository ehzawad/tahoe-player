import AVFoundation

/// Contract for playback backends that expose an `AVPlayer`.
///
/// Tahoe Player also has a separate `MPVPlaybackEngine` for broad-format
/// playback while the libmpv renderer still requires its own surface and event
/// loop.
protocol PlaybackEngine: AnyObject {
    /// The `AVPlayer` consumed by the AVFoundation rendering path.
    var avPlayer: AVPlayer { get }

    /// Load a media file for the AVFoundation path, preparing a fallback MP4
    /// when needed.
    @MainActor func load(url: URL) async throws -> PreparedMedia

    func pause()
    func seek(to seconds: Double, completion: @escaping @MainActor () -> Void)

    /// Runtime probe for the AVFoundation path.
    @MainActor func canAttemptPlayback(of url: URL) async -> Bool

    var duration: Double { get }
}

extension PlaybackEngine {
    func seek(to seconds: Double) {
        seek(to: seconds) {}
    }
}
