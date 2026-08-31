import Foundation
import Testing
@testable import Beatbox

@Suite("KTV 会话状态")
@MainActor
struct KaraokeSessionStateTests {
    @Test("只同步当前跟唱录音的状态")
    func synchronizesOnlyMatchingTake() {
        let songID = UUID()
        let takeID = UUID()
        let unrelatedTakeID = UUID()
        let state = KaraokeSessionState.preparing(songID: songID, takeID: takeID)

        #expect(state.synchronized(with: .recording(unrelatedTakeID)) == state)
        #expect(
            state.synchronized(with: .recording(takeID))
                == .recording(songID: songID, takeID: takeID)
        )
    }

    @Test("失败后保留原因且不再同步其他录音")
    func failureEndsSynchronization() throws {
        let songID = UUID()
        let takeID = UUID()
        let active = KaraokeSessionState.recording(songID: songID, takeID: takeID)
        let failed = active.synchronized(with: .failed(.sourceUnavailable))

        #expect(failed.songID == songID)
        #expect(try #require(failed.failureMessage).contains("音源不可用"))
        #expect(failed.synchronized(with: .recording(UUID())) == failed)
    }
}
