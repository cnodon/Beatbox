import Foundation

enum KaraokeSessionState: Equatable, Sendable {
    case idle
    case preparing(songID: UUID, takeID: UUID)
    case recording(songID: UUID, takeID: UUID)
    case paused(songID: UUID, takeID: UUID)
    case finalizing(songID: UUID, takeID: UUID)
    case completed(recordingID: UUID)
    case failed(songID: UUID?, message: String)

    var songID: UUID? {
        switch self {
        case let .preparing(songID, _), let .recording(songID, _),
             let .paused(songID, _), let .finalizing(songID, _):
            songID
        case let .failed(songID, _):
            songID
        case .idle, .completed:
            nil
        }
    }

    var isActive: Bool {
        switch self {
        case .preparing, .recording, .paused, .finalizing:
            true
        case .idle, .completed, .failed:
            false
        }
    }
}

enum KaraokeImportState: Equatable, Sendable {
    case idle
    case converting(String)
    case validating(String)
    case completed(UUID)
    case failed(String)

    var isWorking: Bool {
        switch self {
        case .converting, .validating: true
        case .idle, .completed, .failed: false
        }
    }
}
