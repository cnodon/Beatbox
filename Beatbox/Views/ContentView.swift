import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var appModel
    @ObservedObject private var softwareUpdates: SoftwareUpdateController
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @FocusedValue(\.beatboxTextEditing) private var isTextEditing

    init(softwareUpdates: SoftwareUpdateController) {
        self.softwareUpdates = softwareUpdates
    }

    var body: some View {
        @Bindable var appModel = appModel

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 216, max: 260)
        } content: {
            Group {
                if appModel.selectedLibrary == .karaoke {
                    KaraokeSongListView()
                } else {
                    RecordingListView()
                }
            }
            .navigationSplitViewColumnWidth(min: 270, ideal: 310, max: 380)
        } detail: {
            detail
                .frame(minWidth: 400, minHeight: 480)
        }
        .frame(minWidth: 860, minHeight: 560)
        .navigationSplitViewStyle(.balanced)
        .toolbar { toolbar }
        .overlay(alignment: .bottom) {
            if let message = appModel.userMessage {
                MessageBanner(message: message)
                    .padding(.bottom, 16)
                    .padding(.horizontal, 24)
            }
        }
        .sheet(isPresented: Binding(
            get: { !hasCompletedOnboarding },
            set: { if !$0 { hasCompletedOnboarding = true } }
        )) {
            OnboardingView {
                hasCompletedOnboarding = true
            }
        }
        .onKeyPress(.space) {
            guard isTextEditing != true else { return .ignored }
            switch appModel.capture.state {
            case .recording, .paused:
                if appModel.karaokeSessionState.isActive {
                    appModel.toggleKaraokePause()
                } else {
                    appModel.toggleCapturePause()
                }
                return .handled
            default:
                if appModel.selectedLibrary == .karaoke,
                   let song = appModel.selectedKaraokeSong {
                    appModel.toggleKaraokePlayback(for: song)
                    return .handled
                }
                if let recording = appModel.selectedRecording, !recording.isDeleted {
                    appModel.togglePlayback(for: recording)
                    return .handled
                }
                return .ignored
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let activeSong = appModel.activeKaraokeSong,
           appModel.karaokeSessionState.isActive {
            KaraokeDetailView(song: activeSong)
                .id(activeSong.id)
        } else {
            switch appModel.capture.state {
            case .requestingPermission, .preparing, .recording, .paused, .finalizing:
                CaptureView()
            default:
                if appModel.selectedLibrary == .karaoke,
                   let song = appModel.selectedKaraokeSong {
                    KaraokeDetailView(song: song)
                        .id(song.id)
                } else if appModel.selectedLibrary == .karaoke {
                    EmptyKaraokeDetailView()
                } else if let recording = appModel.selectedRecording {
                    RecordingDetailView(recording: recording)
                        .id(recording.id)
                } else {
                    EmptyDetailView(isRecentlyDeleted: appModel.selectedLibrary == .recentlyDeleted)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            SourcePicker()
        }

        ToolbarItem(placement: .secondaryAction) {
            Button {
                softwareUpdates.checkForUpdates()
            } label: {
                Label("检查更新", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!softwareUpdates.canCheckForUpdates)
            .help("检查 Beatbox 更新")
            .accessibilityLabel("检查软件更新")
        }

        if appModel.capture.state.isCapturing {
            ToolbarItem(placement: .primaryAction) {
                CaptureToolbarStatus()
            }
        }
    }
}

private struct CaptureToolbarStatus: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .foregroundStyle(tint)
            .accessibilityLabel("录制状态：\(title)")
            .help("当前录制状态：\(title)")
    }

    private var title: String {
        switch appModel.capture.state {
        case .recording:
            appModel.selectedRecordingMode == .screenAndAudio ? "正在录屏" : "正在录音"
        case .paused: "已暂停"
        case .finalizing: "正在保存"
        case .preparing, .requestingPermission: "正在准备"
        default: appModel.capture.state.statusText
        }
    }

    private var systemImage: String {
        switch appModel.capture.state {
        case .recording: "record.circle.fill"
        case .paused: "pause.circle.fill"
        case .finalizing: "externaldrive.fill.badge.checkmark"
        default: "ellipsis.circle"
        }
    }

    private var tint: Color {
        switch appModel.capture.state {
        case .recording: .red
        case .paused: .orange
        default: .secondary
        }
    }
}

private struct MessageBanner: View {
    @Environment(AppModel.self) private var appModel
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.secondary)
            Text(message)
                .lineLimit(2)
            Spacer(minLength: 12)
            if appModel.lastDeletedRecordingID != nil {
                Button("撤销") { appModel.undoLastDeletion() }
                    .buttonStyle(.borderless)
            }
            if let action = appModel.userMessageAction {
                Button(action.title) { appModel.performMessageAction() }
                    .buttonStyle(.borderless)
            }
            Button {
                appModel.dismissMessage()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("关闭提示")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
        .frame(maxWidth: 560)
    }
}

