import Foundation
import SwiftData

nonisolated struct LyricCue: Codable, Equatable, Sendable {
    let time: TimeInterval
    let text: String
}

@Model
final class KaraokeSong {
    @Attribute(.unique) var id: UUID
    var title: String
    var artist: String
    var importedAt: Date
    var duration: TimeInterval
    var audioFileName: String
    var lyricsFileName: String?
    var sourceFormat: String
    var fileSize: Int64
    var lyricData: Data

    init(
        id: UUID,
        title: String,
        artist: String,
        importedAt: Date = .now,
        duration: TimeInterval,
        audioFileName: String,
        lyricsFileName: String?,
        sourceFormat: String,
        fileSize: Int64,
        lyricCues: [LyricCue]
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.importedAt = importedAt
        self.duration = duration
        self.audioFileName = audioFileName
        self.lyricsFileName = lyricsFileName
        self.sourceFormat = sourceFormat
        self.fileSize = fileSize
        self.lyricData = (try? JSONEncoder().encode(lyricCues)) ?? Data()
    }

    var lyricCues: [LyricCue] {
        (try? JSONDecoder().decode([LyricCue].self, from: lyricData)) ?? []
    }
}
