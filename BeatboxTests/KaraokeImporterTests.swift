import Foundation
import Testing
@testable import Beatbox

@Suite("KTV 歌曲导入")
@MainActor
struct KaraokeImporterTests {
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
}
