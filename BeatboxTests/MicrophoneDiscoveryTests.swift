import Testing
@testable import Beatbox

@Suite("麦克风发现与选择")
@MainActor
struct MicrophoneDiscoveryTests {
    @Test
    func discoveredMicrophonesHaveStableUniqueIdentities() throws {
        let devices = try MicrophoneDiscovery().devices()

        #expect(Set(devices.map(\.id)).count == devices.count)
        #expect(devices.allSatisfy { !$0.id.isEmpty })
        #expect(devices.allSatisfy { !$0.name.isEmpty })
        #expect(devices.filter(\.isDefault).count <= 1)
    }

    @Test
    func audioSourcePreservesTheCoreAudioDeviceIdentity() {
        let device = MicrophoneDevice(
            id: "test-device-uid",
            audioDeviceID: 42,
            name: "测试 USB 麦克风",
            transport: .usb,
            isDefault: true
        )

        let source = AudioSource.microphone(device)

        #expect(source.id == "microphone:test-device-uid")
        #expect(source.audioDeviceID == 42)
        #expect(source.name == "测试 USB 麦克风")
        #expect(source.detail == "USB · 系统默认")
    }
}
