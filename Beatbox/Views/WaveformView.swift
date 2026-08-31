import SwiftUI

struct LiveRecordingWaveform: View {
    let samples: [Float]
    let tint: Color
    let isPaused: Bool
    let isClipping: Bool

    var body: some View {
        Canvas { context, size in
            let horizontalInset: CGFloat = 12
            let trailingIndicatorSpace: CGFloat = 14
            let barWidth: CGFloat = 3
            let spacing: CGFloat = 3
            let drawableWidth = max(
                1,
                size.width - horizontalInset * 2 - trailingIndicatorSpace
            )
            let targetCount = max(1, Int(drawableWidth / (barWidth + spacing)))
            let visibleSamples = samples.suffix(targetCount)
            let emptySlotCount = targetCount - visibleSamples.count
            let centerY = size.height / 2
            let maximumHeight = max(6, size.height - 24)

            var slot = 0
            while slot < targetCount {
                let x = horizontalInset + CGFloat(slot) * (barWidth + spacing)
                let dataIndex = slot - emptySlotCount
                let hasSample = dataIndex >= 0
                let sample = hasSample ? visibleSamples[visibleSamples.index(visibleSamples.startIndex, offsetBy: dataIndex)] : 0.025
                let height = max(4, CGFloat(sample) * maximumHeight)
                let rect = CGRect(
                    x: x,
                    y: centerY - height / 2,
                    width: barWidth,
                    height: height
                )
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                let recency = hasSample
                    ? Double(dataIndex + 1) / Double(max(1, visibleSamples.count))
                    : 0
                let color = if isClipping, hasSample, recency > 0.88, sample > 0.9 {
                    Color.red
                } else {
                    tint
                }
                let opacity = hasSample ? 0.28 + recency * 0.72 : 0.1
                context.fill(path, with: .color(color.opacity(isPaused ? opacity * 0.62 : opacity)))
                slot += 1
            }

            let indicatorX = size.width - horizontalInset
            var indicator = Path()
            indicator.move(to: CGPoint(x: indicatorX, y: 13))
            indicator.addLine(to: CGPoint(x: indicatorX, y: size.height - 13))
            context.stroke(
                indicator,
                with: .color(tint.opacity(isPaused ? 0.42 : 0.9)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
        }
        .background(.quaternary.opacity(0.42), in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.separator.opacity(0.45))
        }
        .accessibilityHidden(true)
    }
}

struct WaveformView: View {
    let samples: [Float]
    var progress: Double = 1
    var activeColor: Color = .accentColor
    var inactiveColor: Color = .secondary.opacity(0.28)

    var body: some View {
        Canvas { context, size in
            let values = displaySamples(for: Int(max(1, size.width / 4)))
            guard !values.isEmpty else { return }

            let spacing: CGFloat = 2
            let width = max(1, (size.width - spacing * CGFloat(values.count - 1)) / CGFloat(values.count))
            let centerY = size.height / 2
            let progressX = size.width * min(max(progress, 0), 1)

            for (index, sample) in values.enumerated() {
                let height = max(3, CGFloat(sample) * size.height)
                let x = CGFloat(index) * (width + spacing)
                let rect = CGRect(x: x, y: centerY - height / 2, width: width, height: height)
                let path = Path(roundedRect: rect, cornerRadius: width / 2)
                context.fill(path, with: .color(x <= progressX ? activeColor : inactiveColor))
            }
        }
        .accessibilityHidden(true)
    }

    private func displaySamples(for targetCount: Int) -> [Float] {
        guard !samples.isEmpty else {
            return Array(repeating: 0.04, count: max(1, targetCount))
        }
        guard samples.count > targetCount else { return samples }

        let stride = Double(samples.count) / Double(targetCount)
        return (0..<targetCount).map { index in
            let start = Int(Double(index) * stride)
            let end = min(samples.count, Int(Double(index + 1) * stride))
            return samples[start..<max(start + 1, end)].max() ?? 0.02
        }
    }
}

struct WaveformScrubber: View {
    let samples: [Float]
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        GeometryReader { proxy in
            WaveformView(
                samples: samples,
                progress: duration > 0 ? currentTime / duration : 0
            )
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard proxy.size.width > 0 else { return }
                        let fraction = min(max(value.location.x / proxy.size.width, 0), 1)
                        onSeek(duration * fraction)
                    }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("播放位置")
        .accessibilityValue("\(currentTime.beatboxTimestamp)，共 \(duration.beatboxTimestamp)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeek(min(duration, currentTime + 15))
            case .decrement: onSeek(max(0, currentTime - 15))
            @unknown default: break
            }
        }
    }
}
