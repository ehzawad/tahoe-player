import AVFoundation

/// AVFoundation-backed playback engine.
///
/// Natively playable files (MP4, MOV, most AAC/H.264/HEVC content)
/// load directly into AVPlayer. Other containers (MKV, WebM) are
/// handed to ``MediaPreparationService``, which remuxes via FFmpeg
/// when available.
final class AVFoundationPlaybackEngine: PlaybackEngine {
    let avPlayer = AVPlayer()
    private let preparer = MediaPreparationService()
    private(set) var duration: Double = 0

    @MainActor
    func load(url: URL) async throws -> PreparedMedia {
        let prepared = try await preparer.prepare(url: url)

        let asset = AVURLAsset(url: prepared.playbackURL)
        let loadedDuration = try await asset.load(.duration)
        if let durationOverride = prepared.durationOverride, durationOverride.isFinite, durationOverride > 0 {
            duration = durationOverride
        } else {
            duration = loadedDuration.seconds.isFinite ? loadedDuration.seconds : 0
        }

        let item = AVPlayerItem(asset: asset)
        avPlayer.replaceCurrentItem(with: item)
        return prepared
    }

    func pause() {
        avPlayer.pause()
    }

    @MainActor
    func cancelPreparation() {
        preparer.cancelPreparation()
    }

    func seek(to seconds: Double, completion: @escaping @MainActor () -> Void) {
        guard duration > 0 else {
            Task { @MainActor in
                completion()
            }
            return
        }

        let clamped = max(0, min(seconds, duration))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        avPlayer.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            Task { @MainActor in
                completion()
            }
        }
    }

    @MainActor
    func canAttemptPlayback(of url: URL) async -> Bool {
        await MediaPreparationService.isNativelyPlayable(url: url)
    }
}
