import CMpv
import XCTest
@testable import TahoePlayer

final class MPVPlaybackStateTests: XCTestCase {
    func testReplayAfterEOFSeeksFromStart() {
        var state = MPVPlaybackState()

        state.handleEndFile(reason: MPV_END_FILE_REASON_EOF)

        XCTAssertTrue(state.reachedEndOfFile)
        XCTAssertTrue(state.wantsPaused)
        XCTAssertTrue(state.prepareForPlay())
        XCTAssertFalse(state.reachedEndOfFile)
        XCTAssertFalse(state.wantsPaused)
    }

    func testNonEOFEndFileDoesNotTriggerReplayState() {
        var state = MPVPlaybackState()

        state.handleEndFile(reason: MPV_END_FILE_REASON_STOP)

        XCTAssertFalse(state.reachedEndOfFile)
        XCTAssertTrue(state.wantsPaused)
        XCTAssertFalse(state.prepareForPlay())
    }

    func testSeekClearsEOFStateWithoutChangingPausedState() {
        var state = MPVPlaybackState()

        state.handleEndFile(reason: MPV_END_FILE_REASON_EOF)
        state.prepareForSeek()

        XCTAssertFalse(state.reachedEndOfFile)
        XCTAssertTrue(state.wantsPaused)
    }

    func testPlaybackRestartClearsEOFState() {
        var state = MPVPlaybackState()

        state.handleEndFile(reason: MPV_END_FILE_REASON_EOF)
        state.handlePlaybackRestart()

        XCTAssertFalse(state.reachedEndOfFile)
        XCTAssertTrue(state.wantsPaused)
    }
}
