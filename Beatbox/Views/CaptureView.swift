import SwiftUI

struct CaptureView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label(captureSourceTitle, systemImage: captureSourceImage)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("当前来源：\(captureSourceTitle)")

                Spacer()

                Label(statusText, systemImage: statusImage)
                .font(.callout.weight(.semibold))
                .foregroundStyle(statusColor)
                .accessibilityAddTraits(.isHeader)
            }
            .padding(.horizontal, 2)

            Spacer(minLength: 24)

            Text(appModel.capture.elapsedTime.beatboxTimestamp)
                .font(.system(size: 62, weight: .medium, design: .rounded).monospacedDigit())
                .accessibilityLabel("录音时长")
                .accessibilityValue(appModel.capture.elapsedTime.beatboxTimestamp)

            Text(timerCaption)
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            LiveRecordingWaveform(
                samples: appModel.capture.liveWaveformSamples,
                tint: statusColor,
                isPaused: isPaused,
                isClipping: appModel.capture.hasDetectedClipping
            )
            .frame(height: 154)
            .padding(.top, 24)

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    SignalHealthLabel(health: appModel.capture.signalHealth)
                    Spacer()
                    Text("平均 \(decibelText(appModel.capture.averagePower))")
                    Text("峰值 \(decibelText(appModel.capture.peakPower))")
                }
                .font(.caption.monospacedDigit())

                InputLevelMeter(
                    averagePower: appModel.capture.averagePower,
                    peakPower: appModel.capture.peakPower,
                    isPaused: isPaused
                )
            }
            .padding(.top, 18)

            Group {
                if signalGuidanceText != nil {
                    signalGuidance
                } else {
                    Label(
                        appModel.selectedRecordingMode == .screenAndAudio
                            ? "画面与系统音频正在持续写入本机"
                            : "音频正在持续写入本机",
                        systemImage: "externaldrive.fill.badge.checkmark"
                    )
                    .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .frame(minHeight: 22)
            .padding(.top, 12)

            captureControls
            .padding(.top, 22)

            Text(controlHint)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, 12)

            Spacer(minLength: 24)
        }
        .padding(32)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var captureControls: some View {
        switch appModel.capture.state {
        case .requestingPermission, .preparing:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("正在建立安全的本地录制文件…")
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 40)
            .accessibilityElement(children: .combine)
        case .finalizing:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(appModel.selectedRecordingMode == .screenAndAudio
                     ? "正在封装视频与音频，请不要退出 Beatbox"
                     : "正在封装音频，请不要退出 Beatbox")
                    .foregroundStyle(.secondary)
            }
            .frame(minHeight: 40)
            .accessibilityElement(children: .combine)
        case .recording, .paused:
            HStack(spacing: 12) {
                if appModel.selectedRecordingMode == .audio {
                    Button {
                        appModel.toggleCapturePause()
                    } label: {
                        Label(pauseTitle, systemImage: pauseImage)
                            .frame(minWidth: 96)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help(pauseTitle)
                    .accessibilityHint("按空格键也可以\(pauseTitle)")
                }

                Button {
                    Task { _ = await appModel.stopRecording() }
                } label: {
                    Label("停止并保存", systemImage: "stop.fill")
                        .frame(minWidth: 120)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .keyboardShortcut(".", modifiers: [.command])
                .accessibilityHint("停止后会自动出现在录音资料库")
            }
        default:
            EmptyView()
        }
    }

    private var statusImage: String {
        switch appModel.capture.state {
        case .recording: "record.circle.fill"
        case .paused: "pause.circle.fill"
        case .finalizing: "externaldrive.fill.badge.checkmark"
        default: "ellipsis.circle"
        }
    }

    private var statusText: String {
        guard appModel.selectedRecordingMode == .screenAndAudio else {
            return appModel.capture.state.statusText
        }
        return switch appModel.capture.state {
        case .requestingPermission: "正在请求权限"
        case .preparing: "正在准备录屏"
        case .recording: "正在录屏"
        case .paused: "录屏已暂停"
        case .finalizing: "正在保存录屏"
        case .completed: "录屏已保存"
        case .failed: "录屏失败"
        case .idle: "就绪"
        }
    }

    private var isPaused: Bool {
        if case .paused = appModel.capture.state { return true }
        return false
    }

    private var timerCaption: String {
        switch appModel.capture.state {
        case .paused: "录音已暂停，文件仍安全保留"
        case .finalizing: appModel.selectedRecordingMode == .screenAndAudio
            ? "正在封装视频与音频并更新资料库"
            : "正在封装音频并更新资料库"
        case .preparing, .requestingPermission: appModel.selectedRecordingMode == .screenAndAudio
            ? "正在检查屏幕、系统音频和文件写入"
            : "正在检查麦克风和文件写入"
        default: appModel.selectedRecordingMode == .screenAndAudio ? "正在录屏" : "正在录音"
        }
    }

    private var statusColor: Color {
        switch appModel.capture.state {
        case .recording: .red
        case .paused: .orange
        case .failed: .red
        default: .accentColor
        }
    }

    private var captureSourceImage: String {
        appModel.selectedRecordingMode == .screenAndAudio
            ? appModel.selectedRecordingMode.systemImage
            : appModel.selectedSource.kind.systemImage
    }

    private var pauseTitle: String {
        if case .paused = appModel.capture.state { "继续" } else { "暂停" }
    }

    private var pauseImage: String {
        if case .paused = appModel.capture.state { "play.fill" } else { "pause.fill" }
    }

    private var captureSourceTitle: String {
        appModel.selectedRecordingMode == .screenAndAudio
            ? "主显示器与系统音频"
            : appModel.selectedSource.name
    }

    @ViewBuilder
    private var signalGuidance: some View {
        switch appModel.capture.signalHealth {
        case .clipping:
            Label(clippingGuidance, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .silent:
            Label(silenceGuidance, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .low:
            Label("输入声音偏小，可以靠近麦克风或提高输入音量。", systemImage: "speaker.wave.1.fill")
                .foregroundStyle(.secondary)
        case .paused:
            Label("继续后，波形和电平会从当前位置恢复。", systemImage: "pause.circle")
                .foregroundStyle(.secondary)
        case .preparing, .healthy:
            EmptyView()
        }
    }

    private var signalGuidanceText: String? {
        switch appModel.capture.signalHealth {
        case .clipping: clippingGuidance
        case .silent: silenceGuidance
        case .low: "输入声音偏小"
        case .paused: "录制已暂停"
        case .preparing, .healthy: nil
        }
    }

    private var controlHint: String {
        switch appModel.capture.state {
        case .recording where appModel.selectedRecordingMode == .screenAndAudio:
            "录屏暂不支持暂停 · ⌘. 停止并保存"
        case .recording, .paused:
            "空格键暂停或继续 · ⌘. 停止并保存"
        case .finalizing:
            "完成文件封装后即可开始下一次录制"
        default:
            "准备完成后计时和波形会自动开始"
        }
    }

    private func decibelText(_ value: Float) -> String {
        guard value > -100 else { return "— dB" }
        return "\(Int(value.rounded())) dB"
    }

    private var silenceGuidance: String {
        if appModel.selectedRecordingMode == .screenAndAudio {
            return "没有检测到系统音频，请确认有 App 正在播放声音。"
        }
        return appModel.selectedSource.kind == .application
            ? "没有检测到声音，请确认目标 App 正在播放。"
            : "没有检测到声音，请检查麦克风或输入音量。"
    }

    private var clippingGuidance: String {
        if appModel.selectedRecordingMode == .screenAndAudio {
            return "系统音频电平过高，录屏中的声音可能失真。"
        }
        return appModel.selectedSource.kind == .application
            ? "App 输出电平过高，录音可能失真。"
            : "输入电平过高，声音可能失真；请降低麦克风增益。"
    }
}

private struct SignalHealthLabel: View {
    let health: InputSignalHealth

    var body: some View {
        Label(title, systemImage: systemImage)
            .fontWeight(.medium)
            .foregroundStyle(color)
            .accessibilityLabel("输入状态：\(title)")
    }

    private var title: String {
        switch health {
        case .preparing: "正在检查输入"
        case .healthy: "输入正常"
        case .low: "音量偏低"
        case .silent: "未检测到声音"
        case .clipping: "电平过高"
        case .paused: "计量已暂停"
        }
    }

    private var systemImage: String {
        switch health {
        case .preparing: "ellipsis.circle"
        case .healthy: "checkmark.circle.fill"
        case .low: "speaker.wave.1.fill"
        case .silent: "speaker.slash.fill"
        case .clipping: "exclamationmark.triangle.fill"
        case .paused: "pause.circle.fill"
        }
    }

    private var color: Color {
        switch health {
        case .healthy: .green
        case .low, .silent, .paused: .orange
        case .clipping: .red
        case .preparing: .secondary
        }
    }
}

private struct InputLevelMeter: View {
    let averagePower: Float
    let peakPower: Float
    let isPaused: Bool

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { proxy in
                let averagePosition = CGFloat(AudioMeterScale.meterPosition(decibels: averagePower))
                let peakPosition = CGFloat(AudioMeterScale.meterPosition(decibels: peakPower))
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    LinearGradient(
                        colors: [.green, .green, .yellow, .orange, .red],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .mask(alignment: .leading) {
                        Capsule().frame(width: proxy.size.width * averagePosition)
                    }
                    if !isPaused, peakPower > AudioMeterScale.minimumDecibels {
                        Capsule()
                            .fill(peakPosition > 0.94 ? Color.red : Color.primary.opacity(0.72))
                            .frame(width: 2, height: 12)
                            .offset(x: max(0, min(proxy.size.width - 2, proxy.size.width * peakPosition)))
                    }
                }
            }
            .frame(height: 8)

            HStack {
                Text("−60")
                Spacer()
                Text("−24")
                Spacer()
                Text("−12")
                Spacer()
                Text("−6")
                Spacer()
                Text("0 dB")
            }
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.tertiary)
        }
        .opacity(isPaused ? 0.52 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("音频输入电平")
        .accessibilityValue(peakPower > -100 ? "峰值 \(Int(peakPower.rounded())) 分贝" : "暂无信号")
    }
}
