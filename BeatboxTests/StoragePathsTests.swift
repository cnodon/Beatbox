import Foundation
import Testing
@testable import Beatbox

@Suite("存储与录音元数据")
@MainActor
struct StoragePathsTests {
    @Test
    func testRecordingURLsUseRecoverableNames() {
        let root = URL(fileURLWithPath: "/tmp/BeatboxTests", isDirectory: true)
        let paths = StoragePaths(rootURL: root)
        let id = UUID(uuidString: "36EB18BE-8093-4B2E-AE8B-BE5912EA6ED6")!

        #expect(
            paths.inProgressURL(for: id).lastPathComponent
                == "36EB18BE-8093-4B2E-AE8B-BE5912EA6ED6.inprogress.m4a"
        )
        #expect(
            paths.finalURL(for: id).lastPathComponent
                == "36EB18BE-8093-4B2E-AE8B-BE5912EA6ED6.m4a"
        )
        #expect(
            paths.inProgressURL(for: id, mode: .screenAndAudio).lastPathComponent
                == "36EB18BE-8093-4B2E-AE8B-BE5912EA6ED6.inprogress.mov"
        )
        #expect(
            paths.finalURL(for: id, mode: .screenAndAudio).lastPathComponent
                == "36EB18BE-8093-4B2E-AE8B-BE5912EA6ED6.mov"
        )
    }

    @Test
    func testKaraokeURLsStayInsideDedicatedLibrary() {
        let root = URL(fileURLWithPath: "/tmp/BeatboxTests", isDirectory: true)
        let paths = StoragePaths(rootURL: root)
        let id = UUID(uuidString: "36EB18BE-8093-4B2E-AE8B-BE5912EA6ED6")!

        #expect(paths.karaokeAudioURL(for: id, fileExtension: "mp3").lastPathComponent
            == "36EB18BE-8093-4B2E-AE8B-BE5912EA6ED6.mp3")
        #expect(paths.karaokeLyricsURL(for: id).lastPathComponent
            == "36EB18BE-8093-4B2E-AE8B-BE5912EA6ED6.lrc")
        #expect(paths.karaokeStagingURL(for: id).deletingLastPathComponent()
            == paths.karaokeStagingURL)
        #expect(paths.karaokeVocalReductionURL(for: id).deletingLastPathComponent()
            == paths.karaokeDerivedURL)
    }

    @Test
    func testRecordingRoundTripsWaveformAndMetadata() {
        let id = UUID()
        let recording = Recording(
            id: id,
            title: "测试录音",
            duration: 12.5,
            sourceKind: .microphone,
            sourceName: "MacBook 麦克风",
            fileName: "sample.m4a",
            fileSize: 1024,
            waveformSamples: [0.1, 0.5, 1.0]
        )

        #expect(recording.id == id)
        #expect(recording.sourceKind == .microphone)
        #expect(recording.integrity == .complete)
        #expect(recording.waveformSamples == [0.1, 0.5, 1.0])
        #expect(!recording.isDeleted)
    }

    @Test
    func testScreenRecordingRoundTripsModeAndFormat() {
        let recording = Recording(
            id: UUID(),
            title: "测试录屏",
            duration: 8,
            sourceKind: .system,
            sourceName: "主显示器与系统音频",
            recordingMode: .screenAndAudio,
            fileName: "screen.mov",
            fileSize: 4096
        )

        #expect(recording.recordingMode == .screenAndAudio)
        #expect(recording.recordingMode.fileExtension == "mov")
        #expect(recording.recordingMode.fileFormatTitle == "MOV（H.264 + AAC）")
    }
}
