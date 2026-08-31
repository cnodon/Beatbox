import AVFAudio
import CommonCrypto
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
    case conversionFailed(String)
    case invalidAudio
    case unableToStore(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            "请选择 NCM、MP3、FLAC、M4A、WAV、AIFF、CAF 或 AAC 文件。"
        case let .conversionFailed(detail):
            detail.isEmpty ? "NCM 转换失败。" : "NCM 转换失败：\(detail)"
        case .invalidAudio:
            "转换结果不是可播放的音频文件，原始 NCM 已保留。"
        case let .unableToStore(detail):
            "无法保存歌曲：\(detail)"
        }
    }
}

nonisolated struct NativeNCMDecoder {
    enum DecodeError: LocalizedError {
        case invalidContainer
        case invalidKey
        case unsupportedAudio

        var errorDescription: String? {
            switch self {
            case .invalidContainer: "NCM 文件结构无效或已经损坏。"
            case .invalidKey: "无法读取 NCM 音频密钥。"
            case .unsupportedAudio: "NCM 中没有可识别的 MP3 或 FLAC 音频。"
            }
        }
    }

    private static let signature = Data("CTENFDAM".utf8)
    private static let coreKey = Data([
        0x68, 0x7A, 0x48, 0x52, 0x41, 0x6D, 0x73, 0x6F,
        0x35, 0x6B, 0x49, 0x6E, 0x62, 0x61, 0x78, 0x57,
    ])
    private static let maximumSectionSize = 64 * 1_024 * 1_024

    func decode(
        sourceURL: URL,
        outputDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let input = try FileHandle(forReadingFrom: sourceURL)
        defer { try? input.close() }

        guard try readExactly(8, from: input) == Self.signature else {
            throw DecodeError.invalidContainer
        }
        try skip(2, in: input)

        let encryptedKeyLength = try sectionLength(from: input)
        var encryptedKey = try readExactly(encryptedKeyLength, from: input)
        encryptedKey.mutateBytes { $0 ^= 0x64 }
        let decryptedKey = try aesECBDecrypt(encryptedKey, key: Self.coreKey)
        guard decryptedKey.count > 17 else { throw DecodeError.invalidKey }
        let keyBox = buildKeyBox(key: Array(decryptedKey.dropFirst(17)))

        let metadataLength = try sectionLength(from: input, permitsEmpty: true)
        try skip(metadataLength, in: input)
        try skip(5, in: input)

        let coverFrameLength = try integer(from: input)
        let imageLength = try integer(from: input)
        guard coverFrameLength >= imageLength,
              coverFrameLength <= Self.maximumSectionSize else {
            throw DecodeError.invalidContainer
        }
        try skip(coverFrameLength, in: input)

        var output: FileHandle?
        var outputURL: URL?
        var streamOffset = 0
        defer { try? output?.close() }

        while let encryptedChunk = try input.read(upToCount: 32_768), !encryptedChunk.isEmpty {
            var decryptedChunk = encryptedChunk
            decryptedChunk.withUnsafeMutableBytes { rawBuffer in
                guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
                for index in 0..<rawBuffer.count {
                    let position = (streamOffset + index + 1) & 0xFF
                    let first = Int(keyBox[position])
                    let second = Int(keyBox[(first + position) & 0xFF])
                    let mask = keyBox[(first + second) & 0xFF]
                    bytes[index] ^= mask
                }
            }

            if output == nil {
                let fileExtension = try audioFileExtension(for: decryptedChunk)
                let baseName = sourceURL.deletingPathExtension().lastPathComponent
                let destination = outputDirectory
                    .appending(path: baseName)
                    .appendingPathExtension(fileExtension)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                guard fileManager.createFile(atPath: destination.path, contents: nil) else {
                    throw CocoaError(.fileWriteUnknown)
                }
                output = try FileHandle(forWritingTo: destination)
                outputURL = destination
            }

            try output?.write(contentsOf: decryptedChunk)
            streamOffset += decryptedChunk.count
        }

        guard let outputURL else { throw DecodeError.unsupportedAudio }
        try output?.synchronize()
        return outputURL
    }

    private func sectionLength(from input: FileHandle, permitsEmpty: Bool = false) throws -> Int {
        let length = try integer(from: input)
        guard length <= Self.maximumSectionSize, permitsEmpty || length > 0 else {
            throw DecodeError.invalidContainer
        }
        return length
    }

    private func integer(from input: FileHandle) throws -> Int {
        let data = try readExactly(4, from: input)
        return Int(data.withUnsafeBytes { rawBuffer in
            UInt32(littleEndian: rawBuffer.loadUnaligned(as: UInt32.self))
        })
    }

    private func readExactly(_ count: Int, from input: FileHandle) throws -> Data {
        guard count >= 0,
              let data = try input.read(upToCount: count),
              data.count == count else {
            throw DecodeError.invalidContainer
        }
        return data
    }

    private func skip(_ count: Int, in input: FileHandle) throws {
        guard count >= 0 else { throw DecodeError.invalidContainer }
        let offset = try input.offset()
        try input.seek(toOffset: offset + UInt64(count))
    }

    private func aesECBDecrypt(_ encrypted: Data, key: Data) throws -> Data {
        guard encrypted.count.isMultiple(of: kCCBlockSizeAES128),
              key.count == kCCKeySizeAES128 else {
            throw DecodeError.invalidKey
        }

        var output = Data(count: encrypted.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0
        let status = encrypted.withUnsafeBytes { encryptedBytes in
            key.withUnsafeBytes { keyBytes in
                output.withUnsafeMutableBytes { outputBytes in
                    CCCrypt(
                        CCOperation(kCCDecrypt),
                        CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress,
                        key.count,
                        nil,
                        encryptedBytes.baseAddress,
                        encrypted.count,
                        outputBytes.baseAddress,
                        outputCapacity,
                        &outputLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw DecodeError.invalidKey }
        output.removeSubrange(outputLength..<output.count)
        return output
    }

    private func buildKeyBox(key: [UInt8]) -> [UInt8] {
        guard !key.isEmpty else { return [] }
        var box = (0...255).map { UInt8($0) }
        var lastByte: UInt8 = 0
        var keyOffset = 0

        for index in 0..<box.count {
            let swap = box[index]
            let destination = swap &+ lastByte &+ key[keyOffset]
            box[index] = box[Int(destination)]
            box[Int(destination)] = swap
            lastByte = destination
            keyOffset = (keyOffset + 1) % key.count
        }
        return box
    }

    private func audioFileExtension(for data: Data) throws -> String {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0x49, 0x44, 0x33])
            || (bytes.count >= 2 && bytes[0] == 0xFF && bytes[1] & 0xE0 == 0xE0) {
            return "mp3"
        }
        if bytes == [0x66, 0x4C, 0x61, 0x43] {
            return "flac"
        }
        throw DecodeError.unsupportedAudio
    }
}

private extension Data {
    nonisolated mutating func mutateBytes(_ transform: (inout UInt8) -> Void) {
        withUnsafeMutableBytes { rawBuffer in
            guard let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
            for index in 0..<rawBuffer.count {
                transform(&bytes[index])
            }
        }
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
        do {
            return try NativeNCMDecoder().decode(
                sourceURL: sourceURL,
                outputDirectory: outputDirectory,
                fileManager: fileManager
            )
        } catch {
            throw KaraokeImportFailure.conversionFailed(error.localizedDescription)
        }
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
}
