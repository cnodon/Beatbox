import AVFAudio
import AudioToolbox
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Beatbox

@Suite("音频格式导出")
struct AudioExporterTests {
    @Test(arguments: AudioExportFormat.allCases)
    func eachFormatProducesPlayableAudio(format: AudioExportFormat) async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "Beatbox-ExporterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let sourceURL = directoryURL.appending(path: "source.wav")
        try makeTone(at: sourceURL)
        let destinationURL = directoryURL
            .appending(path: "export")
            .appendingPathExtension(format.fileExtension)

        let exportedURL = try await AudioExporter().export(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            format: format
        )

        #expect(exportedURL == destinationURL)
        #expect(FileManager.default.fileExists(atPath: destinationURL.path))
        let outputFile = try AVAudioFile(forReading: destinationURL)
        #expect(outputFile.length > 0)
        #expect(outputFile.fileFormat.sampleRate == 48_000)
        #expect(outputFile.fileFormat.streamDescription.pointee.mFormatID == expectedFormatID(for: format))
    }

    @Test(arguments: AudioExportFormat.allCases)
    func eachFormatHasAnAudioContentType(format: AudioExportFormat) {
        #expect(!format.title.isEmpty)
        #expect(!format.detail.isEmpty)
        #expect(!format.fileExtension.isEmpty)
        #expect(format.contentType.conforms(to: .audio))
    }

    @Test
    func refusesToOverwriteLibrarySourceInPlace() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "Beatbox-SameFile-\(UUID().uuidString).wav")
        try makeTone(at: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        await #expect(throws: AudioExportError.self) {
            try await AudioExporter().export(
                sourceURL: sourceURL,
                destinationURL: sourceURL,
                format: .wavPCM
            )
        }
        #expect(FileManager.default.fileExists(atPath: sourceURL.path))
    }

    @Test
    func replacesAnExistingDestinationWithPlayableOutput() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "Beatbox-ReplacementTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let sourceURL = directoryURL.appending(path: "source.wav")
        let destinationURL = directoryURL.appending(path: "existing.wav")
        try makeTone(at: sourceURL)
        try Data("existing file".utf8).write(to: destinationURL)

        _ = try await AudioExporter().export(
            sourceURL: sourceURL,
            destinationURL: destinationURL,
            format: .wavPCM
        )

        let outputFile = try AVAudioFile(forReading: destinationURL)
        #expect(outputFile.length > 0)
    }

    @Test
    func existingAACM4AIsCopiedWithoutReencoding() async throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appending(path: "Beatbox-AACCopyTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let waveURL = directoryURL.appending(path: "source.wav")
        let sourceM4AURL = directoryURL.appending(path: "source.m4a")
        let exportedM4AURL = directoryURL.appending(path: "copy.m4a")
        try makeTone(at: waveURL)
        _ = try await AudioExporter().export(
            sourceURL: waveURL,
            destinationURL: sourceM4AURL,
            format: .m4aAAC
        )

        _ = try await AudioExporter().export(
            sourceURL: sourceM4AURL,
            destinationURL: exportedM4AURL,
            format: .m4aAAC
        )

        #expect(try Data(contentsOf: sourceM4AURL) == Data(contentsOf: exportedM4AURL))
    }

    private func makeTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount: AVAudioFrameCount = 4_800
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sampleRate,
                channels: 1,
                interleaved: false
            )
        )
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount))
        let channel = try #require(buffer.floatChannelData?[0])
        buffer.frameLength = frameCount

        for frame in 0 ..< Int(frameCount) {
            channel[frame] = sin(Float(frame) * 2 * .pi * 440 / Float(sampleRate)) * 0.25
        }

        let output = try AVAudioFile(
            forWriting: url,
            settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 1,
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

    private func expectedFormatID(for format: AudioExportFormat) -> AudioFormatID {
        switch format {
        case .m4aAAC: kAudioFormatMPEG4AAC
        case .m4aALAC: kAudioFormatAppleLossless
        case .wavPCM, .aiffPCM, .cafPCM: kAudioFormatLinearPCM
        case .flac: kAudioFormatFLAC
        }
    }
}
