@preconcurrency import AVFAudio
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import os
@preconcurrency import ScreenCaptureKit

enum ScreenRecordingCaptureError: Error, Sendable {
    case unsupportedSystem
    case permissionDenied
    case noDisplay
    case streamFailure(String)
}

@available(macOS 15.0, *)
final class ScreenRecordingCaptureSession: NSObject {
    nonisolated let audioSink: CaptureAudioSink

    private let outputURL: URL
    private let sampleQueue = DispatchQueue(
        label: "com.tokenplay.beatbox.screen-recording",
        qos: .userInitiated
    )
    private let failure = OSAllocatedUnfairLock<String?>(initialState: nil)
    private struct RecordingFinishState {
        var didFinish = false
        var errorDescription: String?
        var continuation: CheckedContinuation<Void, any Error>?
    }
    private let recordingFinish = OSAllocatedUnfairLock(
        initialState: RecordingFinishState()
    )
    private var stream: SCStream?
    private var recordingOutput: SCRecordingOutput?

    init(outputURL: URL, audioSink: CaptureAudioSink) {
        self.outputURL = outputURL
        self.audioSink = audioSink
        super.init()
    }

    func start() async throws {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw ScreenRecordingCaptureError.permissionDenied
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
        } catch {
            throw ScreenRecordingCaptureError.streamFailure(error.localizedDescription)
        }
        guard let display = content.displays.first else {
            throw ScreenRecordingCaptureError.noDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 5
        configuration.showsCursor = true
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = Int(ApplicationAudioCaptureSession.sampleRate)
        configuration.channelCount = Int(ApplicationAudioCaptureSession.channelCount)

        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = outputURL
        recordingConfiguration.outputFileType = .mov
        recordingConfiguration.videoCodecType = .h264
        let recordingOutput = SCRecordingOutput(
            configuration: recordingConfiguration,
            delegate: self
        )

        recordingFinish.withLock { state in
            state = RecordingFinishState()
        }

        do {
            try stream.addStreamOutput(
                self,
                type: .audio,
                sampleHandlerQueue: sampleQueue
            )
            try stream.addRecordingOutput(recordingOutput)
            self.stream = stream
            self.recordingOutput = recordingOutput
            try await stream.startCapture()
        } catch {
            self.stream = nil
            self.recordingOutput = nil
            throw ScreenRecordingCaptureError.streamFailure(error.localizedDescription)
        }
    }

    func stop() async throws -> (duration: TimeInterval, fileSize: Int64) {
        guard let stream, let recordingOutput else {
            throw ScreenRecordingCaptureError.streamFailure("录屏会话不存在")
        }
        do {
            try await stream.stopCapture()
        } catch {
            throw ScreenRecordingCaptureError.streamFailure(error.localizedDescription)
        }
        try await waitForRecordingOutputToFinish()
        self.stream = nil
        self.recordingOutput = nil
        if let failure = failure.withLock({ $0 }) {
            throw ScreenRecordingCaptureError.streamFailure(failure)
        }
        let asset = AVURLAsset(url: outputURL)
        let assetDuration: CMTime
        let videoTracks: [AVAssetTrack]
        let audioTracks: [AVAssetTrack]
        do {
            async let loadedDuration = asset.load(.duration)
            async let loadedVideoTracks = asset.loadTracks(withMediaType: .video)
            async let loadedAudioTracks = asset.loadTracks(withMediaType: .audio)
            (assetDuration, videoTracks, audioTracks) = try await (
                loadedDuration,
                loadedVideoTracks,
                loadedAudioTracks
            )
        } catch {
            throw ScreenRecordingCaptureError.streamFailure("无法验证录屏文件：\(error.localizedDescription)")
        }
        let duration = CMTimeGetSeconds(assetDuration)
        guard duration.isFinite, duration > 0.05 else {
            throw ScreenRecordingCaptureError.streamFailure("录屏文件没有有效时长")
        }
        guard !videoTracks.isEmpty else {
            throw ScreenRecordingCaptureError.streamFailure("录屏文件缺少视频轨")
        }
        guard !audioTracks.isEmpty else {
            throw ScreenRecordingCaptureError.streamFailure("录屏文件缺少系统音频轨")
        }
        let values = try? outputURL.resourceValues(forKeys: [.fileSizeKey])
        return (duration, Int64(values?.fileSize ?? Int(recordingOutput.recordedFileSize)))
    }

    func cancel() {
        guard let stream else { return }
        self.stream = nil
        recordingOutput = nil
        Task { try? await stream.stopCapture() }
    }

    nonisolated var errorDescription: String? {
        failure.withLock { $0 }
    }

    private func waitForRecordingOutputToFinish() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let result: Result<Void, any Error>? = recordingFinish.withLock { state in
                if state.didFinish {
                    if let errorDescription = state.errorDescription {
                        return .failure(ScreenRecordingCaptureError.streamFailure(errorDescription))
                    }
                    return .success(())
                }
                state.continuation = continuation
                return nil
            }
            result?.resume(continuation)
        }
    }

    nonisolated private func completeRecordingOutput(errorDescription: String? = nil) {
        let continuation: CheckedContinuation<Void, any Error>? = recordingFinish.withLock { state in
            guard !state.didFinish else { return nil }
            state.didFinish = true
            state.errorDescription = errorDescription
            defer { state.continuation = nil }
            return state.continuation
        }
        guard let continuation else { return }
        if let errorDescription {
            continuation.resume(
                throwing: ScreenRecordingCaptureError.streamFailure(errorDescription)
            )
        } else {
            continuation.resume()
        }
    }
}

private extension Result where Success == Void, Failure == any Error {
    func resume(_ continuation: CheckedContinuation<Void, any Error>) {
        switch self {
        case .success:
            continuation.resume()
        case let .failure(error):
            continuation.resume(throwing: error)
        }
    }
}

@available(macOS 15.0, *)
extension ScreenRecordingCaptureSession: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio,
              CMSampleBufferDataIsReady(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer)
        else { return }
        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return }
        let format = AVAudioFormat(cmAudioFormatDescription: formatDescription)
        guard format.commonFormat != .otherFormat,
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(frameCount)
              )
        else { return }
        buffer.frameLength = AVAudioFrameCount(frameCount)
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sampleBuffer,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        guard status == noErr else { return }
        audioSink.consume(buffer)
    }
}

@available(macOS 15.0, *)
extension ScreenRecordingCaptureSession: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        failure.withLock { value in
            value = value ?? error.localizedDescription
        }
    }
}

@available(macOS 15.0, *)
extension ScreenRecordingCaptureSession: SCRecordingOutputDelegate {
    nonisolated func recordingOutput(
        _ recordingOutput: SCRecordingOutput,
        didFailWithError error: any Error
    ) {
        failure.withLock { value in
            value = value ?? error.localizedDescription
        }
        completeRecordingOutput(errorDescription: error.localizedDescription)
    }

    nonisolated func recordingOutputDidFinishRecording(
        _ recordingOutput: SCRecordingOutput
    ) {
        completeRecordingOutput()
    }
}
