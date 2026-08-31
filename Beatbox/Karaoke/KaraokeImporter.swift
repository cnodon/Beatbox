import AVFAudio
import Foundation

struct KaraokeImportResult: Sendable {
    let id: UUID
    let title: String
    let artist: String
    let duration: TimeInterval
    let audioFileName: String
    let lyricsFileName: String?
    let sourceFormat: String
    let fileSize: Int64
    let lyricCues: [LyricCue]
}

enum KaraokeImportFailure: LocalizedError, Sendable {
    case unsupportedFile
    case converterMissing
    case conversionFailed(String)
    case convertedFileMissing
    case invalidAudio
    case unableToStore(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            "请选择 NCM、MP3、FLAC、M4A、WAV、AIFF、CAF 或 AAC 文件。"
        case .converterMissing:
            "未找到 ncmdump。请先在终端运行“brew install ncmdump”，然后重试。"
        case let .conversionFailed(detail):
            detail.isEmpty ? "NCM 转换失败。" : "NCM 转换失败：\(detail)"
        case .convertedFileMissing:
            "ncmdump 已结束，但没有生成 MP3 或 FLAC 文件。"
        case .invalidAudio:
            "转换结果不是可播放的音频文件，原始 NCM 已保留。"
        case let .unableToStore(detail):
            "无法保存歌曲：\(detail)"
        }
    }
}

nonisolated enum NCMToolLocator {
    static func executableURL(fileManager: FileManager = .default) -> URL? {
        let candidates = [
            "/opt/homebrew/bin/ncmdump",
            "/usr/local/bin/ncmdump",
        ]
        return candidates
            .map(URL.init(fileURLWithPath:))
            .first { fileManager.isExecutableFile(atPath: $0.path) }
    }
}

actor KaraokeImporter {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func importSong(
        sourceURL: URL,
        lyricsURL: URL?,
        storage: StoragePaths,
        id: UUID = UUID()
    ) throws -> KaraokeImportResult {
        let sourceAccess = sourceURL.startAccessingSecurityScopedResource()
        let lyricsAccess = lyricsURL?.startAccessingSecurityScopedResource() ?? false
        defer {
            if sourceAccess { sourceURL.stopAccessingSecurityScopedResource() }
            if lyricsAccess { lyricsURL?.stopAccessingSecurityScopedResource() }
        }

        let stagingURL = storage.karaokeStagingURL(for: id)
        do {
            if fileManager.fileExists(atPath: stagingURL.path) {
                try fileManager.removeItem(at: stagingURL)
            }
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
            defer { try? fileManager.removeItem(at: stagingURL) }

            let sourceExtension = sourceURL.pathExtension.lowercased()
            let preparedAudioURL: URL
            if sourceExtension == "ncm" {
                preparedAudioURL = try convertNCM(sourceURL, outputDirectory: stagingURL)
            } else if supportedAudioExtensions.contains(sourceExtension) {
                preparedAudioURL = stagingURL.appending(path: sourceURL.lastPathComponent)
                try fileManager.copyItem(at: sourceURL, to: preparedAudioURL)
            } else {
                throw KaraokeImportFailure.unsupportedFile
            }

            guard let player = try? AVAudioPlayer(contentsOf: preparedAudioURL),
                  player.duration > 0.05
            else {
                throw KaraokeImportFailure.invalidAudio
            }

            let audioExtension = preparedAudioURL.pathExtension.lowercased()
            let destinationAudioURL = storage.karaokeAudioURL(
                for: id,
                fileExtension: audioExtension
            )
            if fileManager.fileExists(atPath: destinationAudioURL.path) {
                try fileManager.removeItem(at: destinationAudioURL)
            }
            try fileManager.moveItem(at: preparedAudioURL, to: destinationAudioURL)

            var lyricCues: [LyricCue] = []
            var lyricsFileName: String?
            if let lyricsURL, fileManager.fileExists(atPath: lyricsURL.path) {
                lyricCues = try LRCParser.parseFile(at: lyricsURL)
                let destinationLyricsURL = storage.karaokeLyricsURL(for: id)
                if fileManager.fileExists(atPath: destinationLyricsURL.path) {
                    try fileManager.removeItem(at: destinationLyricsURL)
                }
                try fileManager.copyItem(at: lyricsURL, to: destinationLyricsURL)
                lyricsFileName = destinationLyricsURL.lastPathComponent
            }

            let values = try destinationAudioURL.resourceValues(forKeys: [.fileSizeKey])
            let metadata = filenameMetadata(from: sourceURL)
            return KaraokeImportResult(
                id: id,
                title: metadata.title,
                artist: metadata.artist,
                duration: player.duration,
                audioFileName: destinationAudioURL.lastPathComponent,
                lyricsFileName: lyricsFileName,
                sourceFormat: sourceExtension == "ncm"
                    ? "NCM → \(audioExtension.uppercased())"
                    : audioExtension.uppercased(),
                fileSize: Int64(values.fileSize ?? 0),
                lyricCues: lyricCues
            )
        } catch let failure as KaraokeImportFailure {
            throw failure
        } catch {
            throw KaraokeImportFailure.unableToStore(error.localizedDescription)
        }
    }

    private func convertNCM(_ sourceURL: URL, outputDirectory: URL) throws -> URL {
        guard let executableURL = NCMToolLocator.executableURL(fileManager: fileManager) else {
            throw KaraokeImportFailure.converterMissing
        }

        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = executableURL
        process.arguments = [sourceURL.path, "-o", outputDirectory.path]
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        process.currentDirectoryURL = outputDirectory

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw KaraokeImportFailure.conversionFailed(error.localizedDescription)
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
            throw KaraokeImportFailure.conversionFailed(output)
        }

        let convertedFiles = try fileManager.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ).filter { supportedConvertedExtensions.contains($0.pathExtension.lowercased()) }
        guard convertedFiles.count == 1, let convertedURL = convertedFiles.first else {
            throw KaraokeImportFailure.convertedFileMissing
        }
        return convertedURL
    }

    private func filenameMetadata(from sourceURL: URL) -> (artist: String, title: String) {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let parts = baseName.components(separatedBy: " - ")
        guard parts.count >= 2 else { return ("未知艺术家", baseName) }
        let artist = parts[0]
        return (artist, parts.dropFirst().joined(separator: " - "))
    }

    private let supportedAudioExtensions: Set<String> = [
        "mp3", "flac", "m4a", "wav", "aiff", "aif", "caf", "aac",
    ]
    private let supportedConvertedExtensions: Set<String> = ["mp3", "flac"]
}
