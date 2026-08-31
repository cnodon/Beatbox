# AGENTS.md

本文件约束所有在 Beatbox 仓库中工作的自动化开发代理。它适用于仓库根目录及其全部子目录；更深层目录若存在自己的 `AGENTS.md`，可以补充更具体的规则，但不得削弱这里的产品安全与隐私要求。

## Mission

Beatbox 是一款纯 Swift、macOS 专属的录音与录屏软件。首要目标不是成为 DAW 或视频编辑器，而是让用户可靠地完成：

**授权 → 选音源 → 录音 → 保存 → 回放 → 管理 → 导出。**

任何变更都应优先维护这条闭环。新功能不能以降低录音可靠性、状态清晰度或本地隐私为代价。

## Current phase

- 当前仓库处于 MVP 实现阶段，README 是产品范围、交互和进度的主要事实源。
- 工程为 `Beatbox.xcodeproj`，共享 scheme 为 `Beatbox`，bundle identifier 为 `com.tokenplay.beatbox`；本地无签名编译和测试命令记录在 README。
- 创建或调整工程结构、构建约束和已实现范围后，同步更新 README 与本文。

## Product invariants

以下规则不可破坏：

1. 同一时刻最多一个录制会话。
2. 没有成功写入首个有效音频缓冲区时，不得向用户显示“正在录音”。
3. 录制状态必须在应用内明确可见；P0 在窗口隐藏时固定使用 Dock badge 与 Dock 菜单表达，不使用尚属 P1 的菜单栏迷你录音器。
4. 关闭窗口、按 `Esc`、切换列表选择或打开设置不能隐式停止录音。
5. 停止录音必须先完成文件封装和元数据持久化，再允许开始下一次录音。
6. 任何可恢复失败都优先保留部分文件，不自动销毁已经录下的内容。
7. 删除进入最近删除或提供等价撤销；裁剪默认非破坏性。
8. 音频默认保存在本机；未经明确产品决策不得加入自动上传、分析或遥测音频内容。
9. 权限按需请求，并清楚解释用途。拒绝权限不能让应用崩溃或进入假状态。
10. 录制与播放的主要状态不能只靠红/绿颜色表达。
11. 开始新录音前停止当前回放，防止应用自身声音被系统/App 音源再次捕获。
12. “停止并退出”必须等待 `finalizing` 完成；文件已验证可播放或已明确保存为可恢复文件前，应用不得终止。

## MVP scope

实现功能时按照以下顺序保护范围：

### P0

- 麦克风、指定 App、全系统三类音源。
- “录音”和“录屏与音频”两种互斥录制模式；后者保存主显示器与系统音频。
- 权限、音源发现与录制前电平检查。
- 开始、暂停、继续、停止、计时、波形和峰值提示。
- 持续写盘、异常恢复、磁盘与设备错误处理。
- 录音资料库默认使用 M4A（AAC），录屏使用 MOV（H.264 + AAC）；音频导出支持 M4A/AAC、WAV/PCM、M4A/ALAC、AIFF/PCM、CAF/PCM 与 FLAC，视频导出保存 MOV 副本。
- 录音库、搜索、重命名、最近删除。
- 应用内回放、拖放导出、保存副本、Finder 定位和系统分享。
- macOS 菜单、键盘与无障碍支持。

### P1 or later

- 多源/多轨、裁剪、转写、标签、菜单栏迷你控制、语音增强。
- 不要在 P0 稳定前实现插件链、直播、账号、云同步、协作或专业多轨编辑器。

### User-approved experiment: KTV

- KTV 作为独立本地歌曲库存在，不改变录音资料库的文件安全与单会话约束。
- 可导入标准音频，或调用用户通过 Homebrew 安装的 MIT-licensed `ncmdump` 转换用户明确选择的 NCM；永远保留原 NCM，不传递 `--remove`。
- 同名 LRC 用于逐行歌词；跟唱会话播放歌曲并通过现有 capture coordinator 持续保存麦克风人声。
- 首版不做人声分离、评分、自动混音或联网获取歌词；界面必须明确标注原唱音频与干声录制边界。

## Platform and dependencies

