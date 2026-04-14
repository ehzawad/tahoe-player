import AVFoundation
import CryptoKit
import Foundation

@MainActor
final class MediaPreparationService {
    private var activeProcess: Process?
    private let probeTimeout: TimeInterval = 15
    private let preparationTimeout: TimeInterval = 45 * 60

    deinit {
        activeProcess?.terminate()
    }

    func cancelPreparation() {
        stopActivePreparation()
    }

    func prepare(url: URL) async throws -> PreparedMedia {
        stopActivePreparation()

        if await Self.isNativelyPlayable(url: url) {
            return PreparedMedia(
                sourceURL: url,
                playbackURL: url,
                compatibilityNote: "Playing with AVFoundation.",
                durationOverride: nil
            )
        }

        let ffmpegURL = try resolveFFmpeg()
        let ffprobeURL = resolveFFprobe(near: ffmpegURL)
        let videoCodec = try? await probePrimaryVideoCodec(
            ffprobeURL: ffprobeURL,
            sourceURL: url
        )
        let sourceDuration = try? await probeSourceDuration(
            ffprobeURL: ffprobeURL,
            sourceURL: url
        )
        let subtitleStreamIndex = try? await probeTextSubtitleStreamIndex(
            ffprobeURL: ffprobeURL,
            sourceURL: url
        )
        let outputURL = try makePreparedOutputURL(for: url, variant: "prepared")
        if await Self.isNativelyPlayable(url: outputURL) {
            return PreparedMedia(
                sourceURL: url,
                playbackURL: outputURL,
                compatibilityNote: "Using a cached MP4 copy prepared for AVFoundation playback.",
                durationOverride: sourceDuration
            )
        }

        for usesHVC1Tag in hvc1TagAttempts(for: videoCodec) {
            do {
                try await runFFmpeg(
                    executableURL: ffmpegURL,
                    arguments: remuxArguments(
                        sourceURL: url,
                        outputURL: outputURL,
                        usesHVC1Tag: usesHVC1Tag,
                        subtitleStreamIndex: subtitleStreamIndex
                    )
                )

                if await Self.isNativelyPlayable(url: outputURL) {
                    return PreparedMedia(
                        sourceURL: url,
                        playbackURL: outputURL,
                        compatibilityNote: "Prepared a temporary MP4 copy for AVFoundation playback.",
                        durationOverride: sourceDuration
                    )
                }
            } catch {
                continue
            }
        }

        let transcodeURL = try makePreparedOutputURL(for: url, variant: "transcoded")
        let transcodeArguments = transcodeArguments(
            sourceURL: url,
            outputURL: transcodeURL,
            subtitleStreamIndex: subtitleStreamIndex
        )

        do {
            try await runFFmpeg(
                executableURL: ffmpegURL,
                arguments: transcodeArguments
            )
        } catch {
            throw error
        }

        guard await Self.isNativelyPlayable(url: transcodeURL) else {
            throw MediaPreparationError.preparedFileNotPlayable
        }

        return PreparedMedia(
            sourceURL: url,
            playbackURL: transcodeURL,
            compatibilityNote: "Transcoded a temporary MP4 copy for AVFoundation playback.",
            durationOverride: sourceDuration
        )
    }

    /// Whether AVFoundation can reliably play this URL directly.
    ///
    /// MKV and WebM containers are always treated as non-native even when
    /// `AVURLAsset.load(.isPlayable)` returns true — AVFoundation's runtime
    /// probe false-positives on Matroska files that contain Apple-native
    /// codecs (H.264/HEVC + AAC) but cannot actually render the container.
    static func isNativelyPlayable(url: URL) async -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["mkv", "webm"].contains(ext) {
            return false
        }

