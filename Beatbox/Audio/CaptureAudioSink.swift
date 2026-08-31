@preconcurrency import AVFAudio
import Foundation
import os

nonisolated struct CaptureAudioSnapshot: Sendable {
    let averagePower: Float
    let peakPower: Float
    let processedFrames: AVAudioFramePosition
    let sampleRate: Double
    let errorDescription: String?
}

// AVAudioEngine invokes its tap on a framework-managed thread. Every mutable
// field is protected by OSAllocatedUnfairLock, so the sink can safely cross
// that callback boundary despite AVFAudio lacking complete Sendable annotations.
nonisolated final class CaptureAudioSink: @unchecked Sendable {
    private struct State {
        var audioFile: AVAudioFile?
        var averagePower: Float = -160
        var peakPower: Float = -160
        var processedFrames: AVAudioFramePosition = 0
        var errorDescription: String?
    }

    private let sampleRate: Double
    private let state: OSAllocatedUnfairLock<State>

    init(audioFile: AVAudioFile? = nil, sampleRate: Double) {
        self.sampleRate = sampleRate
        state = OSAllocatedUnfairLock(initialState: State(audioFile: audioFile))
    }

    func consume(_ buffer: AVAudioPCMBuffer) {
        let meters = Self.meters(in: buffer)
        state.withLock { state in
            guard state.errorDescription == nil else { return }
            do {
                try state.audioFile?.write(from: buffer)
                state.processedFrames += AVAudioFramePosition(buffer.frameLength)
                state.averagePower = meters.average
                state.peakPower = meters.peak
            } catch {
                state.errorDescription = error.localizedDescription
            }
        }
    }

    func snapshot() -> CaptureAudioSnapshot {
        state.withLock { state in
            CaptureAudioSnapshot(
                averagePower: state.averagePower,
                peakPower: state.peakPower,
                processedFrames: state.processedFrames,
                sampleRate: sampleRate,
                errorDescription: state.errorDescription
            )
        }
    }

    func finish() -> CaptureAudioSnapshot {
        state.withLock { state in
            let snapshot = CaptureAudioSnapshot(
                averagePower: state.averagePower,
                peakPower: state.peakPower,
                processedFrames: state.processedFrames,
                sampleRate: sampleRate,
                errorDescription: state.errorDescription
            )
            state.audioFile = nil
            return snapshot
        }
    }

    static func tapHandler(for sink: CaptureAudioSink) -> AVAudioNodeTapBlock {
        { buffer, _ in
            sink.consume(buffer)
        }
    }

    private static func meters(
        in buffer: AVAudioPCMBuffer
    ) -> (average: Float, peak: Float) {
        guard buffer.format.commonFormat == .pcmFormatFloat32,
              let channels = buffer.floatChannelData,
              buffer.frameLength > 0
        else { return (-160, -160) }

        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        var sumOfSquares: Double = 0
        var peak: Float = 0

        for channelIndex in 0 ..< channelCount {
            let channel = channels[channelIndex]
            for frameIndex in 0 ..< frameCount {
                let sample = abs(channel[frameIndex])
                peak = max(peak, sample)
                sumOfSquares += Double(sample * sample)
            }
        }

        let sampleCount = max(1, frameCount * channelCount)
        let rootMeanSquare = sqrt(sumOfSquares / Double(sampleCount))
        let averageDecibels = Float(20 * log10(max(rootMeanSquare, 0.000_000_01)))
        let peakDecibels = 20 * log10(max(peak, 0.000_000_01))
        return (max(-160, averageDecibels), max(-160, peakDecibels))
    }
}
