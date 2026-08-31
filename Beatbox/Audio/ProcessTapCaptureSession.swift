@preconcurrency import AVFAudio
import CoreAudio
import Foundation

enum ProcessTapCaptureError: Error, Equatable, Sendable {
    case emptyProcessList
    case coreAudio(operation: String, status: OSStatus)

    var isPermissionDenied: Bool {
        guard case let .coreAudio(_, status) = self else { return false }
        return status == kAudioDevicePermissionsError
    }
}

nonisolated final class ProcessTapCaptureSession {
    private(set) var tapID = AudioObjectID(kAudioObjectUnknown)
    private(set) var aggregateDeviceID = AudioObjectID(kAudioObjectUnknown)
    private(set) var inputFormat: AVAudioFormat?
    private var ioProcID: AudioDeviceIOProcID?
    private var tapUUID: UUID?
    private var hasDestroyedResources = false

    init(
        processObjectIDs: [AudioObjectID],
        bundleIdentifiers _: [String] = []
    ) throws {
        guard !processObjectIDs.isEmpty else {
            throw ProcessTapCaptureError.emptyProcessList
        }

        do {
            try createTap(processObjectIDs: processObjectIDs)
            try createAggregateDevice()
            inputFormat = try readTapFormat()
        } catch {
            destroy()
            throw error
        }
    }

    func destroy() {
        guard !hasDestroyedResources else { return }
        hasDestroyedResources = true

        stopIO()

        if aggregateDeviceID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateDeviceID)
            aggregateDeviceID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }

    func startIO(audioSink: CaptureAudioSink) throws {
        guard ioProcID == nil, let inputFormat else { return }

        var createdIOProcID: AudioDeviceIOProcID?
        let status = AudioDeviceCreateIOProcIDWithBlock(
            &createdIOProcID,
            aggregateDeviceID,
            nil
        ) { _, inputData, _, _, _ in
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                bufferListNoCopy: inputData,
                deallocator: nil
            ) else { return }
            audioSink.consume(buffer)
        }
        try check(status, operation: "创建 App 音频读取回调")
        guard let createdIOProcID else {
            throw ProcessTapCaptureError.coreAudio(
                operation: "创建 App 音频读取回调",
                status: kAudioHardwareUnspecifiedError
            )
        }
        ioProcID = createdIOProcID

        do {
            try startIO()
        } catch {
            AudioDeviceDestroyIOProcID(aggregateDeviceID, createdIOProcID)
            ioProcID = nil
            throw error
        }
    }

    func pauseIO() {
        guard let ioProcID else { return }
        AudioDeviceStop(aggregateDeviceID, ioProcID)
    }

    func resumeIO() throws {
        try startIO()
    }

    func stopIO() {
        guard let ioProcID else { return }
        AudioDeviceStop(aggregateDeviceID, ioProcID)
        AudioDeviceDestroyIOProcID(aggregateDeviceID, ioProcID)
        self.ioProcID = nil
    }

    private func createTap(processObjectIDs: [AudioObjectID]) throws {
        let description = CATapDescription(stereoMixdownOfProcesses: processObjectIDs)
        description.name = "Beatbox App Audio"
        description.uuid = UUID()
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var createdTapID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateProcessTap(description, &createdTapID)
        try check(status, operation: "创建 App 音频 Tap")
        tapID = createdTapID
        tapUUID = description.uuid
    }

    private func createAggregateDevice() throws {
        guard let tapUUID else {
            throw ProcessTapCaptureError.coreAudio(
                operation: "读取 App 音频 Tap 标识",
                status: kAudioHardwareUnspecifiedError
            )
        }
        let outputDeviceID = try defaultSystemOutputDevice()
        let outputDeviceUID = try stringProperty(
            objectID: outputDeviceID,
            selector: kAudioDevicePropertyDeviceUID
        )
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Beatbox App Audio Input",
            kAudioAggregateDeviceUIDKey: "com.tokenplay.beatbox.tap.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputDeviceUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [
                [kAudioSubDeviceUIDKey: outputDeviceUID],
            ],
            kAudioAggregateDeviceTapListKey: [
                [
                    kAudioSubTapUIDKey: tapUUID.uuidString,
                    kAudioSubTapDriftCompensationKey: true,
                ],
            ],
        ]
        var createdDeviceID = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(
            description as CFDictionary,
            &createdDeviceID
        )
        try check(status, operation: "创建 App 音频输入设备")
        aggregateDeviceID = createdDeviceID
    }

    private func readTapFormat() throws -> AVAudioFormat {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var streamDescription = AudioStreamBasicDescription()
        var dataSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        let status = AudioObjectGetPropertyData(
            tapID,
            &address,
            0,
            nil,
            &dataSize,
            &streamDescription
        )
        try check(status, operation: "读取 App 音频格式")
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw ProcessTapCaptureError.coreAudio(
                operation: "读取 App 音频格式",
                status: kAudioDeviceUnsupportedFormatError
            )
        }
        return format
    }

    private func startIO() throws {
        guard let ioProcID else {
            throw ProcessTapCaptureError.coreAudio(
                operation: "启动 App 音频读取",
                status: kAudioHardwareNotReadyError
            )
        }
        try check(
            AudioDeviceStart(aggregateDeviceID, ioProcID),
            operation: "启动 App 音频读取"
        )
    }

    private func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &dataSize,
            &value
        )
        try check(status, operation: "读取 App 音频 Tap")
        guard let value else {
            throw ProcessTapCaptureError.coreAudio(
                operation: "读取 App 音频 Tap",
                status: kAudioHardwareUnspecifiedError
            )
        }
        return value.takeUnretainedValue() as String
    }

    private func defaultSystemOutputDevice() throws -> AudioDeviceID {
        let systemObjectID = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultSystemOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            systemObjectID,
            &address,
            0,
            nil,
            &dataSize,
            &deviceID
        )
        try check(status, operation: "读取系统默认输出设备")
        guard deviceID != kAudioObjectUnknown else {
            throw ProcessTapCaptureError.coreAudio(
                operation: "读取系统默认输出设备",
                status: kAudioHardwareBadDeviceError
            )
        }
        return deviceID
    }

    private func check(_ status: OSStatus, operation: String) throws {
        guard status == noErr else {
            throw ProcessTapCaptureError.coreAudio(operation: operation, status: status)
        }
    }
}
