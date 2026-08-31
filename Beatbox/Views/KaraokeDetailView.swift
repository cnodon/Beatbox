import SwiftUI

struct KaraokeDetailView: View {
    @Environment(AppModel.self) private var appModel
    let song: KaraokeSong

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            lyricsStage
            Divider()
            transport
        }
        .background(.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.title2.weight(.semibold))
                        .lineLimit(1)
                    Text(song.artist)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                sessionStatus
            }

            HStack(spacing: 7) {
                Label("原唱音频", systemImage: "music.note")
                Text("·")
                Text(song.sourceFormat)
                Text("·")
                Text(song.fileSize.beatboxFileSize)
                Text("·")
                Label(
                    song.lyricCues.isEmpty ? "无歌词" : "逐行歌词 · \(song.lyricCues.count) 个时间点",
                    systemImage: song.lyricCues.isEmpty ? "text.badge.xmark" : "text.badge.checkmark"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
    }

    @ViewBuilder
    private var sessionStatus: some View {
        switch sessionStateForSong {
        case .preparing:
            KaraokeStatusPill(title: "正在准备", systemImage: "ellipsis.circle", tint: .secondary)
        case .recording:
            KaraokeStatusPill(title: "跟唱中", systemImage: "record.circle.fill", tint: .red)
        case .paused:
            KaraokeStatusPill(title: "已暂停", systemImage: "pause.circle.fill", tint: .orange)
        case .finalizing:
            KaraokeStatusPill(title: "正在保存", systemImage: "externaldrive.fill.badge.checkmark", tint: .secondary)
        case .failed:
            KaraokeStatusPill(title: "跟唱失败", systemImage: "exclamationmark.triangle.fill", tint: .orange)
        default:
            KaraokeStatusPill(title: "可以开始跟唱", systemImage: "checkmark.circle", tint: .secondary)
        }
    }

    private var lyricsStage: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)

            Text(previousLyric)
                .font(.title3)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .frame(minHeight: 48)
                .accessibilityLabel("上一句歌词")

            Text(currentLyric)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: 760, minHeight: 82)
                .accessibilityLabel("当前歌词")
                .accessibilityValue(currentLyric)

            Text(nextLyric)
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(minHeight: 48)
                .accessibilityLabel("下一句歌词")

            if isActiveSession {
                WaveformView(samples: appModel.capture.liveWaveformSamples, activeColor: .red)
                    .frame(maxWidth: 560, maxHeight: 58)
                    .accessibilityHidden(true)
            } else {
                Label(
                    "播放的是歌曲原文件；开始跟唱后，麦克风人声会单独保存到录音资料库。",
                    systemImage: "headphones"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer(minLength: 12)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var transport: some View {
        VStack(spacing: 14) {
            Slider(
                value: Binding(
                    get: { playbackTime },
                    set: { seek(to: $0) }
                ),
                in: 0...max(song.duration, 0.01)
            )
            .disabled(isActiveSession)
            .accessibilityLabel("歌曲进度")
            .accessibilityValue("\(playbackTime.beatboxTimestamp)，共 \(song.duration.beatboxTimestamp)")

            HStack {
                Text(playbackTime.beatboxTimestamp)
                Spacer()
                Text(song.duration.beatboxTimestamp)
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                if isActiveSession {
                    Button { appModel.toggleKaraokePause() } label: {
                        Label(
                            isPausedSession ? "继续" : "暂停",
                            systemImage: isPausedSession ? "play.fill" : "pause.fill"
                        )
                        .frame(minWidth: 76)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isPreparingOrFinalizing)

                    Button { Task { _ = await appModel.stopKaraokeSession() } } label: {
                        Label("停止并保存", systemImage: "stop.fill")
                            .frame(minWidth: 112)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.red)
                    .disabled(!appModel.capture.state.canStop)
                } else {
                    Button { appModel.karaokePlayback.skip(by: -10) } label: {
                        Label("后退 10 秒", systemImage: "gobackward.10")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(!isCurrentPlayback)

                    Button { appModel.toggleKaraokePlayback(for: song) } label: {
                        Label(
                            isPlaying ? "暂停试听" : "试听",
                            systemImage: isPlaying ? "pause.fill" : "play.fill"
                        )
                        .frame(minWidth: 64)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(
                        appModel.capture.state.isCapturing
                            || appModel.isVocalReductionProcessing(for: song)
                    )

                    Button { appModel.karaokePlayback.skip(by: 10) } label: {
                        Label("前进 10 秒", systemImage: "goforward.10")
                            .labelStyle(.iconOnly)
                    }
                    .disabled(!isCurrentPlayback)

                    Divider()
                        .frame(height: 26)

                    Button {
                        Task { await appModel.startKaraokeSession(for: song) }
                    } label: {
                        Label("录制我的演唱", systemImage: "record.circle.fill")
                            .frame(minWidth: 134)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.red)
                    .disabled(!appModel.canStartKaraokeSession)
                    .help(karaokeStartHelp)
                    .accessibilityHint("播放歌曲，同时把麦克风人声单独保存到资料库")
                }

                Toggle(isOn: Binding(
                    get: { appModel.isVocalReductionEnabled(for: song) },
                    set: { enabled in
                        Task { await appModel.setVocalReductionEnabled(enabled, for: song) }
                    }
                )) {
                    Label("消除原唱", systemImage: "person.crop.circle.badge.minus")
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                .disabled(isActiveSession || appModel.isVocalReductionProcessing(for: song))
                .help("实验性立体声中置人声抵消；单声道或偏离中央的主唱可能无法消除")

                if appModel.isVocalReductionProcessing(for: song) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在生成人声消除版本")
                }

                Spacer(minLength: 16)
                Image(systemName: "speaker.fill")
                    .foregroundStyle(.secondary)
                Slider(value: Binding(
                    get: { Double(appModel.karaokePlayback.volume) },
                    set: { appModel.karaokePlayback.volume = Float($0) }
                ), in: 0...1)
                .frame(width: 130)
                .accessibilityLabel("歌曲音量")
            }

            if isActiveSession {
                Label(
                    isPausedSession
                        ? "已录内容安全保留；继续后从当前位置恢复。"
                        : "麦克风人声正在持续保存到本机。建议使用耳机避免回授。",
                    systemImage: isPausedSession
                        ? "pause.circle"
                        : "externaldrive.fill.badge.checkmark"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else if appModel.isVocalReductionEnabled(for: song) {
                Label(
                    "实验性中置人声抵消已启用；会同时削弱位于中央的贝斯、鼓和其他乐器。",
                    systemImage: "waveform.badge.minus"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else if appModel.selectedSource.kind != .microphone {
                Label(
                    "KTV 需要麦克风。请先在工具栏选择一个麦克风音源。",
                    systemImage: "mic.badge.xmark"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else {
                Label(
                    "建议佩戴耳机，避免扬声器声音再次进入麦克风。",
                    systemImage: "headphones"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(.bar)
    }

    private var sessionStateForSong: KaraokeSessionState {
        guard appModel.karaokeSessionState.songID == song.id else { return .idle }
        return appModel.karaokeSessionState
    }

    private var isActiveSession: Bool { sessionStateForSong.isActive }

    private var isPausedSession: Bool {
        if case .paused = sessionStateForSong { return true }
        return false
    }

    private var isPreparingOrFinalizing: Bool {
        switch sessionStateForSong {
        case .preparing, .finalizing: true
        default: false
        }
    }

    private var isCurrentPlayback: Bool {
        appModel.karaokePlayback.state.songID == song.id
    }

    private var isPlaying: Bool {
        if case .playing(song.id) = appModel.karaokePlayback.state { return true }
        return false
    }

    private var playbackTime: TimeInterval {
        isCurrentPlayback ? appModel.karaokePlayback.currentTime : 0
    }

    private var activeCueIndex: Int? {
        song.lyricCues.lastIndex { $0.time <= playbackTime }
    }

    private var currentLyric: String {
        guard !song.lyricCues.isEmpty else { return "这首歌曲没有歌词" }
        guard let activeCueIndex else {
            let countdown = max(0, Int((song.lyricCues.first?.time ?? 0) - playbackTime))
            return countdown > 0 ? "前奏 · 歌词将在 \(countdown) 秒后开始" : "前奏"
        }
        let text = song.lyricCues[activeCueIndex].text
        return text.isEmpty ? "间奏" : text
    }

    private var previousLyric: String {
        adjacentLyric(from: activeCueIndex, direction: -1)
    }

    private var nextLyric: String {
        adjacentLyric(from: activeCueIndex, direction: 1)
    }

    private func adjacentLyric(from index: Int?, direction: Int) -> String {
        guard !song.lyricCues.isEmpty else { return "" }
        var candidate = (index ?? -1) + direction
        while song.lyricCues.indices.contains(candidate) {
            let text = song.lyricCues[candidate].text
            if !text.isEmpty { return text }
            candidate += direction
        }
        return ""
    }

    private func seek(to time: TimeInterval) {
        if !isCurrentPlayback {
            appModel.karaokePlayback.play(id: song.id, url: appModel.karaokeAudioURL(for: song))
            appModel.karaokePlayback.pause()
        }
        appModel.karaokePlayback.seek(to: time)
    }

    private var karaokeStartHelp: String {
        if appModel.selectedSource.kind != .microphone {
            return "请先在工具栏选择麦克风音源"
        }
        if appModel.capture.state.isCapturing { return "请先停止当前录音" }
        return "使用 \(appModel.selectedSource.name) 跟唱并录制人声"
    }
}

private struct KaraokeStatusPill: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(tint.opacity(0.1), in: Capsule())
    }
}

struct EmptyKaraokeDetailView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        ContentUnavailableView {
            Label("选择或导入一首歌曲", systemImage: "music.mic")
        } description: {
            Text("NCM 会在本机转换为 MP3 或 FLAC；同名 LRC 会自动匹配。")
        } actions: {
            Button("导入歌曲…") { appModel.chooseAndImportKaraokeSong() }
                .buttonStyle(.borderedProminent)
                .disabled(appModel.karaokeImportState.isWorking)
        }
    }
}
