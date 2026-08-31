import AppKit
import SwiftUI

struct RecordingListView: View {
    @Environment(AppModel.self) private var appModel
    @State private var showingEmptyTrashConfirmation = false
    @State private var recordingsPendingPermanentDeletionIDs: Set<UUID> = []

    var body: some View {
        @Bindable var appModel = appModel

        List(selection: $appModel.selectedRecordingIDs) {
            ForEach(appModel.visibleRecordings) { recording in
                RecordingRow(
                    recording: recording,
                    playbackStatus: playbackStatus(for: recording)
                )
                    .tag(recording.id)
                    .contextMenu {
                        recordingContextMenu(recording)
                    }
                    .onDrag {
                        NSItemProvider(contentsOf: appModel.fileURL(for: recording)) ?? NSItemProvider()
                    }
            }
        }
        .overlay {
            if appModel.visibleRecordings.isEmpty {
                ContentUnavailableView {
                    Label(
                        emptyTitle,
                        systemImage: appModel.selectedLibrary == .all ? "waveform" : "trash"
                    )
                } description: {
                    Text(emptyDescription)
                } actions: {
                    if !appModel.searchText.isEmpty {
                        Button("清除搜索") { appModel.searchText = "" }
                    }
                }
            }
        }
        .searchable(text: $appModel.searchText, placement: .toolbar, prompt: "搜索录音")
        .navigationTitle(appModel.selectedLibrary.title)
        .toolbar {
            if appModel.visibleRecordings.count > 1 {
                ToolbarItem {
                    Button {
                        if hasSelectedAllVisibleRecordings {
                            appModel.clearRecordingSelection()
                        } else {
                            appModel.selectAllVisibleRecordings()
                        }
                    } label: {
                        Label(
                            hasSelectedAllVisibleRecordings ? "取消全选" : "全选",
                            systemImage: hasSelectedAllVisibleRecordings
                                ? "checkmark.circle.fill"
                                : "checkmark.circle"
                        )
                    }
                    .help(hasSelectedAllVisibleRecordings ? "取消选择全部录音" : "选择当前列表中的全部录音（⌘A）")
                }
            }

            if !appModel.selectedVisibleRecordings.isEmpty {
                if appModel.selectedLibrary == .recentlyDeleted {
                    ToolbarItem {
                        Button {
                            appModel.restore(appModel.selectedVisibleRecordings)
                        } label: {
                            Label("恢复 \(selectedCount) 项", systemImage: "arrow.uturn.backward")
                        }
                        .help("恢复全部选中的录音")
                    }
                    ToolbarItem {
                        Button(role: .destructive) {
                            requestPermanentDeletion(of: appModel.selectedVisibleRecordings)
                        } label: {
                            Label("删除 \(selectedCount) 项", systemImage: "trash")
                        }
                        .help("永久删除全部选中的录音")
                    }
                } else {
                    ToolbarItem {
                        Button(role: .destructive) {
                            appModel.moveToRecentlyDeleted(appModel.selectedVisibleRecordings)
                        } label: {
                            Label("删除 \(selectedCount) 项", systemImage: "trash")
                        }
                        .help("将全部选中的录音移到最近删除")
                    }
                }
            }

            if appModel.selectedLibrary == .recentlyDeleted,
               !appModel.visibleRecordings.isEmpty {
                ToolbarItem {
                    Button("清空最近删除", systemImage: "trash.slash") {
                        showingEmptyTrashConfirmation = true
                    }
                    .help("永久删除最近删除中的全部录音")
                }
            }
        }
        .onDeleteCommand {
            let selectedRecordings = appModel.selectedVisibleRecordings
            guard !selectedRecordings.isEmpty else { return }
            if appModel.selectedLibrary == .recentlyDeleted {
                requestPermanentDeletion(of: selectedRecordings)
            } else {
                appModel.moveToRecentlyDeleted(selectedRecordings)
            }
        }
        .confirmationDialog(
            "永久删除最近删除中的全部录音？",
            isPresented: $showingEmptyTrashConfirmation
        ) {
            Button("永久删除", role: .destructive) { appModel.emptyRecentlyDeleted() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将永久删除最近删除中的全部文件，此操作无法撤销。")
        }
        .confirmationDialog(
            permanentDeletionTitle,
            isPresented: Binding(
                get: { !recordingsPendingPermanentDeletionIDs.isEmpty },
                set: { if !$0 { recordingsPendingPermanentDeletionIDs.removeAll() } }
            )
        ) {
            Button("永久删除", role: .destructive) {
                appModel.deletePermanently(recordingsPendingPermanentDeletion)
                recordingsPendingPermanentDeletionIDs.removeAll()
            }
            Button("取消", role: .cancel) {
                recordingsPendingPermanentDeletionIDs.removeAll()
            }
        } message: {
            Text("所选 \(recordingsPendingPermanentDeletion.count) 个文件将被移除，此操作无法撤销。")
        }
    }

    @ViewBuilder
    private func recordingContextMenu(_ recording: Recording) -> some View {
        let targets = contextTargets(for: recording)
        if recording.isDeleted {
            Button(targets.count == 1 ? "恢复" : "恢复 \(targets.count) 项") {
                appModel.restore(targets)
            }
            Button("立即删除…", role: .destructive) {
                requestPermanentDeletion(of: targets)
            }
        } else {
            if targets.count == 1, recording.recordingMode == .screenAndAudio {
                Button("显示录屏") {
                    appModel.selectedRecordingID = recording.id
                }
            } else if targets.count == 1 {
                Button(playbackStatus(for: recording) == .playing ? "暂停" : "播放") {
                    appModel.togglePlayback(for: recording)
                }
            }
            if targets.count == 1 {
                Button("导出为…") { appModel.export(recording) }
                    .disabled(appModel.isExporting || appModel.capture.state.isCapturing)
                Button("在 Finder 中显示") { appModel.reveal(recording) }
            }
            Divider()
            Button(
                targets.count == 1 ? "移到最近删除" : "将 \(targets.count) 项移到最近删除",
                role: .destructive
            ) {
                appModel.moveToRecentlyDeleted(targets)
            }
        }
    }

    private var emptyTitle: String {
        if !appModel.searchText.isEmpty { return "没有匹配的录音" }
        return appModel.selectedLibrary == .all ? "还没有录音" : "没有最近删除的录音"
    }

    private var emptyDescription: String {
        if !appModel.searchText.isEmpty { return "尝试搜索其他名称或音源。" }
        return appModel.selectedLibrary == .all
            ? "选择麦克风，然后点击左侧资料库底部的录音按钮。"
            : "移到这里的录音可以恢复或永久删除。"
    }

    private var recordingsPendingPermanentDeletion: [Recording] {
        appModel.recordings.filter { recordingsPendingPermanentDeletionIDs.contains($0.id) }
    }

    private var permanentDeletionTitle: String {
        let recordings = recordingsPendingPermanentDeletion
        guard recordings.count == 1, let recording = recordings.first else {
            return "永久删除所选 \(recordings.count) 个录音？"
        }
        return "永久删除“\(recording.title)”？"
    }

    private var selectedCount: Int { appModel.selectedVisibleRecordings.count }

    private var hasSelectedAllVisibleRecordings: Bool {
        let visibleIDs = Set(appModel.visibleRecordings.map(\.id))
        return !visibleIDs.isEmpty && visibleIDs.isSubset(of: appModel.selectedRecordingIDs)
    }

    private func contextTargets(for recording: Recording) -> [Recording] {
        guard appModel.selectedRecordingIDs.contains(recording.id) else { return [recording] }
        let selected = appModel.selectedVisibleRecordings
        return selected.isEmpty ? [recording] : selected
    }

    private func requestPermanentDeletion(of recordings: [Recording]) {
        recordingsPendingPermanentDeletionIDs = Set(recordings.map(\.id))
    }

    private func playbackStatus(for recording: Recording) -> RecordingRowPlaybackStatus {
        guard appModel.playback.state.recordingID == recording.id else { return .idle }
        if case .playing(recording.id) = appModel.playback.state { return .playing }
        return .paused
    }
}

private enum RecordingRowPlaybackStatus: Equatable {
    case idle
    case playing
    case paused
}

private struct RecordingRow: View {
    let recording: Recording
    let playbackStatus: RecordingRowPlaybackStatus

