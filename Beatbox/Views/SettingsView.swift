import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    let softwareUpdates: SoftwareUpdateController

    var body: some View {
        Form {
            Section("录音") {
                LabeledContent("音频录制", value: "M4A（AAC）· 48 kHz")
                LabeledContent("录屏", value: "MOV（H.264 + AAC）")
                LabeledContent("当前默认音源") {
                    Label(appModel.selectedSource.name, systemImage: appModel.selectedSource.kind.systemImage)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("可导出格式", value: "AAC、WAV、ALAC、AIFF、CAF、FLAC")
                Button("显示录音文件夹", systemImage: "folder") {
                    appModel.revealRecordingsFolder()
                }
            }

            Section("权限") {
                LabeledContent("麦克风") {
                    Label(microphoneStatus, systemImage: microphoneStatusImage)
                        .foregroundStyle(microphoneStatusColor)
                }
                if appModel.capture.permissionState == .denied
                    || appModel.capture.permissionState == .restricted {
                    Button("打开麦克风隐私设置", systemImage: "gear") {
                        appModel.openMicrophoneSettings()
                    }
                }
                LabeledContent("App 与系统音频") {
                    Label("首次录制时请求", systemImage: "hand.raised.fill")
                        .foregroundStyle(.secondary)
                }
                Button("打开屏幕与系统音频录制设置", systemImage: "gear") {
                    appModel.openSystemAudioSettings()
                }
            }

            Section("本地与隐私") {
                Label(
                    "录音、录屏、KTV 歌曲与歌词默认只保存在这台 Mac。",
                    systemImage: "lock.fill"
                )
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Section("软件更新") {
                LabeledContent("当前版本", value: versionDescription)
                CheckForUpdatesButton(softwareUpdates: softwareUpdates)
                Text("更新通过 GitHub Releases 发布，并由 Sparkle 校验签名后安装。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 540, height: 520)
    }

    private var versionDescription: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        return switch (version, build) {
        case let (.some(version), .some(build)):
            "\(version)（\(build)）"
        case let (.some(version), .none):
            version
        default:
            "未知"
        }
    }

    private var microphoneStatus: String {
        switch appModel.capture.permissionState {
        case .notDetermined: "尚未请求"
        case .authorized: "已允许"
        case .denied: "已拒绝"
        case .restricted: "访问受限"
        }
    }

    private var microphoneStatusImage: String {
        switch appModel.capture.permissionState {
        case .authorized: "checkmark.circle.fill"
        case .notDetermined: "minus.circle"
        case .denied, .restricted: "exclamationmark.triangle.fill"
        }
    }

    private var microphoneStatusColor: Color {
        switch appModel.capture.permissionState {
        case .authorized: .green
        case .notDetermined: .secondary
        case .denied, .restricted: .orange
        }
    }
}
