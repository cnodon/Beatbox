import AVFAudio
import Foundation
import Observation
import os

enum PlaybackState: Equatable {
    case idle
    case loading(UUID)
    case playing(UUID)
    case paused(UUID)
    case failed(UUID, String)

    var recordingID: UUID? {
        switch self {
        case let .loading(id), let .playing(id), let .paused(id), let .failed(id, _): id
        case .idle: nil
        }
    }
}

@Observable
final class PlaybackController {
    private(set) var state: PlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var rate: Float = 1 {
        didSet { player?.rate = rate }
    }
    var volume: Float = 1 {
        didSet { player?.volume = volume }
    }

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var progressTimer: Timer?
    @ObservationIgnored private let logger = Logger(
        subsystem: "com.tokenplay.beatbox",
        category: "playback"
    )

    func play(id: UUID, url: URL) {
        if case .paused(id) = state, let player {
            player.rate = rate
            player.play()
            state = .playing(id)
            startProgressTimer()
            return
        }

        stop()
        state = .loading(id)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.enableRate = true
            player.rate = rate
            player.volume = volume
            player.prepareToPlay()
            self.player = player
            duration = player.duration
            guard player.play() else {
                state = .failed(id, "无法开始播放")
                return
            }
            state = .playing(id)
            startProgressTimer()
        } catch {
            logger.error("Unable to play recording: \(error.localizedDescription, privacy: .private)")
            state = .failed(id, error.localizedDescription)
        }
    }

    func toggle(id: UUID, url: URL) {
        switch state {
        case .playing(id): pause()
        case .paused(id): play(id: id, url: url)
        default: play(id: id, url: url)
        }
    }

    func pause() {
        guard case let .playing(id) = state, let player else { return }
        player.pause()
        state = .paused(id)
        stopProgressTimer()
    }

    func stop() {
        player?.stop()
        player = nil
        stopProgressTimer()
        currentTime = 0
        duration = 0
        state = .idle
    }

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(time, 0), player.duration)
        player.currentTime = clamped
        currentTime = clamped
    }

    func skip(by interval: TimeInterval) {
        seek(to: currentTime + interval)
    }

    private func startProgressTimer() {
        stopProgressTimer()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateProgress()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    private func updateProgress() {
        guard let player, let id = state.recordingID else { return }
        currentTime = player.currentTime
        duration = player.duration
        if !player.isPlaying, currentTime >= max(0, duration - 0.05) {
            currentTime = 0
            player.currentTime = 0
            state = .paused(id)
            stopProgressTimer()
        }
    }
}