- Language: Swift 6 language mode.
- Platform: macOS only; deployment target macOS 14.2 or later.
- UI: SwiftUI first; use AppKit from Swift when macOS behavior is otherwise inaccessible or materially worse.
- Audio: AVFAudio/AVAudioEngine/AVAudioFile for device input and file processing; ScreenCaptureKit for selected-App audio and display/system-audio recording; Core Audio Process Tap remains an experimental fallback/diagnostic path.
- Video: SCRecordingOutput on macOS 15+ writes MOV with H.264 video and AAC system audio; keep the app deployable to macOS 14.2 and make unavailable modes explicit.
- Persistence: SwiftData for metadata and explicit file management for audio payloads.
- Tests: Swift Testing for unit/integration tests; XCTest only for UI automation or APIs that require it.
- Logging: `Logger` from OSLog, never `print` in shipping paths.
- Updates: Sparkle 2 is an explicitly approved Swift Package dependency used only for signed in-app updates from public GitHub Releases. Keep its version pinned by `Package.resolved`, require EdDSA verification, Developer ID signing and Apple notarization, and never expose the update private key in the repository or logs.
- Do not add third-party runtime dependencies without explicit approval and a documented reason. In particular, do not add a library solely to ship MP3 in the MVP.

Calling Apple C or Objective-C frameworks through their Swift imports is allowed. Do not introduce Objective-C/C/C++ source files unless a verified platform limitation makes them necessary and the change is approved.

## Architecture rules

### Model states explicitly

Use value types and mutually exclusive enums. The capture lifecycle should remain conceptually equivalent to:

```swift
enum CaptureState: Equatable {
    case idle
    case requestingPermission
    case preparing(AudioSource.ID)
    case recording(Recording.ID)
    case paused(Recording.ID)
    case finalizing(Recording.ID)
    case completed(Recording.ID)
    case failed(CaptureFailure)
}
```

Associated data may evolve, but do not replace this with independent `isRecording`, `isPaused`, `isSaving`, and `hasError` booleans that permit impossible combinations.

Playback has a separate state source:

```swift
enum PlaybackState: Equatable {
    case idle
    case loading(Recording.ID)
    case playing(Recording.ID)
    case paused(Recording.ID)
    case failed(Recording.ID, PlaybackFailure)
}
```

Starting capture must return playback to `idle`. Deleting or replacing the current playback item must first release its player resources.

Recovery is recording metadata, not a live capture state:

```swift
enum RecordingIntegrity: Equatable {
    case complete
    case recovered
}
```

A playable partial file enters the library with `.recovered`. An unplayable file remains a failed recovery artifact with explicit retry/reveal/remove actions; do not add `.recovered` to `CaptureState`.

### Keep layers separated

- Views render state and emit user intent; they do not own Core Audio objects or write files.
- A capture coordinator enforces transitions and owns one end-to-end recording operation.
- Audio source discovery is separate from capture and remains testable without a live recording.
- Persistence commits metadata only when its matching file state is known.
- Playback never mutates the source recording file.
- Export works from a stable file URL and does not move the library’s canonical file.

### Concurrency and real-time audio

- Enable Approachable Concurrency and MainActor default isolation for the app target.
- Keep UI and observable feature state on MainActor.
- Do not assume `async` automatically moves work off MainActor.
- Use structured concurrency and store/cancel any unstructured task whose lifetime follows a recording or view.
- Never block an audio callback with `await`, locks of unbounded duration, semaphores, UI work, network calls, logging storms, format discovery or filesystem coordination.
- Avoid allocations and conversions in the real-time path when they can be prepared before capture.
- Do not use `Task.detached`, `@unchecked Sendable` or `nonisolated(unsafe)` to silence compiler errors. Document and prove the synchronization strategy if an exception is unavoidable.
- Check cancellation before expensive waveform generation, conversion or transcription.

### File lifecycle

- Create each capture with a stable recording ID and a temporary/in-progress file marker.
- Write incrementally rather than retaining an entire recording in memory.
- Finalization closes the writer, validates that the file is readable, and then marks metadata complete.
- On launch, scan in-progress records and offer recovery when a playable file exists.
- Sanitize suggested filenames but preserve the user’s displayed title separately from the physical filename when useful.
- Treat audio files, titles, source App names and transcripts as private in logs.

## UI and interaction rules

