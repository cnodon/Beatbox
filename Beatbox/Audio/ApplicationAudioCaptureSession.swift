@preconcurrency import AVFAudio
import CoreGraphics
import CoreMedia
import Foundation
import os
@preconcurrency import ScreenCaptureKit

enum ApplicationAudioCaptureError: Error, Sendable {
    case permissionDenied
    case noDisplay
    case applicationNotRunning
    case invalidFormat
    case streamFailure(String)
}

/// Captures only the audio emitted by the selected application. ScreenCaptureKit
/// requires a video stream even for audio-only work, so the session attaches a
/// discarded 2×2 frame at 1 fps and writes only `.audio` sample buffers.
final class ApplicationAudioCaptureSession: NSObject {
    static let sampleRate = 48_000.0
    static let channelCount: AVAudioChannelCount = 2

    let bundleIdentifiers: Set<String>
    nonisolated let audioSink: CaptureAudioSink

    private let sampleQueue = DispatchQueue(
        label: "com.tokenplay.beatbox.application-audio",
        qos: .userInitiated
    )
    private let acceptsSamples = OSAllocatedUnfairLock(initialState: false)
    private let failure = OSAllocatedUnfairLock<String?>(initialState: nil)
    private var stream: SCStream?

    init(bundleIdentifiers: [String], audioSink: CaptureAudioSink) {
        self.bundleIdentifiers = Set(bundleIdentifiers)
        self.audioSink = audioSink
        super.init()
    }

    func start() async throws {
        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            throw ApplicationAudioCaptureError.permissionDenied
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
        } catch {
            throw ApplicationAudioCaptureError.streamFailure(error.localizedDescription)
        }

        guard let display = content.displays.first else {
            throw ApplicationAudioCaptureError.noDisplay
        }
        let applications = content.applications.filter {
            bundleIdentifiers.contains($0.bundleIdentifier)
        }
        guard !applications.isEmpty else {
            throw ApplicationAudioCaptureError.applicationNotRunning
        }

        let filter = SCContentFilter(
            display: display,
            including: applications,
            exceptingWindows: []
        )
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = Int(Self.sampleRate)
        configuration.channelCount = Int(Self.channelCount)

        let stream = SCStream(
            filter: filter,
            configuration: configuration,
            delegate: self
        )
        do {
            try stream.addStreamOutput(
                self,
                type: .screen,
                sampleHandlerQueue: sampleQueue
            )
            try stream.addStreamOutput(
                self,
                type: .audio,
                sampleHandlerQueue: sampleQueue
            )
            self.stream = stream
            acceptsSamples.withLock { $0 = true }
            try await stream.startCapture()
        } catch {
            acceptsSamples.withLock { $0 = false }
            self.stream = nil
            throw ApplicationAudioCaptureError.streamFailure(error.localizedDescription)
        }
    }

    func pause() {
        acceptsSamples.withLock { $0 = false }
    }

    func resume() {
        acceptsSamples.withLock { $0 = true }
    }

    func stop() async {
        acceptsSamples.withLock { $0 = false }
        guard let stream else { return }
        self.stream = nil
        try? await stream.stopCapture()
    }

    func cancel() {
        acceptsSamples.withLock { $0 = false }
        guard let stream else { return }
        self.stream = nil
        Task { try? await stream.stopCapture() }
    }

    nonisolated var errorDescription: String? {
        failure.withLock { $0 }
    }
}

extension ApplicationAudioCaptureSession: SCStreamOutput {
    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard type == .audio,
              acceptsSamples.withLock({ $0 }),
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

extension ApplicationAudioCaptureSession: SCStreamDelegate {
    nonisolated func stream(_ stream: SCStream, didStopWithError error: any Error) {
        acceptsSamples.withLock { $0 = false }
        failure.withLock { value in
            value = value ?? error.localizedDescription
        }
    }
}
