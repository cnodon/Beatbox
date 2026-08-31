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

        #expect(result.artist == "庾澄庆")
        #expect(result.title == "让我一次爱个够")
        #expect(result.duration > 250)
        #expect(result.sourceFormat == "NCM → MP3")
        #expect(!result.lyricCues.isEmpty)
        #expect(FileManager.default.fileExists(
            atPath: storage.karaokeURL(for: result.audioFileName).path
        ))
    }
}
