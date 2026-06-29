# Art3m1s

Flutter + Rust 的 Artemis visual novel runtime 前端。Flutter 负责窗口、UI、输入、文件 I/O、音视频播放和存档沙箱；Rust `art3m1s-core` 负责脚本执行、图层合成、文本渲染和离屏 RGBA 帧输出。

## 仓库关系

| 路径                                                 | 职责 |
|----------------------------------------------------|------|
| `https://github.com/Alphaly2K/art3m1s`             | Flutter 宿主 app |
| `https://github.com/Alphaly2K/art3m1s-core`        | Rust runtime + C FFI dylib |
| `https://github.com/Alphaly2K/art3m1s-interpreter` | ASB/AST/IET 解释器、Lua bridge、tag/event 层 |

## 运行时架构

```text
PlayerScreen
  ├─ 读取 game source
  │   ├─ PFS: FileProvider.openPfs()
  │   └─ directory: FileProvider.openDirectory()
  ├─ 解析 system.ini 初始舞台尺寸
  ├─ 设置 saveDir: appSupport/art3m1s/saves/<gameId>
  ├─ CoreBridge.createRuntime()
  ├─ CoreBridge.loadProject()
  └─ 60fps frame loop
      ├─ feed mouse/key input
      ├─ art3m1s_runtime_advance_and_render()
      ├─ RGBA → ui.Image
      └─ RawImage 显示

CoreBridge
  ├─ 加载 libart3m1s_core.dylib
  ├─ 注册 log callback
  ├─ 注册 media command callback
  ├─ 注册 FileProvider reader/writer/delete callbacks
  ├─ 转发输入和每帧 render
  └─ 通知 core: video/sound finished

FileProvider
  ├─ PFS / split PFS / patch PFS 读取
  ├─ 解包目录读取
  └─ app support 存档读写删除

MediaBridge
  ├─ BGM / SE / Voice: audioplayers
  ├─ fullscreen video: media_kit
  ├─ layer video: 当前不渲染，保留 TODO
  └─ 播放完成后回调 core
```

## 数据流

### 画面

```text
Rust CoreRuntime::advance_and_render(delta_ms)
  → GL offscreen FBO
  → RGBA bytes
  → Dart Uint8List
  → ui.decodeImageFromPixels()
  → RawImage
```

Core 不创建窗口。Flutter 是唯一窗口 owner。

### 输入

Flutter `Listener` 把指针事件转为舞台坐标，交给 core：

- hover/move：`art3m1s_runtime_feed_mouse`
- mouse button：`art3m1s_runtime_feed_mouse_button`
- keyboard：`art3m1s_runtime_feed_key`
- scroll：映射为 runtime 支持的输入事件

视频 overlay 存在时会吸收鼠标事件，防止点击穿透到底层游戏导致剧情推进。可跳过全屏视频通过 opaque `GestureDetector` 吸收点击并调用 `MediaBridge.skipVideo()`。

### 文件与存档

Core 不直接读写物理文件。所有文件操作都走 FFI callback：

```text
core logical path
  → FileProvider._saveFile / PFS lookup / directory lookup
  → host filesystem
```

存档统一放在：

```text
<Application Support>/art3m1s/saves/<gameId>/<SAVEPATH>/
```

这样 PFS 游戏和目录游戏都使用 app sandbox，避免 iOS/macOS 沙箱写入限制，也避免修改原游戏目录。

### 媒体

Core 发出 JSON media command：

- `audio_bgm_play`
- `audio_se_play`
- `audio_voice_play`
- `audio_set_volume`
- `audio_stop_all`
- `video_play`
- `video_stop_all`

Flutter `MediaBridge` 负责实际播放。全屏 video 完成后调用 `art3m1s_runtime_notify_video_finished`，sound 完成后调用 `art3m1s_runtime_notify_sound_finished`。

目前 layer video 不以 Flutter overlay 实现。`MediaBridge` 会记录 TODO 并直接通知完成，避免无限遮挡或阻塞。

## 关键文件

| 文件 | 说明 |
|------|------|
| `lib/screens/player_screen.dart` | 游戏主屏幕、帧循环、输入、视频 overlay |
| `lib/services/core_bridge.dart` | Rust dylib FFI 入口、runtime lifecycle、回调注册 |
| `lib/services/file_provider.dart` | PFS/目录/存档统一读取与写删 callback |
| `lib/services/media_bridge.dart` | 音频、全屏视频、媒体完成通知 |
| `lib/services/pfs_bridge.dart` | PFS native bridge |
| `lib/services/logger.dart` | Flutter/Rust 日志落盘 |

## 构建

### 1. 构建 Rust core

```bash
cd /Users/alphaly/RustroverProjects/art3m1s-core
cargo test
cargo build --release

cp target/release/libart3m1s_core.dylib /Users/alphaly/IdeaProjects/Art3m1s/libart3m1s_core.dylib
codesign --force --sign - /Users/alphaly/IdeaProjects/Art3m1s/libart3m1s_core.dylib
```

如修改了 `/Users/alphaly/RustroverProjects/asb-interpreter`，确保 `art3m1s-core` 当前依赖指向正确版本，再重建 core dylib。

### 2. 准备其他 native dylib

项目根通常还需要：

- `libpfs_upk.dylib`
- `libEGL.dylib`
- `libGLESv2.dylib`

macOS 下可能需要签名：

```bash
codesign --force --sign - libpfs_upk.dylib
codesign --force --sign - libEGL.dylib
codesign --force --sign - libGLESv2.dylib
```

### 3. 运行 Flutter

```bash
flutter run -d macos
# macOS
flutter run -d linux
# Linux
flutter run -d android
# Android
```

## 验证

```bash
flutter analyze
```

涉及 native/core 改动时还应运行：

```bash
# in core repo
cargo test
```

## 调试

- Rust 日志通过 `CoreBridge` 注册的 log callback 进入 Flutter logger。
- 最近一次日志通常在 `~/Documents/art3m1s_*.log`。
- 存档目录日志会显示为 `[CoreBridge] 存档目录已设置: ...`。
- Core 事件可搜索 `[runtime] Event::SaveGame`、`[runtime] Event::LoadGame`、`VideoPlay`、`LayerCreate`。

## 当前限制

- Layer video 未实现 Flutter overlay 渲染。
- 音频由 Dart 插件播放，core 只维护逻辑状态和完成 handler。
- 每帧 RGBA 回读路径简单可靠，但不是最终性能形态。
- 大文件导入不要走会整文件读入内存的 picker 流程；资源读取应优先走路径/PFS/目录。
