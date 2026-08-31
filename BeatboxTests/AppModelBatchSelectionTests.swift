import Foundation
import SwiftData
import Testing
@testable import Beatbox

@Suite("录音批量选择与删除", .serialized)
@MainActor
struct AppModelBatchSelectionTests {
    @Test("全选后可批量移到最近删除并一次撤销")
    func batchMoveAndUndo() throws {
        let fixture = try makeFixture(recordingCount: 3)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        fixture.appModel.selectAllVisibleRecordings()
        #expect(fixture.appModel.selectedVisibleRecordings.count == 3)

        fixture.appModel.moveToRecentlyDeleted(fixture.appModel.selectedVisibleRecordings)
        #expect(fixture.appModel.visibleRecordings.isEmpty)
        #expect(fixture.appModel.lastDeletedRecordingIDs.count == 3)

        fixture.appModel.undoLastDeletion()
        #expect(fixture.appModel.visibleRecordings.count == 3)
        #expect(fixture.appModel.selectedVisibleRecordings.count == 3)
        #expect(fixture.appModel.lastDeletedRecordingIDs.isEmpty)
    }

    @Test("批量永久删除同时移除数据库记录和文件")
    func batchPermanentDelete() throws {
        let fixture = try makeFixture(recordingCount: 2, deleted: true, createFiles: true)
        defer { try? FileManager.default.removeItem(at: fixture.rootURL) }

        fixture.appModel.selectedLibrary = .recentlyDeleted
        fixture.appModel.selectAllVisibleRecordings()
        let fileURLs = fixture.appModel.selectedVisibleRecordings.map(fixture.appModel.fileURL)

        fixture.appModel.deletePermanently(fixture.appModel.selectedVisibleRecordings)

        #expect(fixture.appModel.recordings.isEmpty)
        #expect(fileURLs.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    private func makeFixture(
        recordingCount: Int,
        deleted: Bool = false,
        createFiles: Bool = false
    ) throws -> (appModel: AppModel, rootURL: URL, container: ModelContainer) {
        let rootURL = FileManager.default.temporaryDirectory.appending(
            path: "Beatbox-BatchSelectionTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        let storage = StoragePaths(rootURL: rootURL)
        try storage.prepare()

        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Recording.self,
            KaraokeSong.self,
            configurations: configuration
        )
        for index in 0 ..< recordingCount {
            let id = UUID()
            let fileName = "\(id.uuidString).m4a"
            let recording = Recording(
                id: id,
                title: "测试录音 \(index + 1)",
                duration: 1,
                sourceKind: .microphone,
                sourceName: "测试麦克风",
                fileName: fileName,
                fileSize: 1,
                deletedAt: deleted ? .now : nil
            )
            container.mainContext.insert(recording)
            if createFiles {
                try Data([0]).write(to: storage.url(for: fileName))
            }
        }
        try container.mainContext.save()

        return (
            try AppModel(
                modelContext: container.mainContext,
                storage: storage,
                performsStartupRecovery: false
            ),
            rootURL,
            container
        )
    }
}
