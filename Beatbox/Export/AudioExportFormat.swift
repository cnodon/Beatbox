import Foundation
import UniformTypeIdentifiers

nonisolated enum AudioExportFormat: String, CaseIterable, Identifiable, Sendable {
    case m4aAAC
    case wavPCM
    case m4aALAC
    case aiffPCM
    case cafPCM
    case flac

    var id: String { rawValue }

    var title: String {
        switch self {
        case .m4aAAC: "M4A — AAC"
        case .wavPCM: "WAV — PCM"
        case .m4aALAC: "M4A — Apple Lossless"
        case .aiffPCM: "AIFF — PCM"
        case .cafPCM: "CAF — PCM"
        case .flac: "FLAC — 无损"
        }
    }

    var detail: String {
        switch self {
        case .m4aAAC: "体积小、兼容性好；原始 M4A 录音可直接复制，不重复压缩。"
        case .wavPCM: "16-bit 无压缩音频，适合剪辑、播客和通用音频软件。"
        case .m4aALAC: "Apple 无损压缩，保留完整音质且比 WAV 更节省空间。"
        case .aiffPCM: "16-bit 无压缩音频，适合传统 Mac 音频工作流。"
        case .cafPCM: "24-bit Core Audio 文件，适合 Apple 平台上的后期处理。"
        case .flac: "24-bit 开放无损格式，适合跨平台归档。"
        }
    }

    var fileExtension: String {
        switch self {
        case .m4aAAC, .m4aALAC: "m4a"
        case .wavPCM: "wav"
        case .aiffPCM: "aiff"
        case .cafPCM: "caf"
        case .flac: "flac"
        }
    }

    var contentType: UTType {
        switch self {
        case .m4aAAC, .m4aALAC:
            .mpeg4Audio
        case .wavPCM:
            .wav
        case .aiffPCM:
            .aiff
        case .cafPCM:
            UTType(filenameExtension: "caf", conformingTo: .audio) ?? .audio
        case .flac:
            UTType(filenameExtension: "flac", conformingTo: .audio) ?? .audio
        }
    }
}

nonisolated struct AudioExportRequest: Sendable {
    let destinationURL: URL
    let format: AudioExportFormat
}
