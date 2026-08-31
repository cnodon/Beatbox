import CoreAudio
import Foundation
import Testing
@testable import Beatbox

@Suite("App 音频发现与选择")
@MainActor
struct ApplicationAudioDiscoveryTests {
    @Test
    func discoveredApplicationsHaveUniqueStableIdentities() throws {
        let applications = try ApplicationAudioDiscovery().applications()

        #expect(Set(applications.map(\.id)).count == applications.count)
        #expect(applications.allSatisfy { !$0.id.isEmpty })
        #expect(applications.allSatisfy { !$0.name.isEmpty })
        #expect(applications.allSatisfy { !$0.processObjectIDs.isEmpty })
    }

    @Test
    func audioSourcePreservesAllProcessObjectsForAnApplication() throws {
        let application = ApplicationAudioDevice(
            id: "application:com.example.player",
            name: "Example Player",
            bundleIdentifier: "com.example.player",
            bundleURL: URL(fileURLWithPath: "/Applications/Example Player.app"),
            processObjectIDs: [31, 17]
        )

        let source = AudioSource.application(application)

        #expect(source.kind == .application)
        #expect(source.processObjectIDs == [31, 17])
        #expect(source.bundleIdentifier == "com.example.player")
        let input = try #require(source.captureInput)
        #expect(input == .application(
            processObjectIDs: [31, 17],
            bundleIdentifiers: ["com.example.player"]
        ))
    }

    @Test
    func processTapPermissionFailureIsRecognized() {
        let error = ProcessTapCaptureError.coreAudio(
            operation: "测试",
            status: kAudioDevicePermissionsError
        )

        #expect(error.isPermissionDenied)
        #expect(!ProcessTapCaptureError.emptyProcessList.isPermissionDenied)
    }
}
