import CoreAudio
import Foundation

enum MicrophoneTransport: String, Sendable {
    case builtIn
    case usb
    case bluetooth
    case aggregate
    case virtual
    case other

    var title: String {
        switch self {
        case .builtIn: "内建"
        case .usb: "USB"
        case .bluetooth: "蓝牙"
        case .aggregate: "聚合设备"
        case .virtual: "虚拟设备"
        case .other: "音频输入"
        }
    }

    var systemImage: String {
        switch self {
        case .builtIn: "macbook"
        case .usb: "cable.connector"
        case .bluetooth: "wave.3.right"
        case .aggregate: "square.stack.3d.up"
        case .virtual: "waveform.badge.mic"
        case .other: "mic"
        }
    }
}

struct MicrophoneDevice: Identifiable, Hashable, Sendable {
    let id: String
    let audioDeviceID: UInt32
    let name: String
    let transport: MicrophoneTransport
    let isDefault: Bool
}

enum MicrophoneDiscoveryError: LocalizedError {
    case coreAudio(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .coreAudio(status):
            "无法读取麦克风设备（Core Audio 错误 \(status)）。"
        }
    }
}

struct MicrophoneDiscovery {
    func devices() throws -> [MicrophoneDevice] {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        let defaultInputID = try? uint32Property(
            objectID: systemObject,
            selector: kAudioHardwarePropertyDefaultInputDevice
        )

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize))

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        guard deviceCount > 0 else { return [] }
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)
        let status = deviceIDs.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return kAudioHardwareUnspecifiedError
            }
            return AudioObjectGetPropertyData(
                systemObject,
                &address,
                0,
                nil,
                &dataSize,
                baseAddress
            )
        }
        try check(status)

        let microphones = deviceIDs.compactMap { deviceID -> MicrophoneDevice? in
            guard (try? hasInputStreams(deviceID)) == true,
                  (try? uint32Property(
                    objectID: deviceID,
                    selector: kAudioDevicePropertyDeviceIsAlive
                  )) != 0,
                  let id = try? stringProperty(
                    objectID: deviceID,
                    selector: kAudioDevicePropertyDeviceUID
                  ),
                  let name = try? stringProperty(
                    objectID: deviceID,
                    selector: kAudioObjectPropertyName
                  )
            else { return nil }

            return MicrophoneDevice(
                id: id,
                audioDeviceID: deviceID,
                name: name,
                transport: (try? transport(for: deviceID)) ?? .other,
                isDefault: deviceID == defaultInputID
            )
        }

        return microphones.sorted { left, right in
            if left.isDefault != right.isDefault { return left.isDefault }
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
    }

    private func hasInputStreams(_ deviceID: AudioDeviceID) throws -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize))
        return dataSize >= MemoryLayout<AudioStreamID>.size
    }

    private func transport(for deviceID: AudioDeviceID) throws -> MicrophoneTransport {
        let value = try uint32Property(
            objectID: deviceID,
            selector: kAudioDevicePropertyTransportType
        )
        switch value {
        case kAudioDeviceTransportTypeBuiltIn:
            return .builtIn
        case kAudioDeviceTransportTypeUSB:
            return .usb
        case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
            return .bluetooth
        case kAudioDeviceTransportTypeAggregate:
            return .aggregate
        case kAudioDeviceTransportTypeVirtual:
            return .virtual
        default:
            return .other
        }
    }

    private func uint32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value))
        return value
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
        try check(AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value))
        guard let value else { throw MicrophoneDiscoveryError.coreAudio(kAudioHardwareUnspecifiedError) }
        return value.takeUnretainedValue() as String
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else { throw MicrophoneDiscoveryError.coreAudio(status) }
    }
}
