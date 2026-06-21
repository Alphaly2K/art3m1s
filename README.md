# Art3m1s

Artemis 视觉小说引擎的跨平台前端，基于 Flutter + Rust。

## 架构

```
┌──────────────────────────────────┐
│  Flutter 宿主 (Dart)             │
│  ┌────────────┐ ┌─────────────┐  │
│  │ UI / 设置   │ │ 主循环 16ms  │  │
│  │ (Riverpod)  │ │ timer → FFI │  │
│  └────────────┘ └──────┬──────┘  │
│                        │         │
│              FFI (dart:ffi)      │
├────────────────────────┼─────────┤
│  art3m1s-core (Rust)   │         │
│  ┌─────────────────────┴──────┐  │
│  │  CoreRuntime               │  │
│  │  ┌──────────┐ ┌──────────┐ │  │
│  │  │Compositor│ │Interpreter│ │  │
│  │  │(Scene +  │ │(ASB/Lua) │ │  │
│  │  │ Renderer)│ └──────────┘ │  │
│  │  ├──────────┤              │  │
│  │  │GL Backend│ Audio/Vid    │  │
│  │  │(glow+   │ Backend      │  │
│  │  │ ANGLE)  │ (rodio/ffmpeg)│  │
│  │  └──────────┘              │  │
│  └────────────────────────────┘  │
└──────────────────────────────────┘
```

### 依赖关系

| 组件 | 语言 | 说明 |
|------|------|------|
| `art3m1s` | Dart | Flutter 前端，UI、设置、主循环 |
| `art3m1s-core` | Rust | 核心引擎，渲染、音频、视频、脚本解释 |
| `asb-interpreter` | Rust | Artemis ASB/IET/AST 脚本解释器 |
| `pfs-upk-rust` | Rust | PFS 归档解包 |
| `asb-decrypt` | Rust | ASB 脚本解密 |
| `libEGL.dylib` / `libGLESv2.dylib` | C++ | ANGLE，跨平台 OpenGL ES 实现 |

### Core 产生的像素数据如何到屏幕上

```
Rust CoreRuntime::advance_and_render()
  → Compositor::render()
    → update_video_textures()
    → build_frame() → DrawList
    → inject_fullscreen_video()
    → GlRenderer::render() → FBO
    → glReadPixels() → Vec<u8>
  → FFI 返回 RGBA 像素
→ Dart Uint8List
→ ui.decodeImageFromPixels() → ui.Image
→ RawImage widget → 全屏显示
```

Core 不拥有窗口——它只产出像素 buffer，Flutter 负责显示。

### 文件 IO

Core 不直接读文件。所有文件操作通过 FFI callback 路由到宿主：

```
Core 请求文件 → ffi::request_file()
  → art3m1s_register_file_reader callback
    → Dart FileProvider → PFS 归档 / 本地目录
```

### 音频架构

```
Script [splay] / [seplay] 标签
  → Interpreter → Event::BgmPlay / SePlay
    → Compositor::forward_audio_event()
      → AudioBackend::play_bgm/play_se()
        → RodioBackend (rodio + cpal)
```

音量控制通过全局变量 `s.bgmvol` / `s.sevol`（0-1000），每帧从 VariableStore 读出并同步到 AudioBackend。

## 开发

### 前置条件

- Flutter SDK ≥ 3.44

### 构建

```bash
# Rust core dylib
cd art3m1s-core
cargo build --release

# 复制到 Flutter 项目
cp target/release/libart3m1s_core.dylib ../Art3m1s/

# 签名 (macOS)
codesign --force --sign - ../Art3m1s/libart3m1s_core.dylib
codesign --force --sign - ../Art3m1s/libpfs_upk.dylib
codesign --force --sign - ../Art3m1s/libEGL.dylib
codesign --force --sign - ../Art3m1s/libGLESv2.dylib

# 运行 Flutter
cd ../Art3m1s
flutter run -d macos
```

### 调试

设置页面开启「调试模式」后 Rust core 侧会输出 `[event]` 日志，可在 `art3m1s.log` 或控制台查看。