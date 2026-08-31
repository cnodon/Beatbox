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

    var takeID: UUID? {
        switch self {
        case let .preparing(_, takeID), let .recording(_, takeID),
             let .paused(_, takeID), let .finalizing(_, takeID):
            takeID
        case .idle, .completed, .failed:
            nil
        }
    }

    var failureMessage: String? {
        guard case let .failed(_, message) = self else { return nil }
        return message
    }

    var isActive: Bool {
        switch self {
        case .preparing, .recording, .paused, .finalizing:
            true
        case .idle, .completed, .failed:
            false
        }
    }

    func synchronized(with captureState: CaptureState) -> KaraokeSessionState {
        guard let songID, let takeID else { return self }
        return switch captureState {
        case .recording(takeID):
            .recording(songID: songID, takeID: takeID)
        case .paused(takeID):
            .paused(songID: songID, takeID: takeID)
        case .finalizing(takeID):
            .finalizing(songID: songID, takeID: takeID)
        case let .failed(failure):
            .failed(
                songID: songID,
                message: "\(failure.title)：\(failure.recoverySuggestion)"
            )
        case .idle, .requestingPermission, .preparing, .completed,
             .recording, .paused, .finalizing:
            self
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