        let asset = AVURLAsset(url: url)
        do {
            return try await asset.load(.isPlayable)
        } catch {
            return false
        }
    }

    private func makePreparedOutputURL(for sourceURL: URL, variant: String) throws -> URL {
        let cacheKey = try cacheKey(for: sourceURL)
        let cacheRoot = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appending(path: "TahoePlayer", directoryHint: .isDirectory)
        .appending(path: "Prepared", directoryHint: .isDirectory)
        .appending(path: cacheKey, directoryHint: .isDirectory)

        try FileManager.default.createDirectory(
            at: cacheRoot,
            withIntermediateDirectories: true
        )

        let basename = sourceURL.deletingPathExtension().lastPathComponent
        return cacheRoot.appending(path: "\(basename)-\(variant).mp4")
    }

    private func cacheKey(for sourceURL: URL) throws -> String {
        let sourcePath = sourceURL.path(percentEncoded: false)
        let attributes = try FileManager.default.attributesOfItem(atPath: sourcePath)
        let byteCount = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modifiedAt = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let recipeVersion = "v3-hvc1-aac-stereo-mov-text"
        let input = "\(recipeVersion)|\(sourcePath)|\(byteCount)|\(modifiedAt)"
        let digest = SHA256.hash(data: Data(input.utf8))

        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func resolveFFmpeg() throws -> URL {
        let candidates = [
            "/opt/homebrew/bin/ffmpeg",
            "/usr/local/bin/ffmpeg",
            "/opt/local/bin/ffmpeg",
            "/usr/bin/ffmpeg"
        ]

        if let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) {
            return URL(fileURLWithPath: path)
        }

        throw MediaPreparationError.ffmpegMissing
    }

    private func resolveFFprobe(near ffmpegURL: URL) -> URL? {
        let sibling = ffmpegURL.deletingLastPathComponent().appending(path: "ffprobe")
        if FileManager.default.isExecutableFile(atPath: sibling.path(percentEncoded: false)) {
            return sibling
        }

        let candidates = [
            "/opt/homebrew/bin/ffprobe",
            "/usr/local/bin/ffprobe",
            "/opt/local/bin/ffprobe",
            "/usr/bin/ffprobe"
        ]

        guard let path = candidates.first(where: FileManager.default.isExecutableFile(atPath:)) else {
            return nil
        }

        return URL(fileURLWithPath: path)
    }

    private func probePrimaryVideoCodec(ffprobeURL: URL?, sourceURL: URL) async throws -> String? {
        guard let ffprobeURL else { return nil }

        let output = try await runProcess(
            executableURL: ffprobeURL,
            timeout: probeTimeout,
            arguments: [
                "-v", "error",
                "-select_streams", "v:0",
                "-show_entries", "stream=codec_name",
                "-of", "default=noprint_wrappers=1:nokey=1",
                sourceURL.path(percentEncoded: false)
            ]
        )

        return output
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
    }

    private func probeSourceDuration(ffprobeURL: URL?, sourceURL: URL) async throws -> Double? {
        guard let ffprobeURL else { return nil }

        let output = try await runProcess(
            executableURL: ffprobeURL,
            timeout: probeTimeout,
            arguments: [
                "-v", "error",
                "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1",
                sourceURL.path(percentEncoded: false)
            ]
        )

        guard let rawDuration = output
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init),
            let duration = Double(rawDuration),
            duration.isFinite,
            duration > 0
        else {
            return nil
        }

        return duration
    }

    private func probeTextSubtitleStreamIndex(ffprobeURL: URL?, sourceURL: URL) async throws -> Int? {
        guard let ffprobeURL else { return nil }

        let output = try await runProcess(
            executableURL: ffprobeURL,
            timeout: probeTimeout,
            arguments: [
                "-v", "error",
                "-select_streams", "s",
                "-show_entries", "stream=index,codec_name",
                "-of", "csv=p=0",
                sourceURL.path(percentEncoded: false)
            ]
        )

        let textSubtitleCodecs: Set<String> = [
            "ass",
            "mov_text",
            "ssa",
            "subrip",
            "text",
            "webvtt"
        ]

        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            guard parts.count >= 2,
                  let index = Int(parts[0]),
                  textSubtitleCodecs.contains(parts[1])
            else {
                continue
            }

            return index
        }

        return nil
    }

    private func hvc1TagAttempts(for videoCodec: String?) -> [Bool] {
        if videoCodec == "hevc" {
            return [true]
        }

        if videoCodec == nil {
            return [true, false]
        }

        return [false]
    }

    private func remuxArguments(
        sourceURL: URL,
        outputURL: URL,
        usesHVC1Tag: Bool,
        subtitleStreamIndex: Int?
    ) -> [String] {
        var arguments = [
            "-hide_banner",
            "-y",
            "-i", sourceURL.path(percentEncoded: false),
            "-map", "0:v:0",
            "-map", "0:a?",
            "-c:v", "copy"
        ]

        if usesHVC1Tag {
            arguments.append(contentsOf: ["-tag:v", "hvc1"])
        }

        arguments.append(contentsOf: [
            "-c:a", "aac",
            "-b:a", "192k",
            "-ac", "2",
        ])
        arguments.append(contentsOf: subtitleArguments(for: subtitleStreamIndex))
        arguments.append(contentsOf: [
            "-movflags", "+faststart",
            outputURL.path(percentEncoded: false)
        ])

        return arguments
    }

    private func transcodeArguments(
        sourceURL: URL,
        outputURL: URL,
        subtitleStreamIndex: Int?
    ) -> [String] {
        var arguments = [
            "-hide_banner",
            "-y",
            "-i", sourceURL.path(percentEncoded: false),
            "-map", "0:v:0",
            "-map", "0:a?",
            "-c:v", "libx264",
            "-preset", "veryfast",
            "-crf", "20",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac",
            "-b:a", "192k",
            "-ac", "2"
        ]
        arguments.append(contentsOf: subtitleArguments(for: subtitleStreamIndex))
        arguments.append(contentsOf: [
            "-movflags", "+faststart",
            outputURL.path(percentEncoded: false)
        ])

        return arguments
    }

    private func subtitleArguments(for streamIndex: Int?) -> [String] {
        guard let streamIndex else {
            return ["-sn"]
        }

        return [
            "-map", "0:\(streamIndex)",
            "-c:s", "mov_text"
        ]
    }

    private func runFFmpeg(executableURL: URL, arguments: [String]) async throws {
        _ = try await runProcess(
            executableURL: executableURL,
            timeout: preparationTimeout,
            arguments: arguments
        )
    }

    private func stopActivePreparation() {
        if let activeProcess, activeProcess.isRunning {
            activeProcess.terminate()
        }
        activeProcess = nil
    }

    private func runProcess(
        executableURL: URL,
        timeout: TimeInterval,
        arguments: [String]
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            let state = ProcessRunState(continuation: continuation)
            let timeoutNanoseconds = UInt64(max(timeout, 1) * 1_000_000_000)

            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if !chunk.isEmpty {
                    state.append(chunk)
                }
            }

            let timeoutTask = Task { [weak process] in
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                guard !Task.isCancelled else { return }

                if process?.isRunning == true {
                    process?.terminate()
                }

                state.resume(
                    throwing: MediaPreparationError.processTimedOut(
                        executableURL.lastPathComponent,
                        timeout,
                        state.outputString()
                    )
                )
            }

            process.terminationHandler = { process in
                timeoutTask.cancel()
                pipe.fileHandleForReading.readabilityHandler = nil
                let remainingOutput = pipe.fileHandleForReading.readDataToEndOfFile()
                state.append(remainingOutput)
                let message = state.outputString()

                Task { @MainActor [weak self] in
                    if self?.activeProcess === process {
                        self?.activeProcess = nil
                    }
                }

                if process.terminationStatus == 0 {
                    state.resume(returning: message)
                } else {
                    state.resume(throwing: MediaPreparationError.ffmpegFailed(message))
                }
            }

            do {
                activeProcess = process
                try process.run()
            } catch {
                timeoutTask.cancel()
                pipe.fileHandleForReading.readabilityHandler = nil
                activeProcess = nil
                state.resume(throwing: error)
            }
        }
    }
}