Use `README.md` as the interface specification and apply the design engineering principles from [emilkowalski/skills](https://github.com/emilkowalski/skills).

### Native macOS behavior

- Prefer NavigationSplitView, standard toolbar placement, menus, commands, focus rings, SF Symbols, system colors and system save/open panels.
- Support keyboard-only operation and VoiceOver from the first implementation, not as a final polish pass.
- Respect system accent color, appearance, Dynamic Type where applicable, increased contrast and Reduce Motion.
- Use standard destructive-action conventions and UndoManager for recoverable deletion.
- Never replace a discoverable menu command with an icon-only custom gesture.
- Recent Deleted exposes Restore, Delete Immediately, and Empty Recently Deleted. The last two require explicit confirmation; an empty collection exposes no destructive action.

### Motion

- Before adding motion, state its purpose: feedback, state explanation, spatial continuity or avoiding a jarring change.
- Do not animate keyboard-triggered high-frequency actions.
- Common UI transitions stay below 300 ms; enter with ease-out, move with ease-in-out, and make exit faster than enter.
- Button press feedback may use a subtle scale around `0.97` for `100–160 ms`; disable transform feedback under Reduce Motion.
- Popovers should originate visually from their trigger. Centered modals remain centered.
- Do not animate from scale zero and do not add bounce to professional recording controls.
- Real-time waveform motion represents data; it must never delay capture or compete with the timer and state label.
- Animate only properties SwiftUI/Core Animation can render efficiently, primarily transform and opacity.
- Use the documented strong ease-out curve `(0.23, 1, 0.32, 1)` for short entering UI and strong ease-in-out `(0.77, 0, 0.175, 1)` for the few state morphs that genuinely need motion.

### Recording interaction

- The current audio source remains visible before and during recording.
- Provide preflight metering before the record command.
- Disable or explain unsupported source changes during an active recording; never switch silently.
- Use text, symbol/shape and color together for recording, paused, finalizing and failure states.
- Stopping and pausing must be visually distinct actions.
- `Esc` dismisses transient UI; it never stops a recording.
- While finalizing, show progress/state and prevent duplicate capture commands.
- Errors must include a next action such as Retry, Choose Another Source, Open System Settings, Free Space or Reveal Recovered File.
- P0 uses Dock badge text (`REC`, `PAUSED`, `SAVING`) plus a non-color shape, and a Dock menu with Show Recording Window, Pause/Resume, and Stop. Clicking the Dock icon restores and focuses the active capture view.
- When the user chooses Stop and Quit, keep the app alive through finalization. On failure, remain open and offer Retry, Reveal Recovery File, and Cancel Quit.
- If focus is inside text input, a popover, or a modal control, `Space` retains the system behavior. Otherwise capture state takes precedence over playback state.
- If a disconnected microphone is replaced mid-recording, require explicit confirmation, exclude the paused gap from duration, and persist both the source change and gap metadata.

## Accessibility

Every shipped capture control must have:

- A meaningful accessibility label and value, including current source and capture state.
- A keyboard command or standard focus path.
- A hit target appropriate for macOS controls.
- A non-color state indicator.
- Stable announcements: do not announce every waveform update; announce important transitions such as recording started, paused, resumed, saved and failed.

Timer announcements must not speak every second. Expose the current value for on-demand VoiceOver reading.

## Testing expectations

Tests are part of the feature. At minimum, changes affecting capture should cover:

### Unit tests

- Legal and illegal `CaptureState` transitions.
- Duration accounting across pause/resume.
- Filename generation and collision handling.
- Metadata/file consistency and recovery decisions.
- Permission-state mapping and user-facing recovery actions.

### Integration tests

- Start, write, pause, resume, stop and reopen a fixture file.
- Source disappearance and writer failure preserve recoverable output.
- Relaunch recovery finds in-progress recordings.
- Export creates a playable copy without altering the library original.

### Manual/device verification

- Built-in microphone plus at least one external or virtual input if available.
- One supported application source and all-system audio.
- A 60-minute recording for each source category before MVP release.
- Close/minimize window, switch Spaces, sleep/lock behavior, target App exit, device unplug and low disk space.
- Permission allow, deny, later enable, and later revoke flows.
- VoiceOver, keyboard-only navigation, increased contrast and Reduce Motion.

Do not claim a source path is reliable based only on mocked buffers. Record and play back real audio on a Mac.

## Definition of done

A change is done only when:

1. It preserves or completes the MVP user journey.
2. The app builds without new warnings under strict concurrency checking.
3. Relevant automated tests pass.
4. Real audio behavior is manually verified when the change touches capture, playback, permissions or files.
5. Failure and recovery states are implemented, not left as console output.
6. Keyboard, VoiceOver and Reduce Motion behavior are checked for UI changes.
7. README and AGENTS remain consistent with actual behavior and commands.

## Change discipline

- Keep changes narrowly scoped and preserve unrelated user work.
- Prefer concrete types; introduce protocols only at a real substitution/testing boundary.
- Prefer structs/enums and `let`; use classes for identity, shared resource lifetime or framework requirements.
- Do not optimize or add concurrency without profiling or a real-time requirement.
- Use `apply_patch` for source edits made by agents.
- Use OSLog with privacy-safe fields for diagnostics.
- Record important architectural decisions in the repository when they affect file compatibility, minimum OS, permissions or capture semantics.
- If product behavior would become destructive, cloud-connected, or materially broader than the README scope, stop and request user direction.
