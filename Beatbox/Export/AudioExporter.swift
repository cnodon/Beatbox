import AVFAudio
import AudioToolbox
import Foundation

nonisolated enum AudioExportError: LocalizedError, Sendable {
    case sourceMissing
    case sourceAndDestinationMatch
    case cannotCreateAudioBuffer
    case conversionFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceMissing:
            "找不到原始录音文件。"
        case .sourceAndDestinationMatch:
            "导出位置不能覆盖 Beatbox 资料库中的原始文件。"
        case .cannotCreateAudioBuffer:
            "无法创建音频转换缓冲区。"
        case let .conversionFailed(message):
            "音频转换失败：\(message)"
        }
    }
}

nonisolated struct AudioExporter: Sendable {
    @concurrent
    func export(
        sourceURL: URL,
        destinationURL: URL,
        format: AudioExportFormat
    ) async throws -> URL {
        try Task.checkCancellation()

        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw AudioExportError.sourceMissing
        }
        guard sourceURL.standardizedFileURL != destinationURL.standardizedFileURL else {
            throw AudioExportError.sourceAndDestinationMatch
        }

        let temporaryURL = fileManager.temporaryDirectory
            .appending(path: "Beatbox-Export-\(UUID().uuidString)")
            .appendingPathExtension(format.fileExtension)

        do {
            if format == .m4aAAC,
               sourceURL.pathExtension.localizedCaseInsensitiveCompare("m4a") == .orderedSame {
                try fileManager.copyItem(at: sourceURL, to: temporaryURL)
            } else {
                try transcode(sourceURL: sourceURL, destinationURL: temporaryURL, format: format)
            }

            try Task.checkCancellation()
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
            return destinationURL
        } catch is CancellationError {
            try? fileManager.removeItem(at: temporaryURL)
            throw CancellationError()
        } catch let error as AudioExportError {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw AudioExportError.conversionFailed(error.localizedDescription)
        }
    }

    private func transcode(
        sourceURL: URL,
        destinationURL: URL,
        format: AudioExportFormat
    ) throws {
        let inputFile = try AVAudioFile(forReading: sourceURL)
        let processingFormat = inputFile.processingFormat
        let outputFile = try AVAudioFile(
            forWriting: destinationURL,
            settings: outputSettings(
                for: format,
                sampleRate: processingFormat.sampleRate,
                channelCount: processingFormat.channelCount
            ),
            commonFormat: processingFormat.commonFormat,
            interleaved: processingFormat.isInterleaved
        )

        let frameCapacity: AVAudioFrameCount = 32_768
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: processingFormat,
            frameCapacity: frameCapacity
        ) else {
            throw AudioExportError.cannotCreateAudioBuffer
        }

        while inputFile.framePosition < inputFile.length {
            try Task.checkCancellation()
            let remainingFrames = inputFile.length - inputFile.framePosition
            let framesToRead = AVAudioFrameCount(min(Int64(frameCapacity), remainingFrames))
            try inputFile.read(into: buffer, frameCount: framesToRead)
            guard buffer.frameLength > 0 else { break }
            try outputFile.write(from: buffer)
        }
    }

    private func outputSettings(
        for format: AudioExportFormat,
        sampleRate: Double,
        channelCount: AVAudioChannelCount
    ) -> [String: Any] {
        switch format {
        case .m4aAAC:
            [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitRateKey: channelCount > 1 ? 192_000 : 128_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
        case .m4aALAC:
            [
                AVFormatIDKey: kAudioFormatAppleLossless,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitDepthHintKey: 24,
            ]
        case .wavPCM, .aiffPCM:
            linearPCMSettings(
                sampleRate: sampleRate,
                channelCount: channelCount,
                bitDepth: 16,
                isBigEndian: format == .aiffPCM
            )
        case .cafPCM:
            linearPCMSettings(
                sampleRate: sampleRate,
                channelCount: channelCount,
                bitDepth: 24,
                isBigEndian: false
            )
        case .flac:
            [
                AVFormatIDKey: kAudioFormatFLAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVEncoderBitDepthHintKey: 24,
            ]
        }
    }

    private func linearPCMSettings(
        sampleRate: Double,
        channelCount: AVAudioChannelCount,
        bitDepth: Int,
        isBigEndian: Bool
    ) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channelCount,
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: isBigEndian,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }
}
