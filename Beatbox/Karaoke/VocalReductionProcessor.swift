import AVFAudio
import AudioToolbox
import Foundation

nonisolated enum VocalReductionError: LocalizedError {
    case stereoRequired
    case emptyAudio
    case processingFailed(String)

    var errorDescription: String? {
        switch self {
        case .stereoRequired:
            "这首歌曲不是立体声，无法使用中置人声消除。"
        case .emptyAudio:
            "没有从歌曲中读取到可处理的音频。"
        case let .processingFailed(stage):
            "人声消除在“\(stage)”阶段失败。"
        }
    }
}

nonisolated struct VocalReductionProcessor: Sendable {
    @concurrent
    func createAccompaniment(sourceURL: URL, destinationURL: URL) async throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        do {
            let input: AVAudioFile
            do {
                input = try AVAudioFile(forReading: sourceURL)
            } catch {
                throw VocalReductionError.processingFailed("读取歌曲")
            }
            let inputFormat = input.processingFormat
            guard inputFormat.channelCount >= 2 else {
                throw VocalReductionError.stereoRequired
            }
            guard let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputFormat.sampleRate,
                channels: 2,
                interleaved: false
            ) else {
                throw VocalReductionError.emptyAudio
            }

            let output: AVAudioFile
            do {
                output = try AVAudioFile(
                    forWriting: destinationURL,
                    settings: [
                        AVFormatIDKey: kAudioFormatLinearPCM,
                        AVSampleRateKey: inputFormat.sampleRate,
                        AVNumberOfChannelsKey: 2,
                        AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false,
                        AVLinearPCMIsBigEndianKey: false,
                        AVLinearPCMIsNonInterleaved: false,
                    ],
                    commonFormat: .pcmFormatFloat32,
                    interleaved: false
                )
            } catch {
                throw VocalReductionError.processingFailed("创建伴奏文件")
            }
            let capacity: AVAudioFrameCount = 8_192
            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: inputFormat,
                frameCapacity: capacity
            ), let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: capacity
            ) else {
                throw VocalReductionError.emptyAudio
            }

            var processedFrames: AVAudioFramePosition = 0
            while input.framePosition < input.length {
                try Task.checkCancellation()
                let remainingFrames = input.length - input.framePosition
                let framesToRead = AVAudioFrameCount(
                    min(AVAudioFramePosition(capacity), remainingFrames)
                )
                do {
                    try input.read(into: inputBuffer, frameCount: framesToRead)
                } catch {
                    throw VocalReductionError.processingFailed("解码歌曲")
                }
                guard inputBuffer.frameLength > 0 else { break }
                guard let inputChannels = inputBuffer.floatChannelData,
                      let outputChannels = outputBuffer.floatChannelData else {
                    throw VocalReductionError.emptyAudio
                }

                let frameCount = Int(inputBuffer.frameLength)
                outputBuffer.frameLength = inputBuffer.frameLength
                for frame in 0 ..< frameCount {
                    let sideSignal = (inputChannels[0][frame] - inputChannels[1][frame]) * 0.5
                    outputChannels[0][frame] = sideSignal
                    outputChannels[1][frame] = sideSignal
                }
                do {
                    try output.write(from: outputBuffer)
                } catch {
                    throw VocalReductionError.processingFailed("写入伴奏")
                }
                processedFrames += AVAudioFramePosition(inputBuffer.frameLength)
            }

            guard processedFrames > 0 else { throw VocalReductionError.emptyAudio }
            return destinationURL
        } catch {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.removeItem(at: destinationURL)
            }
            throw error
        }
    }
}