private struct SourcePicker: View {
    @Environment(AppModel.self) private var appModel

    @ViewBuilder
    var body: some View {
        if appModel.selectedRecordingMode == .screenAndAudio {
            HStack(spacing: 6) {
                Image(systemName: appModel.selectedRecordingMode.systemImage)
                Text("主显示器与系统音频")
                    .lineLimit(1)
            }
                .font(.callout.weight(.medium))
                .foregroundStyle(appModel.capture.state.isCapturing ? .primary : .secondary)
                .padding(.horizontal, 8)
                .fixedSize(horizontal: true, vertical: false)
                .help("录屏模式会捕获主显示器与系统音频")
                .accessibilityLabel("录制来源：主显示器与系统音频")
        } else {
            Menu {
                Section("当前音源") {
                    Label(
                        sourceMenuTitle(appModel.selectedSource),
                        systemImage: appModel.selectedSource.kind.systemImage
                    )
                    .disabled(true)
                }

                Section("麦克风") {
                    ForEach(appModel.microphoneSources) { source in
                        Button {
                            appModel.selectMicrophone(source)
                        } label: {
                            Label {
                                Text(sourceMenuTitle(source))
                            } icon: {
                                Image(systemName: source.id == appModel.selectedSource.id
                                      ? "checkmark.circle.fill"
                                      : "mic")
                            }
                        }
                    }
                    Button("重新扫描麦克风", systemImage: "arrow.clockwise") {
                        appModel.refreshMicrophones(showErrors: true)
                    }
                }

                Section("指定 App") {
                    if appModel.applicationSources.isEmpty {
                        Label("没有检测到正在运行的 App", systemImage: "speaker.slash")
                            .disabled(true)
                    } else {
                        ForEach(appModel.applicationSources) { source in
                            Button {
                                appModel.selectApplication(source)
                            } label: {
                                Label {
                                    Text(sourceMenuTitle(source))
                                } icon: {
                                    Image(systemName: source.id == appModel.selectedSource.id
                                          ? "checkmark.circle.fill"
                                          : "app")
                                }
                            }
                        }
                    }
                    Button("重新扫描 App", systemImage: "arrow.clockwise") {
                        appModel.refreshApplications(showErrors: true)
                    }
                }

                Section("系统") {
                    unavailableSource(.systemPreview)
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: appModel.selectedSource.kind.systemImage)
                    Text(appModel.selectedSource.name)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .font(.callout.weight(.medium))
                .frame(maxWidth: 220)
                .fixedSize(horizontal: true, vertical: false)
            }
            .menuIndicator(.hidden)
            .disabled(appModel.capture.state.isCapturing)
            .help(appModel.capture.state.isCapturing ? "结束当前录音后可更换音源" : "选择音源")
            .accessibilityLabel("录音音源：\(appModel.selectedSource.name)")
            .accessibilityHint(appModel.capture.state.isCapturing ? "结束当前录音后可以更换" : "打开音源菜单")
            .onAppear {
                appModel.refreshMicrophones()
                appModel.refreshApplications()
            }
        }
    }

    private func sourceMenuTitle(_ source: AudioSource) -> String {
        guard let detail = source.detail else { return source.name }
        return "\(source.name) · \(detail)"
    }

    private func unavailableSource(_ source: AudioSource) -> some View {
        Label(
            "\(source.name) · \(source.unavailableReason ?? "不可用")",
            systemImage: "lock.fill"
        )
        .disabled(true)
    }
}
