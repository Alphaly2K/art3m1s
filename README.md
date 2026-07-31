<p align="center">
  <img src="assets/branding/art3m1s-logo-v1.png" alt="Art3m1s icon" width="168">
</p>

# Art3m1s

Art3m1s 是使用 Flutter 编写的跨平台 Artemis 视觉小说运行时宿主。Flutter 负责资料库、
原生窗口、输入、文件沙箱、音视频解码和平台服务；Rust
[`art3m1s-core`](https://github.com/Alphaly2K/art3m1s-core) 负责脚本执行、游戏状态和
离屏图层合成。

当前应用版本为 **1.1.1-0.2.1c**，对应 `art3m1s-core 0.2.1` 兼容周期。

## 功能

- 从解包目录、单卷/分卷 PFS 和移动端应用目录导入游戏；同一目录中的多个 PFS
  会分别建立项目条目
- 启动时无界面读取游戏标题，并通过 VNDB 补全标题和封面
- 以稳定项目 ID 映射游戏目录、具体 PFS、存档、封面和设置，避免同名文件互相串档
- 按平台使用 macOS、Cupertino、Fluent、Yaru/Material 3 风格的原生化界面
- 以约 60 FPS 驱动 Rust runtime，转发鼠标、键盘、触摸、右键、悬停和拖动
- 播放 BGM、SE、Voice、全屏视频与参与 core 合成的图层视频
- 将游戏文件与存档隔离到应用可访问的位置，支持通过 iOS 文件 App 导入导出
- 提供渲染后端、启动 OS、脚本字符集、翻译和调试选项
- 支持本地翻译补丁以及 OpenAI、Anthropic、DeepL、Google、百度和有道在线翻译
- 提供会话日志、可拖动/缩放的等宽字体调试浮窗、日志导出和关于/许可证页面

## 架构

```text
平台界面
  macOS / Cupertino / Fluent / Material
        │
        ├─ LibraryActions
        │   ├─ 原生文件选择器 / 文件 App 可见目录
        │   ├─ 游戏标题探测
        │   └─ VNDB 元数据与封面查询
        │
        └─ PlayerScreen
            ├─ 输入与生命周期
            ├─ 60 FPS 运行时循环
            ├─ MediaBridge
            └─ RGBA 帧显示
                     │
                  CoreBridge
            ┌────────┼────────┐
            │        │        │
       FileProvider  UI      翻译
       PFS/目录回调与宿主服务
                     │ C FFI
                     ▼
                art3m1s-core
```

### CoreBridge

`lib/services/core_bridge.dart` 负责加载目标平台的 native library、持有 runtime handle，
并注册以下回调：

- 项目和存档文件的读取、写入、删除、状态查询与复制；
- 媒体命令以及音频/视频播放完成通知；
- 对话框、标题、浏览器/平台请求和窗口状态；
- 字体查找与文本注入；
- 同步帧渲染与图层视频纹理上传。

同一 runtime 的 core 调用会串行执行。关闭 runtime 时会先解除回调并停止媒体任务，
再销毁 native handle。

### FileProvider

`lib/services/file_provider.dart` 向 core 提供统一的逻辑文件命名空间：

- PFS、分卷 PFS 和补丁 PFS 资源；
- 已解包的游戏目录；
- 由应用管理的存档文件。

PFS 条目绑定到具体的基础 `.pfs` 文件，而不是只绑定父目录。资源路径会依据
`system.ini` 的 `CHARSET` 以 Shift_JIS 或 UTF-8 解码；大型加密资源支持分块读取。

core 不需要接触用户文件的物理路径。在 iOS 上，文件 App 可见的数据按以下结构保存：

```text
Documents/Art3m1s/
  Games/
  Saves/
```

原生 `UIDocumentPicker` 通过 security-scoped URL 复制用户选中的 PFS 分卷。导入时
会先扫描 table 中的 `gametitle`，找不到时再使用启用环境补丁的 headless runtime
探测标题。Android
使用 Storage Access Framework 将选定目录复制到沙箱，从而避免 Dart 无法直接访问
`content://`，也避免在 Dart 中把整个文件读入内存。

### MediaBridge

`lib/services/media_bridge.dart` 负责实际解码：

- BGM/SE/Voice 使用 `audioplayers`；
- 全屏视频与图层视频使用 `media_kit`/mpv；
- 全屏视频显示在游戏画面上方并吸收鼠标和触摸输入；
- 图层视频在 worker isolate 中解码，只保留最新 RGBA8 帧，再将其指针借给 core
  同步上传为 GL 纹理。

视频解码节奏与游戏帧循环相互独立，因此 24 FPS 视频不会把 runtime 一同限制在
24 FPS。

### 翻译

翻译功能需要在全局设置和项目设置中分别启用。支持以下翻译来源：

- JSON 字符串映射；
- 由 `source` 和 `translation` 字段组成的 JSON/JSONL 条目；
- 使用 Tab 分隔原文和译文的对照文件；
- OpenAI、Anthropic、DeepL、Google 翻译、百度翻译和有道翻译 API。

本地补丁的匹配结果优先于在线翻译。在线任务会去重、缓存并交给限制并发数的异步队列，
因此脚本执行和逐字动画不会被网络延迟阻塞。Ruby 注音会作为上下文提供给翻译服务，
只有正文会被替换。

旧版资料库和设置数据仍然兼容：缺少项目翻译字段时默认关闭翻译；第一版在线翻译设置
会迁移到 OpenAI 兼容服务配置。

## 平台界面

| 平台 | 界面 | 导入方式 |
|---|---|---|
| macOS | `macos_ui`、沉浸式原生标题栏和应用菜单 | 目录或 PFS 选择器 |
| iOS | Cupertino、原生文件与资料库管理器 | UIDocumentPicker 或 `Art3m1s/Games` |
| Windows | Fluent UI | 目录或 PFS 选择器 |
| Linux | Yaru/Material 界面 | 目录或 PFS 选择器 |
| Android | Material 3 | 原生 SAF 目录复制 |

设置和关于页面共用相同的数据与功能，但会使用符合目标平台习惯的控件进行渲染。
Fable 的本轮 macOS UI 更新还加入了原生应用菜单、更加清晰的明暗主题图标状态和紧凑
的游戏控制面板。

## 关键文件

| 路径 | 职责 |
|---|---|
| `lib/screens/player_screen.dart` | Runtime 生命周期、帧循环、输入和视频浮层 |
| `lib/services/core_bridge.dart` | Native C ABI 与回调注册 |
| `lib/services/file_provider.dart` | PFS/目录/存档逻辑文件系统 |
| `lib/services/game_importer.dart` | 移动端原生导入与沙箱复制 |
| `lib/services/media_bridge.dart` | 音频、全屏视频和图层视频解码 |
| `lib/services/text_translation_service.dart` | 补丁查找、翻译服务、队列与缓存 |
| `lib/services/vndb_service.dart` | 资料库标题和封面元数据 |
| `lib/widgets/debug_overlay_host.dart` | Runtime 监控和会话日志浮窗 |
| `lib/shell/` | 各平台应用界面 |
| `scripts/ios_build_rust.sh` | 将 Rust library 构建并打包为 iOS framework |

## 构建

### 前置要求

- Flutter 稳定版
- Rust 稳定版
- 对应目标平台的 SDK
- 为目标平台编译的 `art3m1s-core` native library
- 与 core 固定版本一致的 `pfs-upk-rust` native library
- 当前平台所需的 mpv/media_kit 运行时依赖

### macOS 开发

```bash
cd /path/to/art3m1s-core
git submodule update --init --recursive
cargo test
cargo build --release
cargo build --release --manifest-path crates/pfs-upk-rust/Cargo.toml

cp target/release/libart3m1s_core.dylib /path/to/Art3m1s/
cp crates/pfs-upk-rust/target/release/libpfs_upk.dylib /path/to/Art3m1s/
codesign --force --sign - /path/to/Art3m1s/libart3m1s_core.dylib
codesign --force --sign - /path/to/Art3m1s/libpfs_upk.dylib

cd /path/to/Art3m1s
flutter pub get
COMMIT=$(git rev-parse HEAD)
VERSION=$(sed -n 's/^version: //p' pubspec.yaml)
flutter run -d macos \
  --dart-define=GIT_COMMIT="$COMMIT" \
  --dart-define=APP_VERSION="$VERSION"
```

应用包还需要当前桌面打包方案使用的 PFS 和 EGL/GLES library。不能从同一 framework
的多个副本重复加载 native library，否则可能产生重复 Objective-C class 或运行时崩溃。

### iOS framework

先安装 Rust target，然后运行：

```bash
rustup target add aarch64-apple-ios aarch64-apple-ios-sim

CORE_SRC=/path/to/art3m1s-core \
PFS_SRC=/path/to/pfs-upk-rust \
METALANGLE_SIM_FRAMEWORK=/path/to/MetalANGLE-simulator.framework \
./scripts/ios_build_rust.sh --release
```

脚本默认构建 `aarch64-apple-ios` 与 `aarch64-apple-ios-sim`，并输出包含真机与
Apple Silicon 模拟器切片的 `.xcframework`。MetalANGLE 的真机源 framework 默认读取
`ios/Frameworks/MetalANGLEDevice.framework`（首次也兼容旧名 `MetalANGLE.framework`），
模拟器 framework 首次通过 `METALANGLE_SIM_FRAMEWORK` 指定；脚本会将两者分别保存为
`MetalANGLEDevice.framework` 与 `MetalANGLESimulator.framework`，后续无需重复指定。
只为真机构建时使用 `--device-only`；
需要在打包过程中直接签署 framework 时使用 `--sign "证书名称"`。
构建完成后 `ios/Frameworks/` 中会生成 core、PFS 与 MetalANGLE 三个 XCFramework。

### 验证

```bash
flutter analyze
flutter test
```

修改 native/runtime 后还应在 `art3m1s-core` 中通过 `cargo test`，并使用真实游戏日志
验证。仅能成功编译并不能证明脚本兼容性。

## 调试

- Rust 日志通过已注册回调进入当前游戏会话的统一日志记录器。
- 调试浮窗显示 runtime、帧和媒体状态，日志部分使用等宽字体。
- 关闭调试浮窗时会同步更新持久化开关，切换场景后不会再次自行出现。
- 可以在设置中导出日志。Apple 平台会将其存入应用 Documents 目录，可通过文件
  App 或 Finder 共享。

常用的 runtime 日志标记包括 `Event::SaveGame`、`Event::LoadGame`、`VideoPlay`、
`LayerCreate`、对话框请求和翻译序号。

## 当前限制

- 画面显示仍会把 CPU RGBA buffer 转换成 `ui.Image`，目前不是共享 GPU surface。
- Artemis HLSL 和 E-Mote 兼容层只覆盖测试游戏中观察到的变体，并不支持所有私有
  引擎版本。
- 部分引擎平台事件仍依赖各目标平台的宿主实现。
- 移动端大型游戏应通过原生目录/文件导入流程添加，不能使用会把整个归档读入内存的
  API。

## 相关仓库

| 仓库 | 职责 |
|---|---|
| [Alphaly2K/art3m1s](https://github.com/Alphaly2K/art3m1s) | Flutter 宿主应用 |
| [Alphaly2K/art3m1s-core](https://github.com/Alphaly2K/art3m1s-core) | Rust runtime、解释器、合成器和支持 crate |
| [Alphaly2K/pfs-upk-rust](https://github.com/Alphaly2K/pfs-upk-rust) | PFS reader 与流式 FFI |

## 版本说明

[完整变更记录](CHANGELOG.md)

## 许可证

[AGPLv3](LICENSE)
