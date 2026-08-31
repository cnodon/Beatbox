import AVFAudio
import AudioToolbox
import Foundation
import Testing
@testable import Beatbox

@Suite("KTV 人声消除")
struct VocalReductionProcessorTests {
    @Test("抵消左右声道中相同的中置人声")
    func removesCenterSignal() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "Beatbox-VocalReduction-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let sourceURL = directoryURL.appending(path: "center.caf")
        let destinationURL = directoryURL.appending(path: "accompaniment.caf")
        try makeStereoCenterTone(at: sourceURL)

        _ = try await VocalReductionProcessor().createAccompaniment(
            sourceURL: sourceURL,
            destinationURL: destinationURL
        )

        let output = try AVAudioFile(
            forReading: destinationURL,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let buffer = try #require(AVAudioPCMBuffer(
            pcmFormat: output.processingFormat,
            frameCapacity: AVAudioFrameCount(output.length)
        ))
        try output.read(into: buffer)
        let channels = try #require(buffer.floatChannelData)
        let peak = (0 ..< Int(buffer.frameLength)).reduce(Float.zero) { current, frame in
            max(current, max(abs(channels[0][frame]), abs(channels[1][frame])))
        }
        #expect(peak < 0.000_01)
    }

    private func makeStereoCenterTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount: AVAudioFrameCount = 4_800
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ))
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        let channels = try #require(buffer.floatChannelData)
        buffer.frameLength = frameCount
        for frame in 0 ..< Int(frameCount) {
            let sample = sin(Float(frame) * 2 * .pi * 440 / Float(sampleRate)) * 0.5
            channels[0][frame] = sample
            channels[1][frame] = sample
        }
        let output = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try output.write(from: buffer)
    }
}
