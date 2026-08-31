@preconcurrency import AVFAudio
import Foundation
import Testing
@testable import Beatbox

@Suite("录音文件写入")
@MainActor
struct CaptureAudioSinkTests {
    @Test
    func sinkWritesFramesAndReportsSignalMeters() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appending(path: "Beatbox-CaptureAudioSink-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48_000,
            channels: 1,
            interleaved: false
        ))
        let audioFile = try AVAudioFile(forWriting: fileURL, settings: format.settings)
        let sink = CaptureAudioSink(audioFile: audioFile, sampleRate: format.sampleRate)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 480))
        buffer.frameLength = 480

        let samples = try #require(buffer.floatChannelData?[0])
        for index in 0 ..< Int(buffer.frameLength) {
            samples[index] = 0.5
        }

        sink.consume(buffer)
        let snapshot = sink.finish()

        #expect(snapshot.processedFrames == 480)
        #expect(snapshot.sampleRate == 48_000)
        #expect(snapshot.errorDescription == nil)
        #expect(snapshot.averagePower > -6.1 && snapshot.averagePower < -6.0)
        #expect(snapshot.peakPower > -6.1 && snapshot.peakPower < -6.0)

        let readableFile = try AVAudioFile(forReading: fileURL)
        #expect(readableFile.length == 480)
    }
}
