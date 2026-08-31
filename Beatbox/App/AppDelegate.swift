import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appModel: AppModel?

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard let appModel, appModel.capture.state.isCapturing else { return nil }

        let menu = NSMenu(title: "Beatbox")
        let showTitle = appModel.karaokeSessionState.isActive ? "显示 KTV 窗口" : "显示录音窗口"
        menu.addItem(withTitle: showTitle, action: #selector(showRecordingWindow), keyEquivalent: "")

        if appModel.selectedRecordingMode == .audio || appModel.karaokeSessionState.isActive {
            let pauseTitle = if case .paused = appModel.capture.state { "继续" } else { "暂停" }
            menu.addItem(withTitle: pauseTitle, action: #selector(togglePause), keyEquivalent: "")
        }
        let stopItem = menu.addItem(
            withTitle: appModel.capture.state.canStop ? "停止" : "正在保存…",
            action: #selector(stopRecording),
            keyEquivalent: ""
        )
        stopItem.isEnabled = appModel.capture.state.canStop
        for item in menu.items {
            item.target = self
        }
        return menu
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appModel, appModel.capture.state.isCapturing else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "停止录音并退出 Beatbox？"
        alert.informativeText = "Beatbox 会先完成文件保存。录音保存成功前应用不会退出。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "停止并退出")
        alert.addButton(withTitle: "取消")

        guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
        Task {
            let didSave = if appModel.karaokeSessionState.isActive {
                await appModel.stopKaraokeSession()
            } else {
                await appModel.stopRecording()
            }
            sender.reply(toApplicationShouldTerminate: didSave)
        }
        return .terminateLater
    }

    @objc private func showRecordingWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
    }

    @objc private func togglePause() {
        guard let appModel else { return }
        if appModel.karaokeSessionState.isActive {
            appModel.toggleKaraokePause()
        } else {
            appModel.toggleCapturePause()
        }
    }

    @objc private func stopRecording() {
        guard let appModel else { return }
        Task {
            if appModel.karaokeSessionState.isActive {
                _ = await appModel.stopKaraokeSession()
            } else {
                _ = await appModel.stopRecording()
            }
        }
    }
}
