import AVFAudio
import AVFoundation
import Foundation
import Observation
import os

@Observable
final class CaptureController {
    private(set) var state: CaptureState = .idle {
        didSet { onStateChange?(state) }
    }
    private(set) var elapsedTime: TimeInterval = 0
    private(set) var averagePower: Float = -160
    private(set) var peakPower: Float = -160
    private(set) var liveWaveformSamples: [Float] = []
    private(set) var hasDetectedSilence = false
    private(set) var hasDetectedClipping = false

    @ObservationIgnored private var engine: AVAudioEngine?
    @ObservationIgnored private var audioSink: CaptureAudioSink?
    @ObservationIgnored private var applicationAudioSession: ApplicationAudioCaptureSession?
    @ObservationIgnored private var screenRecordingSession: AnyObject?
    @ObservationIgnored private var inputTapInstalled = false
    @ObservationIgnored private var meterTimer: Timer?
    @ObservationIgnored private var inProgressURL: URL?
    @ObservationIgnored private var finalURL: URL?
    @ObservationIgnored private var activeID: UUID?
    @ObservationIgnored private var activeMode: RecordingMode = .audio
    @ObservationIgnored private var silenceStartedAt: Date?
    @ObservationIgnored private var clippingDetectedAt: Date?
    @ObservationIgnored private var smoothedWaveformLevel: Float = 0.025
    @ObservationIgnored private var waveformAccumulator = WaveformAccumulator()
    @ObservationIgnored private var finalizationTask: Task<CaptureResult?, any Error>?
    @ObservationIgnored private let logger = Logger(
        subsystem: "com.tokenplay.beatbox",
        category: "capture"
    )

    @ObservationIgnored var onStateChange: ((CaptureState) -> Void)?

