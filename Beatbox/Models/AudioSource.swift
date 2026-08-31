import Foundation

enum AudioSourceKind: String, Codable, CaseIterable, Sendable {
    case microphone
    case application
    case system

    var title: String {
        switch self {
        case .microphone: "麦克风"
        case .application: "指定 App"
        case .system: "系统音频"
        }
    }

    var systemImage: String {
        switch self {
        case .microphone: "mic.fill"
        case .application: "app.fill"
        case .system: "macbook.and.iphone"
        }
    }
}

struct AudioSource: Identifiable, Hashable, Sendable {
    let id: String
    let kind: AudioSourceKind
    let name: String
    let isAvailable: Bool
    let unavailableReason: String?
    let audioDeviceID: UInt32?
    let processObjectIDs: [UInt32]
    let bundleIdentifier: String?
    let applicationURL: URL?
    let detail: String?

    static let defaultMicrophone = AudioSource(
        id: "default-microphone",
        kind: .microphone,
        name: "系统默认麦克风",
        isAvailable: true,
        unavailableReason: nil,
        audioDeviceID: nil,
        processObjectIDs: [],
        bundleIdentifier: nil,
        applicationURL: nil,
        detail: "跟随 macOS 默认输入"
    )

    static let applicationPreview = AudioSource(
        id: "application-audio",
        kind: .application,
        name: "指定 App",
        isAvailable: false,
        unavailableReason: "系统音频捕获将在下一阶段接入",
        audioDeviceID: nil,
        processObjectIDs: [],
        bundleIdentifier: nil,
        applicationURL: nil,
        detail: nil
    )

    static let systemPreview = AudioSource(
        id: "system-audio",
        kind: .system,
        name: "整个系统音频",
        isAvailable: false,
        unavailableReason: "系统音频捕获将在下一阶段接入",
        audioDeviceID: nil,
        processObjectIDs: [],
        bundleIdentifier: nil,
        applicationURL: nil,
        detail: nil
    )

    static func microphone(_ device: MicrophoneDevice) -> AudioSource {
        AudioSource(
            id: "microphone:\(device.id)",
            kind: .microphone,
            name: device.name,
            isAvailable: true,
            unavailableReason: nil,
            audioDeviceID: device.audioDeviceID,
            processObjectIDs: [],
            bundleIdentifier: nil,
            applicationURL: nil,
            detail: device.isDefault
                ? "\(device.transport.title) · 系统默认"
                : device.transport.title
        )
    }

    static func application(_ device: ApplicationAudioDevice) -> AudioSource {
        AudioSource(
            id: device.id,
            kind: .application,
            name: device.name,
            isAvailable: true,
            unavailableReason: nil,
            audioDeviceID: nil,
            processObjectIDs: device.processObjectIDs,
            bundleIdentifier: device.bundleIdentifier,
            applicationURL: device.bundleURL,
            detail: "正在输出音频"
        )
    }

    var captureInput: CaptureInput? {
        switch kind {
        case .microphone:
            .microphone(deviceID: audioDeviceID)
        case .application where !processObjectIDs.isEmpty:
            .application(
                processObjectIDs: processObjectIDs,
                bundleIdentifiers: bundleIdentifier.map { [$0] } ?? []
            )
        case .application, .system:
            nil
        }
    }
}
