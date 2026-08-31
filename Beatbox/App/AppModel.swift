import AppKit
import AVFAudio
import AVFoundation
import Foundation
import Observation
import os
import SwiftData
import UniformTypeIdentifiers

enum LibrarySection: String, CaseIterable, Identifiable {
    case all
    case recentlyDeleted
    case karaoke

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "所有录音"
        case .recentlyDeleted: "最近删除"
        case .karaoke: "歌曲"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "waveform"
        case .recentlyDeleted: "trash"
        case .karaoke: "music.mic"
        }
    }
}

enum UserMessageAction {
    case microphoneSettings
    case systemAudioSettings
    case recordingsFolder

    var title: String {
        switch self {
        case .microphoneSettings, .systemAudioSettings: "打开系统设置"
        case .recordingsFolder: "显示未完成文件"
        }
    }
}

@Observable
final class AppModel {
    let capture = CaptureController()
    let playback = PlaybackController()
    let karaokePlayback = KaraokePlaybackController()

    var selectedLibrary: LibrarySection = .all {
        didSet {
            if selectedLibrary == .karaoke {
                playback.stop()
                if !capture.state.isCapturing {
                    selectedRecordingMode = .audio
                }
                selectFirstVisibleKaraokeSongIfNeeded()
            } else {
                if !karaokeSessionState.isActive {
                    karaokePlayback.stop()
                }
                selectFirstVisibleRecordingIfNeeded()
            }
        }
    }
    var selectedRecordingID: UUID?
    var selectedKaraokeSongID: UUID?
    var searchText = ""
    var karaokeSearchText = ""
    private(set) var recordings: [Recording] = []
    private(set) var karaokeSongs: [KaraokeSong] = []
    private(set) var lastDeletedRecordingID: UUID?
    var userMessage: String?
    private(set) var userMessageAction: UserMessageAction?
    var recoveryIssueCount = 0
    private(set) var karaokeImportState: KaraokeImportState = .idle
    private(set) var karaokeSessionState: KaraokeSessionState = .idle
    private(set) var selectedSource: AudioSource = .defaultMicrophone
    var selectedRecordingMode: RecordingMode = .audio
    private(set) var microphoneSources: [AudioSource] = [.defaultMicrophone]
    private(set) var applicationSources: [AudioSource] = []
    private(set) var exportingRecordingID: UUID?

    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let storage: StoragePaths
    @ObservationIgnored private let audioExporter = AudioExporter()
    @ObservationIgnored private let videoExporter = VideoExporter()
    @ObservationIgnored private let karaokeImporter = KaraokeImporter()
    @ObservationIgnored private var stopTask: Task<Bool, Never>?
    @ObservationIgnored private let logger = Logger(
        subsystem: "com.tokenplay.beatbox",
        category: "app-model"
    )

    init(modelContext: ModelContext, storage: StoragePaths) throws {
        self.modelContext = modelContext
        self.storage = storage
        try storage.prepare()

        capture.onStateChange = { [weak self] state in
            self?.updateDockStatus(for: state)
            self?.synchronizeKaraokeSession(with: state)
            if case let .failed(failure) = state {
                let hasArtifact = self?.capture.hasRecoverableArtifact == true
                self?.userMessage = "\(failure.title)：\(failure.recoverySuggestion)"
                    + (hasArtifact ? " 已录内容仍保留在本机。" : "")
                self?.userMessageAction = switch failure {
                case .permissionDenied: .microphoneSettings
                case .systemAudioPermissionDenied: .systemAudioSettings
                default: hasArtifact ? .recordingsFolder : nil
                }
            }
        }
        karaokePlayback.onCompletion = { [weak self] songID in
            guard self?.karaokeSessionState.songID == songID else { return }
            Task { _ = await self?.stopKaraokeSession() }
        }

        recoverIncompleteRecordings()
        refreshRecordings()
        Task { await recoverIncompleteScreenRecordings() }
        refreshKaraokeSongs()
        refreshMicrophones()
        refreshApplications()
    }

    var visibleRecordings: [Recording] {
        let filteredByLibrary = recordings.filter { recording in
            switch selectedLibrary {
            case .all: !recording.isDeleted
            case .recentlyDeleted: recording.isDeleted
            case .karaoke: false
            }
        }

        guard !searchText.isEmpty else { return filteredByLibrary }
        return filteredByLibrary.filter {
            $0.title.localizedStandardContains(searchText)
                || $0.sourceName.localizedStandardContains(searchText)
        }
    }

