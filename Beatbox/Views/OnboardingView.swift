import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel
    let completion: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 9) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.tint)
                Text("欢迎使用 Beatbox")
                    .font(.largeTitle.bold())
                Text("选择一种来源，一次操作就能可靠地录下来。")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Label("录音与歌曲默认只保存在这台 Mac", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("按需授权")
                    .font(.headline)

                permissionCard(
                    title: "麦克风",
                    description: "录制内建、USB 或其他输入设备。",
                    systemImage: "mic.fill",
                    status: microphoneStatus,
                    statusImage: microphoneStatusImage,
                    statusColor: microphoneStatusColor,
                    actionTitle: microphoneActionTitle
                ) {
                    switch appModel.capture.permissionState {
                    case .denied, .restricted:
                        appModel.openMicrophoneSettings()
                    case .authorized:
                        break
                    case .notDetermined:
                        Task { _ = await appModel.requestMicrophonePermission() }
                    }
                }

                permissionCard(
                    title: "系统与 App 音频",
                    description: "录制你选择的 App，或在录屏时捕获系统音频。",
                    systemImage: "macbook.and.iphone",
                    status: "开始 App 录音时由 macOS 请求",
                    statusImage: "hand.raised.fill",
                    statusColor: .secondary,
                    actionTitle: nil,
                    action: {}
                )
            }

            Button("进入 Beatbox") { completion() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

            Text("也可以稍后在系统设置中更改权限。")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(36)
        .frame(width: 580)
        .interactiveDismissDisabled()
    }

    private func permissionCard(
        title: String,
        description: String,
        systemImage: String,
        status: String,
        statusImage: String,
        statusColor: Color,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title2)
                .frame(width: 34)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).fontWeight(.semibold)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Label(status, systemImage: statusImage)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            Spacer(minLength: 12)
            if let actionTitle {
                Button(actionTitle, action: action)
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var microphoneStatus: String {
        switch appModel.capture.permissionState {
        case .notDetermined: "尚未请求"
        case .authorized: "已允许"
        case .denied: "已拒绝"
        case .restricted: "访问受限"
        }
    }

    private var microphoneActionTitle: String? {
        switch appModel.capture.permissionState {
        case .notDetermined: "允许访问"
        case .authorized: nil
        case .denied, .restricted: "打开系统设置"
        }
    }

    private var microphoneStatusImage: String {
        switch appModel.capture.permissionState {
        case .authorized: "checkmark.circle.fill"
        case .denied, .restricted: "exclamationmark.triangle.fill"
        case .notDetermined: "minus.circle"
        }
    }

    private var microphoneStatusColor: Color {
        switch appModel.capture.permissionState {
        case .authorized: .green
        case .denied, .restricted: .orange
        case .notDetermined: .secondary
        }
    }
}
