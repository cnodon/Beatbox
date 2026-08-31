import Foundation
import SwiftData

enum RecordingIntegrity: String, Codable, Sendable {
    case complete
    case recovered
}

@Model
final class Recording {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var duration: TimeInterval
    var sourceKindRawValue: String
    var sourceName: String
    var recordingModeRawValue: String = RecordingMode.audio.rawValue
    var fileName: String
    var fileSize: Int64
    var integrityRawValue: String
    var deletedAt: Date?
    var waveformData: Data

    init(
        id: UUID,
        title: String,
        createdAt: Date = .now,
        duration: TimeInterval,
        sourceKind: AudioSourceKind,
        sourceName: String,
        recordingMode: RecordingMode = .audio,
        fileName: String,
        fileSize: Int64,
        integrity: RecordingIntegrity = .complete,
        deletedAt: Date? = nil,
        waveformSamples: [Float] = []
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.duration = duration
        self.sourceKindRawValue = sourceKind.rawValue
        self.sourceName = sourceName
        self.recordingModeRawValue = recordingMode.rawValue
        self.fileName = fileName
        self.fileSize = fileSize
        self.integrityRawValue = integrity.rawValue
        self.deletedAt = deletedAt
        self.waveformData = (try? JSONEncoder().encode(waveformSamples)) ?? Data()
    }

    var sourceKind: AudioSourceKind {
        AudioSourceKind(rawValue: sourceKindRawValue) ?? .microphone
    }

    var integrity: RecordingIntegrity {
        RecordingIntegrity(rawValue: integrityRawValue) ?? .complete
    }

    var recordingMode: RecordingMode {
        RecordingMode(rawValue: recordingModeRawValue) ?? .audio
    }

    var waveformSamples: [Float] {
        (try? JSONDecoder().decode([Float].self, from: waveformData)) ?? []
    }

    var isDeleted: Bool {
        deletedAt != nil
    }

    static func defaultTitle(sourceName: String, date: Date = .now) -> String {
        let timestamp = date.formatted(
            .dateTime
                .year()
                .month(.twoDigits)
                .day(.twoDigits)
                .hour(.twoDigits(amPM: .omitted))
                .minute(.twoDigits)
        )
        return "\(sourceName) — \(timestamp)"
    }
}
