import AVFoundation

/// Contract for a media playback backend.
///
/// The app ships with AVFoundation; this protocol exists so a
/// second decoder (libmpv, VLCKit, …) can slot in later without
/// rewiring the UI layer.
protocol PlaybackEngine: AnyObject {
    /// The underlying AVPlayer. Future non-AVFoundation backends
    /// would supply their own rendering surface instead.
    var avPlayer: AVPlayer { get }

    /// Load a media file, preparing it if necessary (e.g. FFmpeg remux).
    @MainActor func load(url: URL) async throws -> PreparedMedia

    func pause()
    func seek(to seconds: Double)

    /// Runtime probe: can this backend handle the given URL?
    @MainActor func canAttemptPlayback(of url: URL) async -> Bool

    var duration: Double { get }
}
