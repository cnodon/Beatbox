import SwiftUI

struct KaraokeSongListView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel

        List(selection: $appModel.selectedKaraokeSongID) {
            ForEach(appModel.visibleKaraokeSongs) { song in
                KaraokeSongRow(song: song)
                    .tag(song.id)
                    .contextMenu {
                        Button("试听") { appModel.toggleKaraokePlayback(for: song) }
                            .disabled(appModel.capture.state.isCapturing)
                        Button("在 Finder 中显示") { appModel.reveal(song) }
                    }
            }
        }
        .overlay {
            if appModel.visibleKaraokeSongs.isEmpty {
                ContentUnavailableView {
                    Label(
                        appModel.karaokeSearchText.isEmpty ? "还没有 KTV 歌曲" : "没有匹配的歌曲",
                        systemImage: "music.mic"
                    )
                } description: {
                    Text(appModel.karaokeSearchText.isEmpty
                         ? "导入 NCM 或标准音频；同名 LRC 会自动匹配。"
                         : "尝试搜索其他歌曲或歌手。")
                } actions: {
                    if appModel.karaokeSearchText.isEmpty {
                        Button("导入歌曲…") { appModel.chooseAndImportKaraokeSong() }
                            .buttonStyle(.borderedProminent)
                            .disabled(appModel.karaokeImportState.isWorking)
                    }
                }
            }
        }
        .searchable(text: $appModel.karaokeSearchText, placement: .toolbar, prompt: "搜索歌曲")
        .navigationTitle("KTV · 歌曲")
        .toolbar {
            ToolbarItem {
                Button("导入歌曲…", systemImage: "plus") {
                    appModel.chooseAndImportKaraokeSong()
                }
                .disabled(appModel.karaokeImportState.isWorking)
                .help("导入 NCM 或标准音频，快捷键 Command I")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if appModel.karaokeImportState.isWorking {
                HStack(spacing: 9) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在转换并验证歌曲…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.bar)
            }
        }
    }
}

private struct KaraokeSongRow: View {
    let song: KaraokeSong

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "music.note")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 42, height: 38)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(song.title)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(song.duration.beatboxTimestamp)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    Text(song.artist)
                    Text("·")
                    Text(song.sourceFormat)
                    Text("·")
                    Label(
                        song.lyricCues.isEmpty ? "无歌词" : "有歌词",
                        systemImage: song.lyricCues.isEmpty ? "text.badge.xmark" : "text.badge.checkmark"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(song.title)，\(song.artist)，\(song.duration.beatboxTimestamp)，\(song.lyricCues.isEmpty ? "无歌词" : "有歌词")"
        )
    }
}
