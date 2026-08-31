import Foundation
import Testing
@testable import Beatbox

@Suite("电平与波形摘要")
struct AudioMeterScaleTests {
    @Test
    func decibelScaleUsesTheFullVisibleRange() {
        #expect(AudioMeterScale.meterPosition(decibels: -60) == 0)
        #expect(AudioMeterScale.meterPosition(decibels: 0) == 1)
        #expect(AudioMeterScale.meterPosition(decibels: -30) == 0.5)
        #expect(AudioMeterScale.waveformLevel(decibels: -60) == 0.025)
        #expect(AudioMeterScale.waveformLevel(decibels: -12) > 0.8)
    }

    @Test
    func decibelScaleClampsInvalidAndOutOfRangeInput() {
        #expect(AudioMeterScale.meterPosition(decibels: -.infinity) == 0)
        #expect(AudioMeterScale.meterPosition(decibels: -120) == 0)
        #expect(AudioMeterScale.meterPosition(decibels: 12) == 1)
        #expect(AudioMeterScale.waveformLevel(decibels: .nan) == 0.025)
    }

    @Test
    func accumulatorStaysBoundedAcrossLongRecordings() {
        var accumulator = WaveformAccumulator(maximumSampleCount: 32)
        for index in 0 ..< 20_000 {
            accumulator.append(Float(index % 100) / 100)
        }

        #expect(accumulator.samples.count < 32)
        #expect(accumulator.snapshot.count <= 32)
        #expect(accumulator.bucketSize > 1)
    }

    @Test
    func accumulatorPreservesPeaksWhenCompressing() {
        var accumulator = WaveformAccumulator(maximumSampleCount: 8)
        for index in 0 ..< 200 {
            accumulator.append(index == 73 ? 1 : 0.1)
        }

        #expect(accumulator.snapshot.contains(1))
        #expect(accumulator.snapshot.allSatisfy { 0 ... 1 ~= $0 })
    }

    @Test
    func resetRestoresInitialResolution() {
        var accumulator = WaveformAccumulator(maximumSampleCount: 8)
        for _ in 0 ..< 100 {
            accumulator.append(0.5)
        }
        accumulator.reset()

        #expect(accumulator.samples.isEmpty)
        #expect(accumulator.snapshot.isEmpty)
        #expect(accumulator.bucketSize == 1)
    }
}
