import CMpv

struct MPVPlaybackState {
    private(set) var wantsPaused = true
    private(set) var reachedEndOfFile = false

    mutating func prepareForLoad() {
        reachedEndOfFile = false
    }

    mutating func prepareForPlay() -> Bool {
        let shouldSeekToStart = reachedEndOfFile
        reachedEndOfFile = false
        wantsPaused = false
        return shouldSeekToStart
    }

    mutating func prepareForPause() {
        wantsPaused = true
    }

    mutating func prepareForSeek() {
        reachedEndOfFile = false
    }

    mutating func handleEndFile(reason: mpv_end_file_reason) {
        guard reason == MPV_END_FILE_REASON_EOF else { return }
        reachedEndOfFile = true
        wantsPaused = true
    }

    mutating func handlePlaybackRestart() {
        reachedEndOfFile = false
    }

    mutating func reset() {
        wantsPaused = true
        reachedEndOfFile = false
    }
}
