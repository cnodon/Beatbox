import Foundation
import Testing
@testable import Beatbox

@Suite("录屏导出")
struct VideoExporterTests {
    @Test
    func exportCopiesMovieWithoutChangingSource() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "BeatboxVideoExporterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sourceURL = directory.appending(path: "source.mov")
        let destinationURL = directory.appending(path: "copy.mov")
        let payload = Data("Beatbox MOV fixture".utf8)
        try payload.write(to: sourceURL)

        let exportedURL = try await VideoExporter().export(
            sourceURL: sourceURL,
            destinationURL: destinationURL
        )

        #expect(exportedURL == destinationURL)
        #expect(try Data(contentsOf: sourceURL) == payload)
        #expect(try Data(contentsOf: destinationURL) == payload)
    }

    @Test
    func exportRejectsOverwritingLibrarySource() async {
        let sourceURL = FileManager.default.temporaryDirectory
            .appending(path: "BeatboxVideoSource-\(UUID().uuidString).mov")
        do {
            try Data([0x01]).write(to: sourceURL)
            defer { try? FileManager.default.removeItem(at: sourceURL) }
            _ = try await VideoExporter().export(
                sourceURL: sourceURL,
                destinationURL: sourceURL
            )
            Issue.record("预期拒绝覆盖资料库原文件")
        } catch VideoExportError.sourceAndDestinationMatch {
            // Expected.
        } catch {
            Issue.record("收到意外错误：\(error)")
        }
    }
}
