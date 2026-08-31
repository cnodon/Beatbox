import Foundation

nonisolated enum RecordingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case audio
    case screenAndAudio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .audio: "录音"
        case .screenAndAudio: "录屏与音频"
        }
    }

    var systemImage: String {
        switch self {
        case .audio: "waveform"
        case .screenAndAudio: "rectangle.inset.filled.and.person.filled"
        }
    }

    var fileExtension: String {
        switch self {
        case .audio: "m4a"
        case .screenAndAudio: "mov"
        }
    }

    var fileFormatTitle: String {
        switch self {
        case .audio: "M4A（AAC）"
        case .screenAndAudio: "MOV（H.264 + AAC）"
        }
    }
}
