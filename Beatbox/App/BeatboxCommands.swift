import SwiftUI

struct BeatboxCommands: Commands {
    let appModel: AppModel
    let softwareUpdates: SoftwareUpdateController

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            CheckForUpdatesButton(softwareUpdates: softwareUpdates)
        }

        CommandGroup(replacing: .newItem) {
            Button("开始新录音") {
                Task { await appModel.startRecording() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!appModel.canStartRecording)

            Divider()

            Button("导入 KTV 歌曲…") {
                appModel.chooseAndImportKaraokeSong()
            }
            .keyboardShortcut("i", modifiers: [.command])
            .disabled(appModel.karaokeImportState.isWorking)
        }

        CommandMenu("录音") {
            Button(capturePauseTitle) {
                if appModel.karaokeSessionState.isActive {
                    appModel.toggleKaraokePause()
                } else {
                    appModel.toggleCapturePause()
                }
            }
            .disabled(!canPauseOrResume)

            Button("停止录音") {
                Task {
                    if appModel.karaokeSessionState.isActive {
                        _ = await appModel.stopKaraokeSession()
                    } else {
                        _ = await appModel.stopRecording()
                    }
                }
            }
            .keyboardShortcut(".", modifiers: [.command])
            .disabled(!appModel.capture.state.canStop)
        }

        CommandGroup(after: .saveItem) {
            Button("导出录音为…") {
                if let recording = appModel.selectedRecording {
                    appModel.export(recording)
                }
            }
            .keyboardShortcut("e", modifiers: [.command])
            .disabled(
                appModel.selectedRecording == nil
                    || appModel.capture.state.isCapturing
                    || appModel.isExporting
            )
        }
    }

    private var canPauseOrResume: Bool {
        if appModel.karaokeSessionState.isActive {
            switch appModel.karaokeSessionState {
            case .recording, .paused: return true
            default: return false
            }
        }
        guard appModel.selectedRecordingMode == .audio else { return false }
        return switch appModel.capture.state {
        case .recording, .paused: true
        default: false
        }
    }

    private var capturePauseTitle: String {
        if case .paused = appModel.karaokeSessionState { return "继续跟唱" }
        if appModel.karaokeSessionState.isActive { return "暂停跟唱" }
        return if case .paused = appModel.capture.state { "继续录音" } else { "暂停录音" }
    }
}
