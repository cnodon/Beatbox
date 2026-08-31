import Foundation

enum MicrophonePermissionState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

enum InputSignalHealth: Equatable, Sendable {
    case preparing
    case healthy
    case low
    case silent
    case clipping
    case paused
}

enum CaptureFailure: Error, Equatable, Sendable {
    case permissionDenied
    case systemAudioPermissionDenied
    case sourceUnavailable
    case unableToPrepare
    case unableToStart
    case insufficientStorage
    case unableToFinalize(String)

    var title: String {
        switch self {
        case .permissionDenied: "没有麦克风权限"
        case .systemAudioPermissionDenied: "没有系统音频录制权限"
        case .sourceUnavailable: "音源不可用"
        case .unableToPrepare: "无法准备录音"
        case .unableToStart: "无法开始录音"
        case .insufficientStorage: "磁盘空间不足"
        case .unableToFinalize: "无法完成录音"
        }
    }

    var recoverySuggestion: String {
        switch self {
        case .permissionDenied:
            "请在系统设置的“隐私与安全性 > 麦克风”中允许 Beatbox。"
        case .systemAudioPermissionDenied:
            "请在系统设置的“隐私与安全性 > 屏幕与系统音频录制”中允许 Beatbox，然后重新打开应用。"
        case .sourceUnavailable:
            "请选择一个当前可用的音源后重试。"
        case .unableToPrepare, .unableToStart:
            "请检查输入设备和磁盘空间，然后重试。"
        case .insufficientStorage:
            "请先释放磁盘空间；录屏建议至少保留 2 GB，录音建议至少保留 256 MB。"
        case .unableToFinalize:
            "Beatbox 已保留未完成文件。请显示录音文件夹后尝试恢复。"
        }
    }
}

enum CaptureState: Equatable, Sendable {
    case idle
    case requestingPermission
    case preparing(UUID)
    case recording(UUID)
    case paused(UUID)
    case finalizing(UUID)
    case completed(UUID)
    case failed(CaptureFailure)

    var recordingID: UUID? {
        switch self {
        case let .preparing(id), let .recording(id), let .paused(id),
             let .finalizing(id), let .completed(id):
            id
        case .idle, .requestingPermission, .failed:
            nil
        }
    }

    var isCapturing: Bool {
        switch self {
        case .preparing, .recording, .paused, .finalizing:
            true
        case .idle, .requestingPermission, .completed, .failed:
            false
        }
    }

    var canStart: Bool {
        switch self {
        case .idle, .completed, .failed:
            true
        case .requestingPermission, .preparing, .recording, .paused, .finalizing:
            false
        }
    }

    var canStop: Bool {
        switch self {
        case .preparing, .recording, .paused:
            true
        case .idle, .requestingPermission, .finalizing, .completed, .failed:
            false
        }
    }

    var statusText: String {
        switch self {
        case .idle: "就绪"
        case .requestingPermission: "等待麦克风权限…"
        case .preparing: "正在准备音源…"
        case .recording: "正在录音"
        case .paused: "已暂停"
        case .finalizing: "正在保存…"
        case .completed: "已保存"
        case let .failed(failure): failure.title
        }
    }
}

struct CaptureResult: Sendable {
    let id: UUID
    let fileURL: URL
    let duration: TimeInterval
    let fileSize: Int64
    let waveformSamples: [Float]
}
