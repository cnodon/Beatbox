import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        List(selection: Binding<LibrarySection?>(
            get: { appModel.selectedLibrary },
            set: { if let section = $0 { appModel.selectedLibrary = section } }
        )) {
            Section("资料库") {
                ForEach([LibrarySection.all, .recentlyDeleted]) { section in
                    HStack(spacing: 8) {
                        Label(section.title, systemImage: section.systemImage)
                        Spacer()
                        Text(appModel.recordingCount(in: section), format: .number)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                        .tag(section)
                }
            }
            Section("实验功能") {
                HStack(spacing: 8) {
                    Label(
                        "KTV · 歌曲",
                        systemImage: LibrarySection.karaoke.systemImage
                    )
                    Spacer()
                    Text(appModel.recordingCount(in: .karaoke), format: .number)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Text("实验")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                .tag(LibrarySection.karaoke)
                .accessibilityLabel("KTV 歌曲，实验功能，\(appModel.recordingCount(in: .karaoke)) 首歌曲")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Beatbox")
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("新建录制")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("⇧⌘R")
                            .font(.caption.monospaced())
                            .foregroundStyle(.tertiary)
                    }

                    Picker("录制类型", selection: $appModel.selectedRecordingMode) {
                        ForEach(RecordingMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .disabled(appModel.capture.state.isCapturing)
                    .accessibilityLabel("录制类型")
                    .accessibilityValue(appModel.selectedRecordingMode.title)

                    Label(captureTargetTitle, systemImage: captureTargetImage)
                        .font(.caption)
                        .foregroundStyle(isSelectedModeAvailable ? Color.secondary : Color.orange)
                        .lineLimit(1)
                        .help(captureTargetTitle)

                    if appModel.capture.state.isCapturing {
                        Label(activeCaptureTitle, systemImage: activeCaptureImage)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(activeCaptureColor)
                            .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                            .accessibilityLabel("录制状态：\(activeCaptureTitle)")
                    } else {
                        Button {
                            Task { await appModel.startRecording() }
                        } label: {
                            Label(
                                "开始\(appModel.selectedRecordingMode.title)",
                                systemImage: "record.circle.fill"
                            )
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(.red)
                        .disabled(!appModel.canStartRecording)
                        .help(recordButtonHelp)
                        .accessibilityLabel(recordButtonHelp)
                        .accessibilityHint("快捷键 Shift Command R")
                    }
                }
                .padding(12)
            }
            .background(.bar)
        }
    }

    private var captureTargetTitle: String {
        if !isSelectedModeAvailable { return "录屏需要 macOS 15 或更高版本" }
        return appModel.selectedRecordingMode == .screenAndAudio
            ? "主显示器与系统音频"
            : appModel.selectedSource.name
    }

    private var captureTargetImage: String {
        if !isSelectedModeAvailable { return "exclamationmark.triangle.fill" }
        return appModel.selectedRecordingMode == .screenAndAudio
            ? appModel.selectedRecordingMode.systemImage
            : appModel.selectedSource.kind.systemImage
    }

    private var isSelectedModeAvailable: Bool {
        appModel.selectedRecordingMode == .audio
            || ProcessInfo.processInfo.isOperatingSystemAtLeast(
                OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
            )
    }

    private var activeCaptureTitle: String {
        switch appModel.capture.state {
        case .recording:
            appModel.selectedRecordingMode == .screenAndAudio ? "录屏进行中" : "录音进行中"
        case .paused: "录音已暂停"
        case .finalizing: "正在保存"
        case .preparing, .requestingPermission: "正在准备"
        default: appModel.capture.state.statusText
        }
    }

    private var activeCaptureImage: String {
        switch appModel.capture.state {
        case .recording: "record.circle.fill"
        case .paused: "pause.circle.fill"
        case .finalizing: "externaldrive.fill.badge.checkmark"
        default: "ellipsis.circle"
        }
    }

    private var activeCaptureColor: Color {
        switch appModel.capture.state {
        case .recording: .red
        case .paused: .orange
        default: .secondary
        }
    }

    private var recordButtonHelp: String {
        if appModel.capture.state.isCapturing { return "录制正在进行中" }
        if appModel.selectedRecordingMode == .screenAndAudio {
            return isSelectedModeAvailable
                ? "录制主显示器画面与系统音频"
                : "录屏需要 macOS 15 或更高版本"
        }
        return "使用 \(appModel.selectedSource.name) 开始录音"
    }
}