    var permissionState: MicrophonePermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined: .notDetermined
        case .authorized: .authorized
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .restricted
        }
    }

    var hasRecoverableArtifact: Bool {
        guard let inProgressURL,
              FileManager.default.fileExists(atPath: inProgressURL.path),
              let values = try? inProgressURL.resourceValues(forKeys: [.fileSizeKey])
        else { return false }
        return (values.fileSize ?? 0) > 0
    }

    var signalHealth: InputSignalHealth {
        switch state {
        case .preparing, .requestingPermission:
            .preparing
        case .paused:
            .paused
        default:
            if hasDetectedClipping {
                .clipping
            } else if hasDetectedSilence {
                .silent
            } else if averagePower < -42 {
                .low
            } else {
                .healthy
            }
        }
    }

    func requestPermission() async -> Bool {
        switch permissionState {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            state = .requestingPermission
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            if !granted {
                state = .failed(.permissionDenied)
            } else {
                state = .idle
            }
            return granted
        }
    }

    func start(
        id: UUID,
        inProgressURL: URL,
        finalURL: URL,
        input: CaptureInput,
        mode: RecordingMode = .audio
    ) async throws {
        guard state.canStart else { return }
        resetMeasurements()
        let minimumCapacity: Int64 = mode == .screenAndAudio
            ? 2 * 1_024 * 1_024 * 1_024
            : 256 * 1_024 * 1_024
        if let capacity = try? inProgressURL.deletingLastPathComponent().resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey]
        ).volumeAvailableCapacityForImportantUsage,
           capacity < minimumCapacity {
            state = .failed(.insufficientStorage)
            throw CaptureFailure.insufficientStorage
        }
        if mode == .audio, case .microphone = input {
            guard await requestPermission() else {
                state = .failed(.permissionDenied)
                throw CaptureFailure.permissionDenied
            }
        }

        state = .preparing(id)

        do {
            if mode == .screenAndAudio {
                try await startScreenRecording(
                    id: id,
                    inProgressURL: inProgressURL,
                    finalURL: finalURL
                )
                return
            }

            let inputFormat: AVAudioFormat
            var preparedEngine: AVAudioEngine?
            switch input {
            case let .microphone(deviceID):
                let engine = AVAudioEngine()
                let inputNode = engine.inputNode
                if let deviceID {
                    try inputNode.auAudioUnit.setDeviceID(deviceID)
                }
                inputFormat = inputNode.outputFormat(forBus: 0)
                preparedEngine = engine
            case let .application(processObjectIDs, bundleIdentifiers):
                guard !processObjectIDs.isEmpty,
                      !bundleIdentifiers.isEmpty,
                      let processFormat = AVAudioFormat(
                          standardFormatWithSampleRate: ApplicationAudioCaptureSession.sampleRate,
                          channels: ApplicationAudioCaptureSession.channelCount
                      )
                else {
                    throw CaptureFailure.sourceUnavailable
                }
                inputFormat = processFormat
            }

            guard inputFormat.channelCount > 0, inputFormat.sampleRate > 0 else {
                state = .failed(.sourceUnavailable)
                throw CaptureFailure.sourceUnavailable
            }

            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: inputFormat.sampleRate,
                AVNumberOfChannelsKey: inputFormat.channelCount,
                AVEncoderBitRateKey: inputFormat.channelCount > 1 ? 192_000 : 128_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let audioFile = try AVAudioFile(
                forWriting: inProgressURL,
                settings: settings,
                commonFormat: inputFormat.commonFormat,
                interleaved: inputFormat.isInterleaved
            )
            let audioSink = CaptureAudioSink(
                audioFile: audioFile,
                sampleRate: inputFormat.sampleRate
            )
            if let preparedEngine {
                preparedEngine.inputNode.installTap(
                    onBus: 0,
                    bufferSize: 1_024,
                    format: inputFormat,
                    block: CaptureAudioSink.tapHandler(for: audioSink)
                )
                inputTapInstalled = true
            }

            self.engine = preparedEngine
            self.audioSink = audioSink
            self.activeID = id
            activeMode = mode
            self.inProgressURL = inProgressURL
            self.finalURL = finalURL

            if let preparedEngine {
                preparedEngine.prepare()
                try preparedEngine.start()
            } else if case let .application(_, bundleIdentifiers) = input {
                let session = ApplicationAudioCaptureSession(
                    bundleIdentifiers: bundleIdentifiers,
                    audioSink: audioSink
                )
                applicationAudioSession = session
                try await session.start()
            }
            startMetering()
        } catch let failure as CaptureFailure {
            state = .failed(failure)
            clearSession()
            throw failure
        } catch let tapError as ProcessTapCaptureError {
            let failure: CaptureFailure = tapError.isPermissionDenied
                ? .systemAudioPermissionDenied
                : .unableToPrepare
            logger.error("Unable to prepare process tap: \(String(describing: tapError), privacy: .private)")
            state = .failed(failure)
            clearSession()
            throw failure
        } catch let captureError as ApplicationAudioCaptureError {
            let failure: CaptureFailure
            switch captureError {
            case .permissionDenied:
                failure = .systemAudioPermissionDenied
            case .applicationNotRunning:
                failure = .sourceUnavailable
            case .noDisplay, .invalidFormat, .streamFailure:
                failure = .unableToPrepare
            }
            logger.error("Unable to prepare application capture: \(String(describing: captureError), privacy: .private)")
            state = .failed(failure)
            clearSession()
            throw failure
        } catch let captureError as ScreenRecordingCaptureError {
            let failure: CaptureFailure = switch captureError {
            case .permissionDenied: .systemAudioPermissionDenied
            case .unsupportedSystem, .noDisplay, .streamFailure: .unableToPrepare
            }
            logger.error("Unable to prepare screen recording: \(String(describing: captureError), privacy: .private)")
            state = .failed(failure)
            clearSession()
            throw failure
        } catch {
            logger.error("Unable to prepare recorder: \(error.localizedDescription, privacy: .private)")
            state = .failed(.unableToPrepare)
            clearSession()
            throw CaptureFailure.unableToPrepare
        }
    }

    func waitUntilReady(timeout: Duration = .seconds(4)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            switch state {
            case .recording:
                return true
            case .preparing:
                try? await Task.sleep(for: .milliseconds(50))
            default:
                return false
            }
        }
        return false
    }

    func pause() {
        guard case let .recording(id) = state else { return }
        guard activeMode == .audio else { return }
        if let engine {
            engine.pause()
        } else {
            applicationAudioSession?.pause()
        }
        state = .paused(id)
        averagePower = -160
        peakPower = -160
        silenceStartedAt = nil
        hasDetectedSilence = false
        clippingDetectedAt = nil
        hasDetectedClipping = false
    }

    func resume() {
        guard case let .paused(id) = state else { return }
        do {
            if let engine {
                try engine.start()
            } else if let applicationAudioSession {
                applicationAudioSession.resume()
            } else {
                throw CaptureFailure.sourceUnavailable
            }
            state = .recording(id)
        } catch {
            logger.error("Unable to resume audio engine: \(error.localizedDescription, privacy: .private)")
            state = .failed(.unableToStart)
        }
    }

    func stop() async throws -> CaptureResult? {
        if let finalizationTask {
            return try await finalizationTask.value
        }
        guard state.canStop else { return nil }

        let task = Task { [weak self] in
            try await self?.finalizeCapture()
        }
        finalizationTask = task
        do {
            let result = try await task.value
            finalizationTask = nil
            return result
        } catch {
            finalizationTask = nil
            throw error
        }
    }

    private func finalizeCapture() async throws -> CaptureResult? {
        guard let id = activeID,
              let audioSink,
              let inProgressURL,
              let finalURL
        else { return nil }

        state = .finalizing(id)
        engine?.stop()
        await applicationAudioSession?.stop()
        if inputTapInstalled {
            engine?.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        stopMetering()
        let finalSnapshot = audioSink.finish()

        if let errorDescription = finalSnapshot.errorDescription {
            let failure = CaptureFailure.unableToFinalize(errorDescription)
            state = .failed(failure)
            clearSession(keepMeasurements: true)
            throw failure
        }

        var screenDuration: TimeInterval?
        var screenFileSize: Int64?
        if activeMode == .screenAndAudio {
            guard #available(macOS 15.0, *),
                  let screenRecordingSession = screenRecordingSession as? ScreenRecordingCaptureSession
            else {
                state = .failed(.unableToFinalize("当前系统不支持录屏输出"))
                clearSession()
                throw CaptureFailure.unableToFinalize("当前系统不支持录屏输出")
            }
            do {
                let screenResult = try await screenRecordingSession.stop()
                screenDuration = screenResult.duration
                screenFileSize = screenResult.fileSize
                self.screenRecordingSession = nil
            } catch {
                let failure = CaptureFailure.unableToFinalize(error.localizedDescription)
                state = .failed(failure)
                clearSession(keepMeasurements: true)
                throw failure
            }
        }

        guard activeMode == .screenAndAudio || finalSnapshot.processedFrames > 0 else {
            if FileManager.default.fileExists(atPath: inProgressURL.path) {
                try? FileManager.default.removeItem(at: inProgressURL)
            }
            state = .failed(.sourceUnavailable)
            clearSession()
            throw CaptureFailure.sourceUnavailable
        }

        do {
            if FileManager.default.fileExists(atPath: finalURL.path) {
                try FileManager.default.removeItem(at: finalURL)
            }
            try FileManager.default.moveItem(at: inProgressURL, to: finalURL)

            let duration: TimeInterval
            if let screenDuration {
                duration = screenDuration
            } else {
                let player = try AVAudioPlayer(contentsOf: finalURL)
                guard player.duration.isFinite, player.duration > 0.01 else {
                    throw CaptureFailure.unableToFinalize("录音文件没有有效时长")
                }
                duration = player.duration
            }
            let values = try finalURL.resourceValues(forKeys: [.fileSizeKey])
            let result = CaptureResult(
                id: id,
                fileURL: finalURL,
                duration: duration,
                fileSize: screenFileSize ?? Int64(values.fileSize ?? 0),
                waveformSamples: waveformAccumulator.snapshot
            )
            state = .completed(id)
            clearSession(keepMeasurements: true)
            return result
        } catch {
            if FileManager.default.fileExists(atPath: finalURL.path),
               !FileManager.default.fileExists(atPath: inProgressURL.path) {
                try? FileManager.default.moveItem(at: finalURL, to: inProgressURL)
            }
            logger.error("Unable to finalize recording: \(error.localizedDescription, privacy: .private)")
            state = .failed(.unableToFinalize(error.localizedDescription))
            clearSession(keepMeasurements: true)
            throw CaptureFailure.unableToFinalize(error.localizedDescription)
        }
    }

    func acknowledgeCompletion() {
        switch state {
        case .completed, .failed:
            state = .idle
        default:
            break
        }
    }

    private func startMetering() {
        stopMetering()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollMeters()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        meterTimer = timer
    }

    private func startScreenRecording(
        id: UUID,
        inProgressURL: URL,
        finalURL: URL
    ) async throws {
        guard #available(macOS 15.0, *) else {
            throw ScreenRecordingCaptureError.unsupportedSystem
        }
        let audioSink = CaptureAudioSink(
            sampleRate: ApplicationAudioCaptureSession.sampleRate
        )
        let session = ScreenRecordingCaptureSession(
            outputURL: inProgressURL,
            audioSink: audioSink
        )
        self.audioSink = audioSink
        activeID = id
        activeMode = .screenAndAudio
        self.inProgressURL = inProgressURL
        self.finalURL = finalURL
        screenRecordingSession = session
        try await session.start()
        startMetering()
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func pollMeters() {
        guard let audioSink, let id = activeID else { return }

        if let errorDescription = applicationAudioSession?.errorDescription {
            logger.error("Application audio stream stopped: \(errorDescription, privacy: .private)")
            state = .failed(.sourceUnavailable)
            clearSession(keepMeasurements: true)
            return
        }
        if #available(macOS 15.0, *),
           let errorDescription = (screenRecordingSession as? ScreenRecordingCaptureSession)?.errorDescription {
            logger.error("Screen recording stream stopped: \(errorDescription, privacy: .private)")
            state = .failed(.unableToFinalize(errorDescription))
            clearSession(keepMeasurements: true)
            return
        }

        let snapshot = audioSink.snapshot()
        if let errorDescription = snapshot.errorDescription {
            logger.error("Audio file writer failed: \(errorDescription, privacy: .private)")
            state = .failed(.unableToFinalize(errorDescription))
            clearSession(keepMeasurements: true)
            return
        }

        elapsedTime = snapshot.sampleRate > 0
            ? Double(snapshot.processedFrames) / snapshot.sampleRate
            : 0

        if case .preparing = state, snapshot.processedFrames > 0 {
            state = .recording(id)
        }

        guard case .recording = state else { return }
        averagePower = snapshot.averagePower
        peakPower = snapshot.peakPower

        let rawLevel = AudioMeterScale.waveformLevel(decibels: averagePower)
        let smoothing: Float = rawLevel > smoothedWaveformLevel ? 0.72 : 0.24
        smoothedWaveformLevel += (rawLevel - smoothedWaveformLevel) * smoothing
        liveWaveformSamples.append(smoothedWaveformLevel)
        waveformAccumulator.append(smoothedWaveformLevel)
        if liveWaveformSamples.count > 240 {
            liveWaveformSamples.removeFirst(60)
        }

        if averagePower < -60 {
            silenceStartedAt = silenceStartedAt ?? .now
            if let silenceStartedAt, Date.now.timeIntervalSince(silenceStartedAt) >= 3 {
                hasDetectedSilence = true
            }
        } else {
            silenceStartedAt = nil
            hasDetectedSilence = false
        }

        if peakPower >= -1 {
            clippingDetectedAt = .now
            hasDetectedClipping = true
        } else if let clippingDetectedAt,
                  Date.now.timeIntervalSince(clippingDetectedAt) > 1.25 {
            self.clippingDetectedAt = nil
            hasDetectedClipping = false
        }
    }

    private func resetMeasurements() {
        elapsedTime = 0
        averagePower = -160
        peakPower = -160
        liveWaveformSamples = []
        silenceStartedAt = nil
        clippingDetectedAt = nil
        hasDetectedSilence = false
        hasDetectedClipping = false
        smoothedWaveformLevel = 0.025
        waveformAccumulator.reset()
    }

    private func clearSession(keepMeasurements: Bool = false) {
        stopMetering()
        engine?.stop()
        if inputTapInstalled {
            engine?.inputNode.removeTap(onBus: 0)
            inputTapInstalled = false
        }
        _ = audioSink?.finish()
        engine = nil
        audioSink = nil
        applicationAudioSession?.cancel()
        applicationAudioSession = nil
        if #available(macOS 15.0, *) {
            (screenRecordingSession as? ScreenRecordingCaptureSession)?.cancel()
            screenRecordingSession = nil
        }
        activeID = nil
        inProgressURL = nil
        finalURL = nil
        activeMode = .audio
        silenceStartedAt = nil
        clippingDetectedAt = nil
        if !keepMeasurements {
            resetMeasurements()
        }
    }
}