    var body: some View {
        HStack(spacing: 11) {
            Group {
                if recording.recordingMode == .screenAndAudio {
                    Image(systemName: "display")
                        .font(.title3)
                        .foregroundStyle(recording.isDeleted ? Color.secondary : Color.accentColor)
                } else {
                    WaveformView(
                        samples: recording.waveformSamples,
                        activeColor: recording.isDeleted ? .secondary : .accentColor
                    )
                }
            }
            .frame(width: 42, height: 30)
            .padding(.horizontal, 5)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
            .overlay(alignment: .bottomTrailing) {
                if playbackStatus != .idle, recording.recordingMode == .audio {
                    Image(systemName: playbackStatus == .playing ? "speaker.wave.2.fill" : "pause.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(Color.accentColor, in: Circle())
                        .offset(x: 4, y: 4)
                        .accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(recording.title)
                        .lineLimit(1)
                        .fontWeight(.medium)
                    Spacer(minLength: 8)
                    Text(recording.duration.beatboxTimestamp)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 5) {
                    Image(systemName: recording.sourceKind.systemImage)
                    Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(recording.fileSize.beatboxFileSize)
                    if recording.integrity == .recovered {
                        Text("· 已恢复")
                            .foregroundStyle(.orange)
                    }
                    if playbackStatus == .playing {
                        Text("· 正在播放")
                            .foregroundStyle(.tint)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint(recording.isDeleted ? "可从快捷菜单恢复或永久删除" : "选择后在详情中播放和导出")
    }

    private var accessibilityDescription: String {
        var parts = [recording.title, recording.duration.beatboxTimestamp, recording.sourceName]
        if recording.recordingMode == .screenAndAudio { parts.append("录屏") }
        if recording.integrity == .recovered { parts.append("已恢复") }
        if playbackStatus == .playing { parts.append("正在播放") }
        if recording.isDeleted { parts.append("位于最近删除") }
        return parts.joined(separator: "，")
    }
}
