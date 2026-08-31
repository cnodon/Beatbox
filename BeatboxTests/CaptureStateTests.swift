import Foundation
import Testing
@testable import Beatbox

@Suite("录音状态机")
@MainActor
struct CaptureStateTests {
    @Test
    func testIdleCanStartAndDoesNotCapture() {
        #expect(CaptureState.idle.canStart)
        #expect(!CaptureState.idle.isCapturing)
        #expect(CaptureState.idle.recordingID == nil)
    }

    @Test
    func testActiveStatesRetainRecordingIdentity() {
        let id = UUID()
        let states: [CaptureState] = [
            .preparing(id),
            .recording(id),
            .paused(id),
            .finalizing(id),
        ]

        for state in states {
            #expect(state.recordingID == id)
            #expect(state.isCapturing)
            #expect(!state.canStart)
        }

        #expect(CaptureState.preparing(id).canStop)
        #expect(CaptureState.recording(id).canStop)
        #expect(CaptureState.paused(id).canStop)
        #expect(!CaptureState.finalizing(id).canStop)
    }

    @Test
    func testCompletedStateAllowsNextRecording() {
        let state = CaptureState.completed(UUID())

        #expect(state.canStart)
        #expect(!state.isCapturing)
    }

    @Test
    func systemAudioPermissionFailureProvidesAnActionableRecoveryPath() {
        let failure = CaptureFailure.systemAudioPermissionDenied

        #expect(failure.title.contains("系统音频"))
        #expect(failure.recoverySuggestion.contains("屏幕与系统音频录制"))
    }

    @Test
    func sourceUnavailableFailureDoesNotDescribeAnEmptyFileAsSaved() {
        let failure = CaptureFailure.sourceUnavailable

        #expect(failure.title == "音源不可用")
        #expect(failure.recoverySuggestion.contains("可用的音源"))
    }

    @Test
    func insufficientStorageFailureProvidesConcreteCapacityGuidance() {
        let failure = CaptureFailure.insufficientStorage

        #expect(failure.title == "磁盘空间不足")
        #expect(failure.recoverySuggestion.contains("2 GB"))
        #expect(failure.recoverySuggestion.contains("256 MB"))
    }
}