enum MediaPreparationError: LocalizedError {
    case ffmpegMissing
    case ffmpegFailed(String)
    case preparedFileNotPlayable
    case processTimedOut(String, TimeInterval, String)

    var errorDescription: String? {
        switch self {
        case .ffmpegMissing:
            "This file is not playable by AVFoundation, and FFmpeg was not found. Install FFmpeg with Homebrew to prepare a fallback MP4."
        case .ffmpegFailed(let output):
            "FFmpeg could not prepare fallback AVFoundation media.\n\(output.trimmedForDisplay(limit: 900))"
        case .preparedFileNotPlayable:
            "The prepared MP4 file still is not playable by AVFoundation."
        case .processTimedOut(let executable, let timeout, let output):
            "\(executable) did not finish within \(Int(timeout)) seconds.\n\(output.trimmedForDisplay(limit: 900))"
        }
    }
}

private final class ProcessRunState: @unchecked Sendable {
    private let lock = NSLock()
    private var output = Data()
    private var didResume = false
    private let continuation: CheckedContinuation<String, Error>

    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        output.append(data)
        lock.unlock()
    }

    func outputString() -> String {
        lock.lock()
        let data = output
        lock.unlock()
        return String(data: data, encoding: .utf8) ?? ""
    }

    func resume(returning value: String) {
        guard markResumed() else { return }
        continuation.resume(returning: value)
    }

    func resume(throwing error: Error) {
        guard markResumed() else { return }
        continuation.resume(throwing: error)
    }

    private func markResumed() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return false }
        didResume = true
        return true
    }
}
