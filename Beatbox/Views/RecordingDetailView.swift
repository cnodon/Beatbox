import AVKit
import SwiftUI

struct RecordingDetailView: View {
    @Environment(AppModel.self) private var appModel
    let recording: Recording

    @State private var titleDraft: String
    @State private var showingPermanentDeleteConfirmation = false
    @FocusState private var isEditingTitle: Bool

    init(recording: Recording) {
        self.recording = recording
        _titleDraft = State(initialValue: recording.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: recording.recordingMode.systemImage)
                    .font(.title2)
                    .foregroundStyle(recording.isDeleted ? Color.secondary : Color.accentColor)
                    .frame(width: 34, height: 34)
                    .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    TextField("录音名称", text: $titleDraft)
                        .textFieldStyle(.plain)
                        .font(.title2.weight(.semibold))
                        .focused($isEditingTitle)
                        .focusedValue(\.beatboxTextEditing, true)
                        .disabled(recording.isDeleted)
                        .accessibilityLabel("录制名称")
                        .accessibilityHint(recording.isDeleted ? "恢复后可以重命名" : "按 Return 保存，按 Escape 取消")
                        .onSubmit { commitTitle() }
                        .onExitCommand {
                            titleDraft = recording.title
                            isEditingTitle = false
                        }

                    Text(recording.recordingMode == .screenAndAudio ? "录屏与系统音频" : "音频录制")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if recording.integrity == .recovered {
                    Label("已恢复", systemImage: "wrench.and.screwdriver.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("这段内容由 Beatbox 从未完成文件中恢复")
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 7) {
                    metadataItems
                }
                VStack(alignment: .leading, spacing: 5) {
                    Label(recording.sourceName, systemImage: recording.sourceKind.systemImage)
                    Text("\(recording.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(recording.fileSize.beatboxFileSize) · \(recording.recordingMode.fileFormatTitle)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if recording.recordingMode == .screenAndAudio {
                screenRecordingPlayer
            } else {
                audioRecordingPlayer
            }

            Divider()

            if recording.isDeleted {
                HStack {
                    Button("恢复") { appModel.restore(recording) }
                        .buttonStyle(.borderedProminent)
                    Button("立即删除…", role: .destructive) {
                        showingPermanentDeleteConfirmation = true
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: 10) {
                    Button(appModel.isExporting(recording) ? "正在导出…" : "导出为…") {
                        appModel.export(recording)
                    }
                        .buttonStyle(.borderedProminent)
                        .disabled(appModel.isExporting)
                    Button("在 Finder 中显示") { appModel.reveal(recording) }
                        .help("在 Finder 中选中原始文件")
                    ShareLink(item: appModel.fileURL(for: recording)) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    Spacer()
                    Button("移到最近删除", role: .destructive) {
                        appModel.moveToRecentlyDeleted(recording)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(28)
        .confirmationDialog(
            "永久删除“\(recording.title)”？",
            isPresented: $showingPermanentDeleteConfirmation
        ) {
            Button("永久删除", role: .destructive) {
                appModel.deletePermanently(recording)
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作无法撤销。")
        }
    }

    @ViewBuilder
    private var metadataItems: some View {
        Label(recording.sourceName, systemImage: recording.sourceKind.systemImage)
        Text("·")
        Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
        Text("·")
        Text(recording.fileSize.beatboxFileSize)
        Text("·")
        Text(recording.recordingMode.fileFormatTitle)
    }

    private var screenRecordingPlayer: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScreenRecordingPlayer(url: appModel.fileURL(for: recording))
                .id(recording.id)
                .aspectRatio(16 / 9, contentMode: .fit)
                .frame(minHeight: 220, maxHeight: 420)
                .background(.black, in: RoundedRectangle(cornerRadius: 10))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel("录屏播放器，\(recording.title)")

            Label(
                "录屏包含主显示器画面与系统音频",
                systemImage: "rectangle.inset.filled.and.person.filled"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var audioRecordingPlayer: some View {
        VStack(alignment: .leading, spacing: 16) {
            WaveformScrubber(
                samples: recording.waveformSamples,
                currentTime: playbackTime,
                duration: recording.duration
            ) { time in
                preparePlaybackIfNeeded()
                appModel.playback.seek(to: time)
            }
            .frame(height: 112)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))

            HStack {
                Text(playbackTime.beatboxTimestamp)
                Spacer()
                Text(recording.duration.beatboxTimestamp)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Spacer()
                Button { appModel.playback.skip(by: -15) } label: {
                    Label("后退 15 秒", systemImage: "gobackward.15")
                        .labelStyle(.iconOnly)
                }
                .help("后退 15 秒")
                .disabled(!isCurrentPlayback)

                Button {
                    appModel.togglePlayback(for: recording)
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .controlSize(.large)
                .accessibilityLabel(isPlaying ? "暂停播放" : "播放录音")

                Button { appModel.playback.skip(by: 15) } label: {
                    Label("前进 15 秒", systemImage: "goforward.15")
                        .labelStyle(.iconOnly)
                }
                .help("前进 15 秒")
                .disabled(!isCurrentPlayback)
                Spacer()
            }

            HStack(spacing: 16) {
                Picker("速度", selection: Binding(
                    get: { appModel.playback.rate },
                    set: { appModel.playback.rate = $0 }
                )) {
                    Text("0.75×").tag(Float(0.75))
                    Text("1×").tag(Float(1))
                    Text("1.25×").tag(Float(1.25))
                    Text("1.5×").tag(Float(1.5))
                    Text("2×").tag(Float(2))
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .accessibilityValue("\(appModel.playback.rate, format: .number) 倍")

                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(appModel.playback.volume) },
                    set: { appModel.playback.volume = Float($0) }
                ), in: 0...1)
                .frame(maxWidth: 180)
                .accessibilityLabel("播放音量")

                Spacer()
            }
        }
    }

    private var isCurrentPlayback: Bool {
        appModel.playback.state.recordingID == recording.id
    }

    private var isPlaying: Bool {
        if case .playing(recording.id) = appModel.playback.state { return true }
        return false
    }

    private var playbackTime: TimeInterval {
        isCurrentPlayback ? appModel.playback.currentTime : 0
    }

    private func commitTitle() {
        appModel.saveTitle(for: recording, title: titleDraft)
        titleDraft = recording.title
        isEditingTitle = false
    }

    private func preparePlaybackIfNeeded() {
        guard !isCurrentPlayback else { return }
        appModel.playback.play(id: recording.id, url: appModel.fileURL(for: recording))
        appModel.playback.pause()
    }
}

private struct ScreenRecordingPlayer: View {
    @State private var player: AVPlayer

    init(url: URL) {
        _player = State(initialValue: AVPlayer(url: url))
    }

    var body: some View {
        NativeVideoPlayer(player: player)
            .onDisappear {
                player.pause()
            }
    }
}

private struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .floating
        view.videoGravity = .resizeAspect
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player = player
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

struct EmptyDetailView: View {
    @Environment(AppModel.self) private var appModel
    let isRecentlyDeleted: Bool

    var body: some View {
        ContentUnavailableView {
            Label(
                isRecentlyDeleted ? "没有最近删除的录音" : "选择或创建一段录音",
                systemImage: isRecentlyDeleted ? "trash" : "waveform.circle"
            )
        } description: {
            Text(isRecentlyDeleted
                 ? "删除的录音会显示在这里。"
                 : "在左侧选择录制类型，确认工具栏中的来源，然后开始录制。")
        }
    }
}