    var selectedRecording: Recording? {
        guard let selectedRecordingID else { return nil }
        return recordings.first { $0.id == selectedRecordingID }
    }

    var visibleKaraokeSongs: [KaraokeSong] {
        guard !karaokeSearchText.isEmpty else { return karaokeSongs }
        return karaokeSongs.filter {
            $0.title.localizedStandardContains(karaokeSearchText)
                || $0.artist.localizedStandardContains(karaokeSearchText)
        }
    }

    var selectedKaraokeSong: KaraokeSong? {
        guard let selectedKaraokeSongID else { return nil }
        return karaokeSongs.first { $0.id == selectedKaraokeSongID }
    }

    var activeKaraokeSong: KaraokeSong? {
        guard let songID = karaokeSessionState.songID else { return nil }
        return karaokeSongs.first { $0.id == songID }
    }

    var activeRecordingURL: URL? {
        guard let selectedRecording else { return nil }
        return fileURL(for: selectedRecording)
    }

    var canStartRecording: Bool {
        let modeAvailable = selectedRecordingMode == .audio || ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 15, minorVersion: 0, patchVersion: 0)
        )
        return modeAvailable && selectedSource.isAvailable && capture.state.canStart
    }

    var isExporting: Bool {
        exportingRecordingID != nil
    }

    var canStartKaraokeSession: Bool {
        selectedSource.kind == .microphone
            && selectedSource.isAvailable
            && capture.state.canStart
            && !karaokeImportState.isWorking
    }

    func recordingCount(in section: LibrarySection) -> Int {
        switch section {
        case .all:
            recordings.lazy.filter { !$0.isDeleted }.count
        case .recentlyDeleted:
            recordings.lazy.filter(\.isDeleted).count
        case .karaoke:
            karaokeSongs.count
        }
    }

    func chooseAndImportKaraokeSong() {
        guard !karaokeImportState.isWorking else { return }
        let panel = NSOpenPanel()
        panel.title = "导入 KTV 歌曲"
        panel.prompt = "导入"
        panel.message = "选择 NCM 或标准音频；Beatbox 会自动匹配同目录下的同名 LRC。"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "ncm") ?? .data,
            .audio,
        ]
        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }
        let lyricsURL = requestAccessToMatchingLyrics(for: sourceURL)
        Task { await importKaraokeSong(from: sourceURL, lyricsURL: lyricsURL) }
    }

    func importKaraokeSong(from sourceURL: URL, lyricsURL: URL? = nil) async {
        guard !karaokeImportState.isWorking else { return }
        karaokeImportState = .converting(sourceURL.lastPathComponent)
        userMessage = sourceURL.pathExtension.lowercased() == "ncm"
            ? "正在转换 NCM，原文件会保留…"
            : "正在导入歌曲…"

        do {
            let result = try await karaokeImporter.importSong(
                sourceURL: sourceURL,
                lyricsURL: lyricsURL,
                storage: storage
            )
            karaokeImportState = .validating(result.title)
            let song = KaraokeSong(
                id: result.id,
                title: result.title,
                artist: result.artist,
                duration: result.duration,
                audioFileName: result.audioFileName,
                lyricsFileName: result.lyricsFileName,
                sourceFormat: result.sourceFormat,
                fileSize: result.fileSize,
                lyricCues: result.lyricCues
            )
            modelContext.insert(song)
            try modelContext.save()
            refreshKaraokeSongs()
            selectedLibrary = .karaoke
            selectedKaraokeSongID = song.id
            karaokeImportState = .completed(song.id)
            userMessage = lyricsURL == nil
                ? "歌曲已导入；没有找到同名 LRC，将使用无歌词模式。"
                : "歌曲和歌词已导入"
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "无法导入歌曲。"
            logger.error("Unable to import karaoke song: \(message, privacy: .private)")
            karaokeImportState = .failed(message)
            userMessage = message
        }
    }

    private func requestAccessToMatchingLyrics(for sourceURL: URL) -> URL? {
        let candidateURL = sourceURL.deletingPathExtension().appendingPathExtension("lrc")
        guard FileManager.default.fileExists(atPath: candidateURL.path) else { return nil }

        let panel = NSOpenPanel()
        panel.title = "授权读取歌词"
        panel.prompt = "使用歌词"
        panel.message = "Beatbox 找到了同名 LRC。请选中它以授权读取；取消仍会导入歌曲。"
        panel.directoryURL = candidateURL.deletingLastPathComponent()
        panel.nameFieldStringValue = candidateURL.lastPathComponent
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "lrc") ?? .plainText]

        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }

    func select(_ song: KaraokeSong) {
        selectedKaraokeSongID = song.id
    }

    func toggleKaraokePlayback(for song: KaraokeSong) {
        guard !capture.state.isCapturing else { return }
        playback.stop()
        karaokePlayback.toggle(id: song.id, url: karaokeAudioURL(for: song))
    }

    func startKaraokeSession(for song: KaraokeSong) async {
        guard canStartKaraokeSession else {
            userMessage = selectedSource.kind == .microphone
                ? "请先结束当前录音或导入任务。"
                : "KTV 跟唱录音需要麦克风音源，请先在工具栏选择麦克风。"
            return
        }
        guard let input = selectedSource.captureInput else {
            userMessage = "当前麦克风不可用。"
            return
        }

        playback.stop()
        karaokePlayback.stop()
        let songURL = karaokeAudioURL(for: song)
        guard karaokePlayback.prepare(id: song.id, url: songURL) else {
            let message = if case let .failed(_, message) = karaokePlayback.state {
                message
            } else {
                "歌曲文件不可播放"
            }
            userMessage = "无法准备歌曲：\(message)"
            karaokeSessionState = .failed(songID: song.id, message: message)
            return
        }
        let takeID = UUID()
        karaokeSessionState = .preparing(songID: song.id, takeID: takeID)
        selectedLibrary = .karaoke
        selectedKaraokeSongID = song.id
        do {
            try await capture.start(
                id: takeID,
                inProgressURL: storage.inProgressURL(for: takeID),
                finalURL: storage.finalURL(for: takeID),
                input: input
            )
            guard await capture.waitUntilReady() else {
                guard karaokeSessionState.isActive else { return }
                _ = try? await capture.stop()
                capture.acknowledgeCompletion()
                let message = "麦克风在 4 秒内没有提供有效音频，请检查设备后重试。"
                karaokeSessionState = .failed(songID: song.id, message: message)
                userMessage = message
                return
            }
            guard karaokePlayback.play(id: song.id, url: songURL) else {
                let message = if case let .failed(_, message) = karaokePlayback.state {
                    message
                } else {
                    "无法开始播放"
                }
                if let result = try? await capture.stop() {
                    _ = preserveCompletedFileForRecovery(result, mode: .audio)
                }
                capture.acknowledgeCompletion()
                karaokeSessionState = .failed(songID: song.id, message: message)
                userMessage = "无法播放歌曲：\(message)。已录到的麦克风片段会作为未完成录音恢复。"
                return
            }
        } catch let failure as CaptureFailure {
            karaokePlayback.stop()
            karaokeSessionState = .failed(
                songID: song.id,
                message: "\(failure.title)：\(failure.recoverySuggestion)"
            )
            userMessage = "\(failure.title)：\(failure.recoverySuggestion)"
        } catch {
            karaokePlayback.stop()
            karaokeSessionState = .failed(songID: song.id, message: error.localizedDescription)
            userMessage = "无法开始跟唱录音。"
        }
    }

    func toggleKaraokePause() {
        switch karaokeSessionState {
        case .recording:
            karaokePlayback.pause()
            capture.pause()
        case .paused:
            guard let song = activeKaraokeSong else { return }
            capture.resume()
            if case .recording = capture.state {
                karaokePlayback.play(id: song.id, url: karaokeAudioURL(for: song))
            }
        default:
            break
        }
    }

    @discardableResult
    func stopKaraokeSession() async -> Bool {
        if let stopTask {
            return await stopTask.value
        }
        let task = Task { [weak self] in
            await self?.performStopKaraokeSession() ?? false
        }
        stopTask = task
        let result = await task.value
        stopTask = nil
        return result
    }

    private func performStopKaraokeSession() async -> Bool {
        guard let song = activeKaraokeSong else { return false }
        karaokePlayback.pause()
        var completedResult: CaptureResult?
        do {
            guard let result = try await capture.stop() else { return false }
            completedResult = result
            let recording = Recording(
                id: result.id,
                title: "\(song.title) — 演唱",
                duration: result.duration,
                sourceKind: .microphone,
                sourceName: "KTV · \(selectedSource.name)",
                fileName: result.fileURL.lastPathComponent,
                fileSize: result.fileSize,
                waveformSamples: result.waveformSamples
            )
            modelContext.insert(recording)
            try modelContext.save()
            refreshRecordings()
            karaokePlayback.stop()
            capture.acknowledgeCompletion()
            karaokeSessionState = .completed(recordingID: recording.id)
            selectedLibrary = .all
            selectedRecordingID = recording.id
            userMessage = "演唱已保存到录音资料库"
            return true
        } catch let failure as CaptureFailure {
            karaokeSessionState = .failed(
                songID: song.id,
                message: "\(failure.title)：\(failure.recoverySuggestion)"
            )
            userMessage = "\(failure.title)：\(failure.recoverySuggestion)"
            return false
        } catch {
            modelContext.rollback()
            if let completedResult {
                _ = preserveCompletedFileForRecovery(completedResult, mode: .audio)
                capture.acknowledgeCompletion()
            }
            logger.error("Unable to persist karaoke take: \(error.localizedDescription, privacy: .private)")
            karaokeSessionState = .failed(songID: song.id, message: error.localizedDescription)
            userMessage = "演唱文件已保留，但资料库更新失败。"
            return false
        }
    }

    func reveal(_ song: KaraokeSong) {
        NSWorkspace.shared.activateFileViewerSelecting([karaokeAudioURL(for: song)])
    }

    func karaokeAudioURL(for song: KaraokeSong) -> URL {
        storage.karaokeURL(for: song.audioFileName)
    }

    func requestMicrophonePermission() async -> Bool {
        await capture.requestPermission()
    }

    func refreshMicrophones(showErrors: Bool = false) {
        do {
            let discoveredSources = try MicrophoneDiscovery()
                .devices()
                .map(AudioSource.microphone)
            microphoneSources = [.defaultMicrophone] + discoveredSources

            guard selectedSource.kind == .microphone,
                  selectedSource.id != AudioSource.defaultMicrophone.id
            else { return }

            if let refreshedSource = microphoneSources.first(where: { $0.id == selectedSource.id }) {
                selectedSource = refreshedSource
                return
            }

            let disconnectedName = selectedSource.name
            selectedSource = .defaultMicrophone
            userMessage = "“\(disconnectedName)”已断开，已切换到系统默认麦克风。"
        } catch {
            logger.error("Unable to discover microphone devices: \(error.localizedDescription, privacy: .private)")
            microphoneSources = [.defaultMicrophone]
            if selectedSource.id != AudioSource.defaultMicrophone.id {
                selectedSource = .defaultMicrophone
            }
            if showErrors {
                userMessage = "无法刷新麦克风列表，将使用 macOS 的默认输入设备。"
            }
        }
    }

    func selectMicrophone(_ source: AudioSource) {
        guard !capture.state.isCapturing,
              source.kind == .microphone,
              source.isAvailable,
              microphoneSources.contains(where: { $0.id == source.id })
        else { return }
        selectedSource = source
    }

    func refreshApplications(showErrors: Bool = false) {
        do {
            applicationSources = try ApplicationAudioDiscovery()
                .applications()
                .map(AudioSource.application)

            guard selectedSource.kind == .application,
                  let refreshedSource = applicationSources.first(where: {
                      $0.id == selectedSource.id
                  })
            else { return }
            selectedSource = refreshedSource
        } catch {
            logger.error("Unable to discover application audio: \(error.localizedDescription, privacy: .private)")
            applicationSources = []
            if showErrors {
                userMessage = "无法刷新 App 音源，请确认目标 App 正在播放声音。"
            }
        }
    }

    func selectApplication(_ source: AudioSource) {
        guard !capture.state.isCapturing,
              source.kind == .application,
              source.isAvailable,
              applicationSources.contains(where: { $0.id == source.id })
        else { return }
        selectedSource = source
    }

    func startRecording() async {
        guard canStartRecording else { return }
        userMessageAction = nil

        if selectedRecordingMode == .audio {
            switch selectedSource.kind {
            case .microphone:
                refreshMicrophones()
            case .application:
                refreshApplications()
                guard let refreshedSource = applicationSources.first(where: {
                    $0.id == selectedSource.id
                }) else {
                    userMessage = "“\(selectedSource.name)”已退出或不再输出音频，请重新选择 App。"
                    return
                }
                selectedSource = refreshedSource
            case .system:
                userMessage = selectedSource.unavailableReason
                return
            }
        }

        let input: CaptureInput
        if selectedRecordingMode == .screenAndAudio {
            input = .microphone(deviceID: nil)
        } else if let selectedInput = selectedSource.captureInput {
            input = selectedInput
        } else {
            userMessage = selectedSource.unavailableReason ?? "当前音源不可用。"
            return
        }

        playback.stop()
        karaokePlayback.stop()
        let id = UUID()
        do {
            try await capture.start(
                id: id,
                inProgressURL: storage.inProgressURL(for: id, mode: selectedRecordingMode),
                finalURL: storage.finalURL(for: id, mode: selectedRecordingMode),
                input: input,
                mode: selectedRecordingMode
            )
        } catch let failure as CaptureFailure {
            userMessage = "\(failure.title)：\(failure.recoverySuggestion)"
            userMessageAction = switch failure {
            case .permissionDenied: .microphoneSettings
            case .systemAudioPermissionDenied: .systemAudioSettings
            default: nil
            }
        } catch {
            logger.error("Unexpected recording error: \(error.localizedDescription, privacy: .private)")
            userMessage = "无法开始录音，请检查麦克风和磁盘空间。"
        }
    }

    @discardableResult
    func stopRecording() async -> Bool {
        if let stopTask {
            return await stopTask.value
        }
        let task = Task { [weak self] in
            await self?.performStopRecording() ?? false
        }
        stopTask = task
        let result = await task.value
        stopTask = nil
        return result
    }

    private func performStopRecording() async -> Bool {
        let mode = selectedRecordingMode
        var completedResult: CaptureResult?
        do {
            guard let result = try await capture.stop() else { return false }
            completedResult = result
            let sourceKind: AudioSourceKind = mode == .screenAndAudio ? .system : selectedSource.kind
            let sourceName = mode == .screenAndAudio ? "主显示器与系统音频" : selectedSource.name
            let recording = Recording(
                id: result.id,
                title: Recording.defaultTitle(sourceName: sourceName),
                duration: result.duration,
                sourceKind: sourceKind,
                sourceName: sourceName,
                recordingMode: mode,
                fileName: result.fileURL.lastPathComponent,
                fileSize: result.fileSize,
                waveformSamples: result.waveformSamples
            )
            modelContext.insert(recording)
            try modelContext.save()
            refreshRecordings()
            selectedLibrary = .all
            selectedRecordingID = recording.id
            capture.acknowledgeCompletion()
            userMessage = mode == .screenAndAudio ? "录屏已保存" : "录音已保存"
            return true
        } catch let failure as CaptureFailure {
            userMessage = "\(failure.title)：\(failure.recoverySuggestion)"
            return false
        } catch {
            modelContext.rollback()
            if let completedResult {
                _ = preserveCompletedFileForRecovery(completedResult, mode: mode)
                capture.acknowledgeCompletion()
            }
            logger.error("Unable to persist completed recording: \(error.localizedDescription, privacy: .private)")
            userMessage = "录音文件已保留，但资料库更新失败。"
            return false
        }
    }

    func toggleCapturePause() {
        switch capture.state {
        case .recording:
            capture.pause()
        case .paused:
            capture.resume()
        default:
            break
        }
    }

    func togglePlayback(for recording: Recording) {
        guard !capture.state.isCapturing else { return }
        if recording.recordingMode == .screenAndAudio {
            NSWorkspace.shared.open(fileURL(for: recording))
            return
        }
        playback.toggle(id: recording.id, url: fileURL(for: recording))
    }

    func select(_ recording: Recording) {
        selectedRecordingID = recording.id
    }

    func saveTitle(for recording: Recording, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            recording.title = trimmed
        }
        _ = saveChanges(messageOnFailure: "无法重命名录音")
    }

    func moveToRecentlyDeleted(_ recording: Recording) {
        if playback.state.recordingID == recording.id {
            playback.stop()
        }
        recording.deletedAt = .now
        guard saveChanges(messageOnFailure: "无法删除录音") else { return }
        lastDeletedRecordingID = recording.id
        selectedRecordingID = nil
        userMessage = "录音已移到“最近删除”"
        selectFirstVisibleRecordingIfNeeded()
    }

    func undoLastDeletion() {
        guard let lastDeletedRecordingID,
              let recording = recordings.first(where: { $0.id == lastDeletedRecordingID })
        else { return }
        recording.deletedAt = nil
        guard saveChanges(messageOnFailure: "无法恢复录音") else { return }
        self.lastDeletedRecordingID = nil
        selectedLibrary = .all
        selectedRecordingID = recording.id
        userMessage = "录音已恢复"
    }

    func restore(_ recording: Recording) {
        recording.deletedAt = nil
        guard saveChanges(messageOnFailure: "无法恢复录音") else { return }
        selectedLibrary = .all
        selectedRecordingID = recording.id
    }

    func deletePermanently(_ recording: Recording) {
        if playback.state.recordingID == recording.id {
            playback.stop()
        }
        let url = fileURL(for: recording)
        let quarantineURL = storage.recordingsURL.appending(
            path: ".\(recording.id.uuidString).deleting-\(UUID().uuidString)"
        )
        var quarantinedFile = false
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.moveItem(at: url, to: quarantineURL)
                quarantinedFile = true
            }
            modelContext.delete(recording)
            try modelContext.save()
            refreshRecordings()
            selectedRecordingID = nil
            selectFirstVisibleRecordingIfNeeded()
            if quarantinedFile {
                do {
                    try FileManager.default.removeItem(at: quarantineURL)
                } catch {
                    logger.error("Unable to remove quarantined recording: \(error.localizedDescription, privacy: .private)")
                }
            }
        } catch {
            modelContext.rollback()
            if quarantinedFile,
               FileManager.default.fileExists(atPath: quarantineURL.path),
               !FileManager.default.fileExists(atPath: url.path) {
                do {
                    try FileManager.default.moveItem(at: quarantineURL, to: url)
                } catch {
                    logger.error("Unable to restore recording after delete failure: \(error.localizedDescription, privacy: .private)")
                }
            }
            refreshRecordings()
            logger.error("Unable to permanently delete recording: \(error.localizedDescription, privacy: .private)")
            userMessage = "无法永久删除这段录音。"
        }
    }

    func emptyRecentlyDeleted() {
        let deletedRecordings = recordings.filter(\.isDeleted)
        for recording in deletedRecordings {
            deletePermanently(recording)
        }
    }

    func export(_ recording: Recording) {
        guard !isExporting else {
            userMessage = "请等待当前导出完成。"
            return
        }

        let sourceURL = fileURL(for: recording)
        if recording.recordingMode == .screenAndAudio {
            exportVideo(recording, sourceURL: sourceURL)
            return
        }
        guard let request = AudioExportPanel.request(recordingTitle: recording.title) else { return }

        exportingRecordingID = recording.id
        userMessage = "正在导出 \(request.format.title)…"
        Task {
            do {
                let destinationURL = try await audioExporter.export(
                    sourceURL: sourceURL,
                    destinationURL: request.destinationURL,
                    format: request.format
                )
                exportingRecordingID = nil
                userMessage = "已导出 \(destinationURL.lastPathComponent)"
            } catch is CancellationError {
                exportingRecordingID = nil
                userMessage = "导出已取消"
            } catch {
                exportingRecordingID = nil
                logger.error("Unable to export recording: \(error.localizedDescription, privacy: .private)")
                userMessage = (error as? LocalizedError)?.errorDescription ?? "无法导出录音。"
            }
        }
    }

    func isExporting(_ recording: Recording) -> Bool {
        exportingRecordingID == recording.id
    }

    func reveal(_ recording: Recording) {
        NSWorkspace.shared.activateFileViewerSelecting([fileURL(for: recording)])
    }

    func revealRecordingsFolder() {
        NSWorkspace.shared.open(storage.recordingsURL)
    }

    func openMicrophoneSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func openSystemAudioSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func fileURL(for recording: Recording) -> URL {
        storage.url(for: recording.fileName)
    }

    func dismissMessage() {
        userMessage = nil
        userMessageAction = nil
    }

    func performMessageAction() {
        switch userMessageAction {
        case .microphoneSettings:
            openMicrophoneSettings()
        case .systemAudioSettings:
            openSystemAudioSettings()
        case .recordingsFolder:
            revealRecordingsFolder()
        case nil:
            break
        }
    }

    private func refreshRecordings() {
        do {
            let descriptor = FetchDescriptor<Recording>(
                sortBy: [SortDescriptor(\Recording.createdAt, order: .reverse)]
            )
            recordings = try modelContext.fetch(descriptor)
            selectFirstVisibleRecordingIfNeeded()
        } catch {
            logger.error("Unable to load recording library: \(error.localizedDescription, privacy: .private)")
            userMessage = "无法载入录音资料库。"
        }
    }

    private func refreshKaraokeSongs() {
        do {
            let descriptor = FetchDescriptor<KaraokeSong>(
                sortBy: [SortDescriptor(\KaraokeSong.importedAt, order: .reverse)]
            )
            karaokeSongs = try modelContext.fetch(descriptor)
            selectFirstVisibleKaraokeSongIfNeeded()
        } catch {
            logger.error("Unable to load karaoke library: \(error.localizedDescription, privacy: .private)")
            userMessage = "无法载入 KTV 歌曲库。"
        }
    }

    private func recoverIncompleteRecordings() {
        do {
            let existingIDs = Set(try modelContext.fetch(FetchDescriptor<Recording>()).map(\.id))
            for inProgressURL in try storage.inProgressFiles() {
                guard inProgressURL.lastPathComponent.hasSuffix(".inprogress.m4a") else { continue }
                let idString = inProgressURL.lastPathComponent
                    .replacingOccurrences(of: ".inprogress.m4a", with: "")
                guard let id = UUID(uuidString: idString), !existingIDs.contains(id) else { continue }

                guard let player = try? AVAudioPlayer(contentsOf: inProgressURL), player.duration > 0.05 else {
                    recoveryIssueCount += 1
                    continue
                }

                let finalURL = storage.finalURL(for: id)
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try FileManager.default.removeItem(at: finalURL)
                }
                try FileManager.default.moveItem(at: inProgressURL, to: finalURL)
                let values = try finalURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                let recording = Recording(
                    id: id,
                    title: "已恢复的录音 — \((values.creationDate ?? .now).formatted(date: .abbreviated, time: .shortened))",
                    createdAt: values.creationDate ?? .now,
                    duration: player.duration,
                    sourceKind: .microphone,
                    sourceName: "系统默认麦克风",
                    fileName: finalURL.lastPathComponent,
                    fileSize: Int64(values.fileSize ?? 0),
                    integrity: .recovered
                )
                modelContext.insert(recording)
            }
            try modelContext.save()
            if recoveryIssueCount > 0 {
                userMessage = "有 \(recoveryIssueCount) 个未完成文件需要手动检查。"
            }
        } catch {
            logger.error("Unable to recover incomplete recordings: \(error.localizedDescription, privacy: .private)")
            recoveryIssueCount += 1
        }
    }

    private func recoverIncompleteScreenRecordings() async {
        do {
            let existingIDs = Set(try modelContext.fetch(FetchDescriptor<Recording>()).map(\.id))
            let files = try storage.inProgressFiles().filter {
                $0.lastPathComponent.hasSuffix(".inprogress.mov")
            }
            for inProgressURL in files {
                let idString = inProgressURL.lastPathComponent
                    .replacingOccurrences(of: ".inprogress.mov", with: "")
                guard let id = UUID(uuidString: idString), !existingIDs.contains(id) else { continue }

                let asset = AVURLAsset(url: inProgressURL)
                let durationTime = try await asset.load(.duration)
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                let duration = CMTimeGetSeconds(durationTime)
                guard duration.isFinite, duration > 0.05, !videoTracks.isEmpty else {
                    recoveryIssueCount += 1
                    continue
                }

                let finalURL = storage.finalURL(for: id, mode: .screenAndAudio)
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    try FileManager.default.removeItem(at: finalURL)
                }
                try FileManager.default.moveItem(at: inProgressURL, to: finalURL)
                let values = try finalURL.resourceValues(forKeys: [.fileSizeKey, .creationDateKey])
                let recording = Recording(
                    id: id,
                    title: "已恢复的录屏 — \((values.creationDate ?? .now).formatted(date: .abbreviated, time: .shortened))",
                    createdAt: values.creationDate ?? .now,
                    duration: duration,
                    sourceKind: .system,
                    sourceName: "主显示器与系统音频",
                    recordingMode: .screenAndAudio,
                    fileName: finalURL.lastPathComponent,
                    fileSize: Int64(values.fileSize ?? 0),
                    integrity: .recovered
                )
                modelContext.insert(recording)
            }
            try modelContext.save()
            refreshRecordings()
            if recoveryIssueCount > 0 {
                userMessage = "有 \(recoveryIssueCount) 个未完成文件需要手动检查。"
            }
        } catch {
            logger.error("Unable to recover incomplete screen recordings: \(error.localizedDescription, privacy: .private)")
            recoveryIssueCount += 1
        }
    }

    private func exportVideo(_ recording: Recording, sourceURL: URL) {
        guard let destinationURL = VideoExportPanel.destination(recordingTitle: recording.title) else {
            return
        }
        exportingRecordingID = recording.id
        userMessage = "正在导出 MOV…"
        Task {
            do {
                let exportedURL = try await videoExporter.export(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL
                )
                exportingRecordingID = nil
                userMessage = "已导出 \(exportedURL.lastPathComponent)"
            } catch is CancellationError {
                exportingRecordingID = nil
                userMessage = "导出已取消"
            } catch {
                exportingRecordingID = nil
                logger.error("Unable to export screen recording: \(error.localizedDescription, privacy: .private)")
                userMessage = (error as? LocalizedError)?.errorDescription ?? "无法导出录屏。"
            }
        }
    }

    @discardableResult
    private func preserveCompletedFileForRecovery(
        _ result: CaptureResult,
        mode: RecordingMode
    ) -> Bool {
        let recoveryURL = storage.inProgressURL(for: result.id, mode: mode)
        guard result.fileURL != recoveryURL else { return true }
        guard !FileManager.default.fileExists(atPath: recoveryURL.path) else {
            logger.error("Recovery destination already exists for completed capture")
            return false
        }
        do {
            try FileManager.default.moveItem(at: result.fileURL, to: recoveryURL)
            return true
        } catch {
            logger.error("Unable to stage completed capture for recovery: \(error.localizedDescription, privacy: .private)")
            return false
        }
    }

    private func selectFirstVisibleRecordingIfNeeded() {
        if let selectedRecordingID,
           visibleRecordings.contains(where: { $0.id == selectedRecordingID }) {
            return
        }
        selectedRecordingID = visibleRecordings.first?.id
    }

    private func selectFirstVisibleKaraokeSongIfNeeded() {
        if let selectedKaraokeSongID,
           visibleKaraokeSongs.contains(where: { $0.id == selectedKaraokeSongID }) {
            return
        }
        selectedKaraokeSongID = visibleKaraokeSongs.first?.id
    }

    @discardableResult
    private func saveChanges(messageOnFailure: String) -> Bool {
        do {
            try modelContext.save()
            refreshRecordings()
            return true
        } catch {
            modelContext.rollback()
            refreshRecordings()
            logger.error("Unable to save library changes: \(error.localizedDescription, privacy: .private)")
            userMessage = messageOnFailure
            return false
        }
    }

    private func updateDockStatus(for state: CaptureState) {
        let badge: String? = switch state {
        case .recording: "REC"
        case .paused: "PAUSED"
        case .finalizing: "SAVING"
        default: nil
        }
        NSApp.dockTile.badgeLabel = badge
        NSApp.dockTile.display()
    }

    private func synchronizeKaraokeSession(with captureState: CaptureState) {
        guard let songID = karaokeSessionState.songID else { return }
        switch captureState {
        case let .recording(takeID):
            karaokeSessionState = .recording(songID: songID, takeID: takeID)
        case let .paused(takeID):
            karaokeSessionState = .paused(songID: songID, takeID: takeID)
        case let .finalizing(takeID):
            karaokeSessionState = .finalizing(songID: songID, takeID: takeID)
        case let .failed(failure):
            karaokePlayback.pause()
            karaokeSessionState = .failed(
                songID: songID,
                message: "\(failure.title)：\(failure.recoverySuggestion)"
            )
        default:
            break
        }
    }

}
