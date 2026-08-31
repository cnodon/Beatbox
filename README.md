# Beatbox

Beatbox 是一款纯 Swift、macOS 专属的本地录音工具。它把麦克风、指定 App 音频、主显示器录屏与系统音频，以及轻量 KTV 跟唱放进同一套原生 Mac 界面。

Beatbox 的目标不是取代 DAW，而是可靠地完成一条短路径：

**选择来源 → 开始录制 → 停止并保存 → 立即回放 → 管理或导出。**

> 当前版本仍处于 MVP 阶段。短时录屏闭环已经过签名真机验证；麦克风、指定 App、KTV 以及长时间录制仍需要更多真机与异常场景验证。请先阅读 [已知限制](#已知限制)。

## 系统要求

- macOS 14.2 或更高版本。
- Xcode 26.6 或兼容的更新版本，用于从源码构建。
- 录屏与系统音频功能需要 macOS 15 或更高版本。
- 指定 App 音频、录屏与系统音频需要“屏幕与系统音频录制”权限。
- 麦克风录音与 KTV 跟唱需要麦克风权限。

Beatbox 使用 Swift 6 和 SwiftUI；音频录制基于 AVFAudio，App/系统音频与录屏基于 ScreenCaptureKit，资料库元数据使用 SwiftData。

## 功能

| 能力 | 当前实现 |
| --- | --- |
| 麦克风录音 | 支持系统默认输入，以及 Core Audio 可发现的内建、USB、蓝牙、聚合和虚拟输入；录制为 M4A（AAC） |
| 指定 App 音频 | 从正在运行的 App 中选择目标，仅保存该 App 的音频为 M4A（AAC） |
| 录屏与音频 | 录制主显示器、鼠标指针和系统音频，保存为 MOV（H.264 + AAC） |
| 录制反馈 | 首个有效音频缓冲区到达后才显示“正在录制”；提供计时、滚动波形、平均/峰值电平、静音和削波提示 |
| 文件安全 | 持续写入本机文件、停止时等待封装、启动时扫描可恢复的未完成文件，并在空间不足或写入失败时提供下一步操作 |
| 资料库 | 搜索、回放、重命名、最近删除、恢复、Finder 定位；支持 `⌘A` 全选、`⌘/Shift` 多选和批量删除；停止后自动选中新文件 |
| 导出 | AAC、WAV、ALAC、AIFF、CAF、FLAC；录屏可导出 MOV，资料库原件不会因导出被移动 |
| KTV | 导入标准音频或 NCM，可匹配同名 LRC；试听、定位、逐行歌词、实验性中置人声消除、可调耳机人声监听，并在播放歌曲时单独录制麦克风人声 |
| macOS 交互 | 原生菜单、快捷键、Dock 录制状态、窗口关闭后继续录制，以及键盘和 VoiceOver 基础支持 |
| 软件更新 | 主窗口工具栏、菜单和设置中提供“检查更新…”，通过 Sparkle 2.9.6 验证并安装 GitHub Release |

## 开始使用

### 麦克风录音

1. 在工具栏选择麦克风。
2. 点击“开始录音”，并在首次使用时允许麦克风访问。
3. 等待界面从“正在准备”切换为“正在录音”。这表示 Beatbox 已收到并写入首个有效缓冲区。
4. 根据需要暂停或继续，再点击“停止并保存”。
5. 新录音会自动进入资料库并被选中，可立即回放、重命名或导出。

### 录制指定 App 的声音

1. 先启动目标 App，并让它保持运行。
2. 在 Beatbox 的音源菜单中刷新并选择该 App。
3. 首次录制时允许“屏幕与系统音频录制”权限；若 macOS 要求，请重新打开 Beatbox。
4. 开始录制并让目标 App 播放声音。停止后，M4A 文件会进入普通录音资料库。

Beatbox 会排除自己的输出，避免应用内回放被再次捕获。目标 App 退出或不再可用时，Beatbox 会停止继续接收并尽量保留已经录到的内容。

### 录屏与系统音频

1. 将模式切换为“录屏与音频”。
2. 允许“屏幕与系统音频录制”权限。
3. 开始录制主显示器与系统声音。
4. 停止后，Beatbox 会等待 MOV 完成封装，并验证文件包含有效的视频轨和音频轨，再将它加入资料库。

录屏目前只支持主显示器，并且不支持暂停。

### KTV 跟唱

标准音频可以直接导入。Beatbox 内置本地 NCM 解码，不需要 Homebrew 或外部命令行工具。

1. 在侧栏打开“KTV · 歌曲”，按 `⌘I` 导入 NCM、MP3、FLAC、M4A、WAV、AIFF、CAF 或 AAC。
2. 如果音频旁存在同名 `.lrc`，Beatbox 会一并导入歌词。
3. 需要伴奏时，可先打开“消除原唱”。Beatbox 会在本机生成衍生伴奏缓存，原歌曲不会被修改。
4. 已经佩戴耳机时，可打开“耳机监听”并调节麦克风监听音量；不要在使用扬声器时开启，否则可能产生回声或啸叫。
5. 点击“录制我的演唱”。Beatbox 会先等待麦克风收到有效音频，再开始歌曲播放和歌词进度。
6. 使用 `Space` 暂停/继续，使用 `⌘.` 停止并保存。演唱的人声文件会进入普通录音资料库。

NCM 转换只在用户明确选择文件后发生，采用流式处理并输出 MP3 或 FLAC，原 NCM 不会被删除。“消除原唱”采用立体声左右声道的中置抵消，适合主唱位于声场中央的歌曲；单声道、偏离中央、带较多混响或已经特殊混音的人声可能残留，同时中央的贝斯、鼓和其他乐器也会被削弱。它不是 AI 分轨。外放歌曲时，麦克风可能再次收进扬声器声音，建议使用耳机。请只处理自己有权使用的音频。

## 常用快捷键

| 操作 | 快捷键 |
| --- | --- |
| 开始新录音 | `⇧⌘R` |
| 暂停或继续 | `Space` |
| 停止并保存 | `⌘.` |
| 导入 KTV 歌曲 | `⌘I` |
| 导出选中录音 | `⌘E` |
| 设置 | `⌘,` |

焦点位于文本输入、弹出菜单或模态控件时，`Space` 保持 macOS 的标准行为。

## 权限与隐私

Beatbox 只在使用相应功能时请求权限：

- 麦克风：麦克风录音和 KTV 人声录制。
- 屏幕与系统音频录制：指定 App 音频以及录屏与系统音频。
- 用户选择的文件：导入歌曲和将录音导出到用户选择的位置。

录音、录屏、KTV 歌曲、歌词和资料库元数据默认保存在这台 Mac。Beatbox 当前没有账号、云同步、音频上传、远程转写或音频内容遥测。自动更新只会获取版本清单和发行包，不会上传录音内容。

权限被拒绝或稍后被撤销时，Beatbox 不会显示假录制状态；界面会提供相应的系统设置入口。你也可以在“系统设置 → 隐私与安全性”中随时调整权限。

## 从源码构建

克隆仓库后，在项目根目录执行：

```sh
open Beatbox.xcodeproj
```

在 Xcode 中选择 `Beatbox` scheme 和“My Mac”。如果需要测试真实麦克风或系统音频权限，请在 Signing & Capabilities 中选择自己的开发团队，并保持 bundle identifier 稳定。macOS 的隐私授权与应用签名及 bundle identity 关联，频繁更改它们可能触发重新授权。

无需签名的编译和测试命令：

```sh
xcodebuild \
  -project Beatbox.xcodeproj \
  -scheme Beatbox \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild \
  -project Beatbox.xcodeproj \
  -scheme Beatbox \
  -configuration Debug \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

unsigned build 适合编译与自动化测试，不代表麦克风、ScreenCaptureKit、沙盒或更新流程已经验证。涉及权限和真实音频的变更必须另外使用签名构建在 Mac 上检查。

## 签名与公证

本地开发运行通常使用 Apple Development 证书。向仓库外分发时，应使用 Developer ID Application、Hardened Runtime、安全时间戳和 Apple 公证。

发行脚本要求明确提供版本、构建号、Developer ID 身份和 App Store Connect API key。示例：

```sh
DEVELOPMENT_TEAM="YOUR_TEAM_ID" \
SIGNING_IDENTITY="Developer ID Application: YOUR NAME (YOUR_TEAM_ID)" \
RELEASE_VERSION="0.1.6" \
RELEASE_BUILD_NUMBER="7" \
NOTARY_KEY_PATH="/secure/path/AuthKey_ABC123.p8" \
NOTARY_KEY_ID="ABC123" \
NOTARY_ISSUER_ID="00000000-0000-0000-0000-000000000000" \
./scripts/build-signed-release.sh
```

默认输出目录为 `.build/release`，主要产物包括：

- `Beatbox.app`
- `Beatbox-<version>.zip`
- `Beatbox-<version>.zip.sha256`
- `Beatbox-<version>.dSYM.zip`（存在 dSYM 时）
- `Beatbox.xcarchive`

脚本会校验 bundle 版本和代码签名，提交 Apple 公证，装订并验证票据，再重新打包分发文件。它不会从仓库读取凭据；Developer ID 私钥由钥匙串提供，公证 key 只通过 `NOTARY_KEY_PATH` 引用。

没有 App Store Connect 公证凭据时，只能显式生成本地测试产物：

```sh
SKIP_NOTARIZATION=1 \
DEVELOPMENT_TEAM="YOUR_TEAM_ID" \
SIGNING_IDENTITY="Developer ID Application: YOUR NAME (YOUR_TEAM_ID)" \
RELEASE_VERSION="0.1.6" \
RELEASE_BUILD_NUMBER="7" \
./scripts/build-signed-release.sh
```

`SKIP_NOTARIZATION=1` 生成的压缩包没有 Apple 公证和 stapled ticket，只用于维护者本机验证，**不得上传到 GitHub Releases 或作为自动更新发布**。GitHub Release workflow 不提供跳过公证模式；缺少任一公证凭据时会在发布前失败。

## GitHub Releases 与自动升级

正式发行包通过 GitHub Releases 提供。Beatbox 当前锁定 Sparkle 2.9.6；主窗口工具栏、菜单与设置窗口都提供“检查更新…”。更新配置位于 [`Configuration/Beatbox-Info.plist`](Configuration/Beatbox-Info.plist)，公开 feed 为：

```text
https://github.com/cnodon/Beatbox/releases/latest/download/appcast.xml
```

工作方式如下：

1. Sparkle updater 随应用启动，按用户的更新偏好或手动“检查更新…”读取公开 appcast。
2. appcast 提供版本号、发行说明、下载地址和 Sparkle 签名。
3. Beatbox 下载对应的 GitHub Release 压缩包，并用内置的 EdDSA 公钥验证 Sparkle 签名。
4. macOS 仍会验证 Developer ID 签名与 Apple 公证；验证不通过时不会安装更新。
5. 用户确认后，Sparkle 替换应用并重新打开 Beatbox。资料库和录音文件位于 Application Support，不会随 `.app` 替换而删除。

本地 Debug/unsigned 构建不应被视为自动升级验证。私钥、App Store Connect 凭据、Developer ID 证书和 Sparkle 私钥不得提交到仓库或上传为普通构建产物。仓库中的 `SUPublicEDKey` 是用于验证签名的公钥，可以公开。

发行辅助脚本：

- [`scripts/fetch-sparkle-tools.sh`](scripts/fetch-sparkle-tools.sh) 下载与 `Package.resolved` 一致的官方 Sparkle 工具，并校验固定 SHA-256。
- [`scripts/generate-appcast.sh`](scripts/generate-appcast.sh) 从已签名、公证并装订票据的 zip 生成 appcast，再独立核对 EdDSA 签名。
- [`.github/workflows/release.yml`](.github/workflows/release.yml) 在 GitHub Actions 中完成签名、公证、appcast 和 Release 发布。

在本机运行下载脚本需要 `jq`；GitHub 的 `macos-26` runner 已提供 workflow 所需工具。

## 发布维护

### 配置 GitHub release environment

workflow 运行在名为 `release` 的 GitHub Environment 中，需要配置以下 Secrets：

| Secret | 用途 |
| --- | --- |
| `APPLE_DEVELOPMENT_TEAM` | Apple Developer Team ID |
| `DEVELOPER_ID_APPLICATION` | 完整的 Developer ID Application 身份名称 |
| `MACOS_CERTIFICATE_P12_BASE64` | Developer ID 证书与私钥的 P12，经 base64 编码 |
| `MACOS_CERTIFICATE_PASSWORD` | P12 密码 |
| `APPLE_NOTARY_KEY_P8_BASE64` | App Store Connect API `.p8` key，经 base64 编码 |
| `APPLE_NOTARY_KEY_ID` | App Store Connect API key ID |
| `APPLE_NOTARY_ISSUER_ID` | App Store Connect issuer ID |
| `SPARKLE_EDDSA_PRIVATE_KEY` | 与应用内公钥匹配的 Sparkle 私钥 |

建议为 `release` Environment 配置必要的 reviewer 和分支/tag 保护。`SPARKLE_EDDSA_PRIVATE_KEY` 必须与 [`Configuration/Beatbox-Info.plist`](Configuration/Beatbox-Info.plist) 中的公钥配对。现有维护者可使用官方 Sparkle `generate_keys --account com.tokenplay.beatbox -x <安全路径>` 导出并加密备份私钥；不要为普通版本重新生成密钥。私钥丢失后，已安装版本无法信任使用新密钥签名的更新。

### 验证候选版本

1. 运行 unsigned build/test，并用签名构建完成麦克风、指定 App、录屏和 KTV 的真机冒烟测试。
2. 创建并推送精确格式为 `vMAJOR.MINOR.PATCH` 的 tag，例如 `v0.1.6`。workflow 会验证 tag 指向当前 checkout，版本号来自 tag，构建号使用该提交的 commit count。
3. 在 Actions 中手动运行 “Release Beatbox”，输入已经存在的 tag，并保持 `publish=false`。
4. workflow 会签名、公证、装订票据、生成 appcast，并上传保留 7 天的 `Beatbox-<version>-release-candidate` artifact。它包含发行 zip、SHA-256、dSYM（若存在）和 `appcast.xml`，但不会创建 GitHub Release。
5. 下载候选产物，完成 Gatekeeper、QuickTime、四条录制路径和从旧版升级的验证。

### 发布正式版本

有两种发布触发方式：

- 推送 `v*` tag：验证通过后自动创建 GitHub Release。
- 手动运行 workflow：指定现有的 `vMAJOR.MINOR.PATCH` tag，并设置 `publish=true`。

正式 Release 包含 `Beatbox-<version>.zip`、对应 `.sha256`、`appcast.xml`，以及存在时的 dSYM zip。发行说明由 GitHub 根据 [`.github/release.yml`](.github/release.yml) 的分类生成。workflow 拒绝覆盖同一 tag 已存在的 Release；需要修复时应发布新版本，而不是替换旧二进制。

如果发行包已在受信任的 Mac 上完成 Developer ID 签名与 Apple 公证，可先把包上传到草稿 Release，再手动运行 “Publish Appcast for Existing Release”。该 workflow 只读取加密的 `SPARKLE_EDDSA_PRIVATE_KEY`，为现有 zip 生成并验证 appcast；成功后附加 `appcast.xml` 并将草稿公开。它不会重新签名、替换或跳过公证发行包。

发布后必须从上一个公开版本实际执行一次“检查更新 → 下载 → 验证 → 安装 → 重启”，并确认原有录音资料库仍可读取。

## 已知限制

- 项目仍在 MVP 阶段，不建议用于无法重录的关键场景。
- 麦克风、指定 App 和 KTV 的最终签名真机闭环，以及每类音源 60 分钟稳定性测试，尚未全部完成。
- 录屏需要 macOS 15+，目前只录主显示器与系统音频，不支持选择窗口、选择显示器、麦克风混录或暂停。
- 指定 App 必须正在运行并出现在可发现列表中；目标退出、设备断开、睡眠/锁屏和权限撤销仍需更多真机覆盖。
- 长时间录音、低磁盘空间、写入失败、强制终止和恢复路径仍处于发布前验证阶段。
- KTV 属于实验功能。NCM 已使用本机真实文件验证内置解码，但不同历史版本的 NCM 容器仍需要更多兼容性测试。
- KTV 耳机监听依赖当前 Mac 的输入/输出设备组合，蓝牙耳机启用麦克风时可能切换到低带宽通话模式并增加延迟。
- Beatbox 只提供实验性的立体声中置人声抵消，不提供 AI 分轨、自动混音、音准评分、转写或多轨编辑。
- 音频导出暂不支持 MP3；源文件为 MP3 时仅限 KTV 导入。
- 当前配置的 feed 依赖公开可访问的 `github.com/cnodon/Beatbox` Release。仓库或 Release 为私有、尚未创建 Release，或 `appcast.xml` 未作为 latest Release asset 发布时，检查更新会失败；Sparkle 不会匿名读取私有 Release。
- Sparkle 与 GitHub 发布链路已接入并有配置测试，但首个公开版本发布前仍必须完成一次真实的旧版本到新版本端到端升级。

## 参与贡献

欢迎提交问题和 Pull Request。开始前请阅读 [AGENTS.md](AGENTS.md)，它记录了产品不变量、Swift 6 并发约束、实时音频规则、文件生命周期和测试要求。

提交变更时：

1. 保持改动聚焦，并说明它影响的用户闭环和异常路径。
2. 不要在没有讨论的情况下加入第三方运行时依赖、云服务、音频遥测或破坏性文件行为。
3. 运行相关单元/集成测试；涉及录音、权限、文件或回放时，附上签名真机验证环境和结果。
4. UI 变更需检查键盘操作、VoiceOver、提高对比度和“减少动态效果”。
5. 不要在日志、截图、测试夹具或 Issue 中暴露录音内容、文件名、App 名称、歌词、证书或密钥。

如果报告捕获失败，请包含 macOS 与 Beatbox 版本、音源类别、授权状态、可复现步骤和不含私人内容的错误信息。不要上传敏感录音，除非你明确拥有并愿意公开它。

## License

Beatbox 以 [MIT License](LICENSE) 开源。Copyright © 2026 Dong Yuan.
