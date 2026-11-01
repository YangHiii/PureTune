# PureTune（纯音）

PureTune 是一个完全离线的 iOS 本地音乐播放器。应用不包含账号、登录、广告、推荐、会员、在线音乐服务或任何业务网络请求。导入的音频只保存在应用自己的沙盒内。

## 第一版功能

- 通过 iOS 系统文件选择器多选导入音频，文件会复制到应用持久化目录。
- 使用 `AVURLAsset` 读取标题、歌手、专辑和时长，缺失字段会使用安全默认值。
- 本地曲库保存在 JSON 索引中，重启应用后仍会恢复，并自动忽略已丢失的文件。
- 支持歌曲列表、按歌曲/歌手/专辑搜索、左滑删除。
- 支持播放、暂停、上一首、下一首、进度显示和拖动跳转。
- 配置 `AVAudioSession.playback` 与 `UIBackgroundModes = audio`，支持后台播放。
- 使用 `MPNowPlayingInfoCenter` 显示锁屏歌曲信息。
- 使用 `MPRemoteCommandCenter` 处理锁屏/耳机的播放、暂停、上一首、下一首和进度跳转。
- 处理音频中断和外接设备断开，避免意外继续播放。
- 导入、解码、删除和曲库持久化错误会以可见提示反馈。

## 项目结构

```text
PureTune/
├── PureTune/
│   ├── App/
│   │   └── PureTuneApp.swift
│   ├── Models/
│   │   └── Song.swift
│   ├── Services/
│   │   ├── MusicLibrary.swift
│   │   └── AudioPlayer.swift
│   ├── Views/
│   │   ├── ContentView.swift
│   │   ├── MiniPlayerView.swift
│   │   ├── NowPlayingView.swift
│   │   └── SongRow.swift
│   └── Info.plist
├── project.yml
├── .github/workflows/build-unsigned-ipa.yml
└── README.md
```

- `App`：应用入口与依赖注入。
- `Models`：可持久化的歌曲模型和时间格式化。
- `Services`：文件导入、元数据、曲库索引、播放队列、后台会话和媒体控制。
- `Views`：音乐库、搜索、导入、迷你播放器与全屏播放页。
- `project.yml`：XcodeGen 工程定义，避免手工维护 `.pbxproj`。

## 数据存储

应用首次启动后会创建：

```text
<App 沙盒>/Documents/PureTune/Music/
<App 沙盒>/Documents/PureTune/library.json
```

`Music/` 保存导入后的音频副本，`library.json` 保存歌曲元数据。卸载应用会删除这些数据。

## 环境要求

- iOS 16.0 或更高版本
- Xcode 15 或更高版本
- XcodeGen
- 无需 Apple Developer 付费账号即可完成未签名编译

## 本地生成与编译

```bash
brew install xcodegen
xcodegen generate --spec project.yml
open PureTune.xcodeproj
```

在 Xcode 中选择自己的签名方式后可安装到设备。仅验证未签名构建时，可执行：

```bash
xcodebuild \
  -project PureTune.xcodeproj \
  -scheme PureTune \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

## GitHub Actions 构建未签名 IPA

工作流文件：`.github/workflows/build-unsigned-ipa.yml`。

1. 将整个目录推送到 GitHub 仓库的 `main` 分支。
2. 工作流会在 `push`、`pull_request` 或手动触发时运行。
3. macOS Runner 安装 XcodeGen、生成工程并执行 Release 构建。
4. 构建后会校验 Bundle ID、显示名称、后台音频声明，以及产物确实未签名。
5. 上传 Artifact：`PureTune-unsigned-IPA`，其中包含 `PureTune-unsigned.ipa`。

该 IPA 是未签名产物，必须由使用者自行签名后才能安装。本仓库不保存证书、描述文件或签名密钥。

## Bundle Identifier

默认 Bundle ID 为 `com.puretune.app`，显示名称为 `PureTune`。`Info.plist` 中的标识、版本、后台音频模式等由 `project.yml` 的 `info.properties` 生成；如需修改，请以 `project.yml` 为准，再重新执行 `xcodegen generate`。

## 音频格式说明

导入器接受系统识别的音频类型，实际可用格式取决于 iOS 的 AVFoundation 解码器。MP3、AAC/M4A、WAV、AIFF 是优先验证格式；FLAC 等格式需在目标系统版本上实测。

## 隐私边界

- 不请求网络权限，不包含网络请求代码。
- 不申请账号、通讯录、相册、位置或麦克风权限。
- 不上传、分析或收集用户音乐库和个人信息。
- 所有音频副本和索引都留在应用沙盒内。
