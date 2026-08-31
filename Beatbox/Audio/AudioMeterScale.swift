import Foundation

nonisolated enum AudioMeterScale {
    static let minimumDecibels: Float = -60

    static func waveformLevel(decibels: Float) -> Float {
        guard decibels.isFinite else { return 0.025 }
        let position = meterPosition(decibels: decibels)
        return max(0.025, pow(position, 0.72))
    }

    static func meterPosition(decibels: Float) -> Float {
        guard decibels.isFinite else { return 0 }
        let clamped = min(max(decibels, minimumDecibels), 0)
        return (clamped - minimumDecibels) / -minimumDecibels
    }
}

nonisolated struct WaveformAccumulator: Sendable {
    private(set) var samples: [Float] = []
    private(set) var bucketSize = 1

    private var pendingMaximum: Float = 0
    private var pendingCount = 0
    private let maximumSampleCount: Int

    init(maximumSampleCount: Int = 2_048) {
        self.maximumSampleCount = max(2, maximumSampleCount)
    }

    mutating func append(_ sample: Float) {
        pendingMaximum = max(pendingMaximum, min(max(sample, 0), 1))
        pendingCount += 1

        guard pendingCount >= bucketSize else { return }
        samples.append(pendingMaximum)
        pendingMaximum = 0
        pendingCount = 0

        if samples.count >= maximumSampleCount {
            compress()
        }
    }

    var snapshot: [Float] {
        guard pendingCount > 0 else { return samples }
        return samples + [pendingMaximum]
    }

    mutating func reset() {
        samples.removeAll(keepingCapacity: true)
        bucketSize = 1
        pendingMaximum = 0
        pendingCount = 0
    }

    private mutating func compress() {
        var compressed: [Float] = []
        compressed.reserveCapacity((samples.count + 1) / 2)

        var index = 0
        while index < samples.count {
            if index + 1 < samples.count {
                compressed.append(max(samples[index], samples[index + 1]))
            } else {
                compressed.append(samples[index])
            }
            index += 2
        }

        samples = compressed
        bucketSize *= 2
    }
}
