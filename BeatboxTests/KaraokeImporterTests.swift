import AVFAudio
import AudioToolbox
import Foundation
import Testing
@testable import Beatbox

@Suite("KTV 歌曲导入")
@MainActor
struct KaraokeImporterTests {
    @Test("导入标准音频和已授权歌词")
    func importsStandardAudioAndLyrics() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "BeatboxLyricsImportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sourceDirectoryURL = rootURL.appending(path: "source", directoryHint: .isDirectory)
        let storage = StoragePaths(rootURL: rootURL.appending(path: "library", directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: sourceDirectoryURL, withIntermediateDirectories: true)
        try storage.prepare()
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let sourceURL = sourceDirectoryURL.appending(path: "歌手 - 歌曲.wav")
        let lyricsURL = sourceDirectoryURL.appending(path: "歌手 - 歌曲.lrc")
        try makeTone(at: sourceURL)
        try "[00:00.00]第一句\n[00:00.05]第二句".write(
            to: lyricsURL,
            atomically: true,
            encoding: .utf8
        )

        let result = try await KaraokeImporter().importSong(
            sourceURL: sourceURL,
            lyricsURL: lyricsURL,
            storage: storage
        )

        #expect(result.lyricCues.map(\.text) == ["第一句", "第二句"])
        let lyricsFileName = try #require(result.lyricsFileName)
        #expect(FileManager.default.fileExists(
            atPath: storage.karaokeURL(for: lyricsFileName).path
        ))
    }

    @Test(.enabled(
        if: ProcessInfo.processInfo.environment["BEATBOX_NCM_FIXTURE"] != nil,
        "需要通过 BEATBOX_NCM_FIXTURE 提供合法的 NCM 文件"
    ))
    func importsConfiguredNCMFixture() async throws {
        let sourcePath = try #require(
            ProcessInfo.processInfo.environment["BEATBOX_NCM_FIXTURE"]
        )

        let sourceURL = URL(fileURLWithPath: sourcePath)
        let lyricCandidate = sourceURL.deletingPathExtension().appendingPathExtension("lrc")
        let lyricURL = FileManager.default.fileExists(atPath: lyricCandidate.path)
            ? lyricCandidate
            : nil
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "BeatboxKaraokeImporterTests-(UUID().uuidString)", directoryHint: .isDirectory)
        let storage = StoragePaths(rootURL: rootURL)
        try storage.prepare()

        let result = try await KaraokeImporter().importSong(
            sourceURL: sourceURL,
            lyricsURL: lyricURL,
            storage: storage
        )

        #expect(!result.artist.isEmpty)
        #expect(!result.title.isEmpty)
        #expect(result.duration > 1)
        #expect(result.sourceFormat == "NCM → MP3" || result.sourceFormat == "NCM → FLAC")
        #expect(FileManager.default.fileExists(
            atPath: storage.karaokeURL(for: result.audioFileName).path
        ))
    }

    @Test("内置解码器拒绝损坏的 NCM")
    func rejectsInvalidNCMContainer() throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appending(path: "BeatboxInvalidNCMTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sourceURL = rootURL.appending(path: "invalid.ncm")
        let outputURL = rootURL.appending(path: "output", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        try Data("not an ncm file".utf8).write(to: sourceURL)

        #expect(throws: NativeNCMDecoder.DecodeError.self) {
            try NativeNCMDecoder().decode(sourceURL: sourceURL, outputDirectory: outputURL)
        }
    }

    private func makeTone(at url: URL) throws {
        let sampleRate = 48_000.0
        let frameCount: AVAudioFrameCount = 4_800
        let format = try #require(AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ))
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
}
