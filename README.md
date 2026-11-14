<p align="center">
  <img src="assets/branding/art3m1s-logo-v1.png" alt="Art3m1s icon" width="168">
</p>
# Art3m1s

> [!IMPORTANT]
>
> 该项目由并几乎完全由 AI 完成实际开发，谨慎用于生产环境。
>
> 该项目只提供对合法游戏副本的启动功能，不提供游戏副本。

Art3m1s 是一个多引擎支持的视觉小说启动器，支持 Windows、Linux、macOS、Android、iOS 等多个平台。

## 功能

- 支持 Artemis、Siglus、AVG32、FVP、KRKR 等引擎游戏的运行。
- 支持以游戏库的形式管理游戏，并提供了各游戏存档隔离的实现。
- 根据不同系统提供了多套原生 UI 壳。
- 支持基于文本替换的语言翻译及在线自动翻译。

## 构建

> [!IMPORTANT]
>
> 原 Flutter 项目的 iOS 目标已被标记为废弃状态，如需构建 iOS 产物，请使用 [新的 SwiftUI 项目](native/ios/Art3m1sNative) 或直接使用统一构建脚本。

### 前置要求

- Flutter 3.47.4
- Rust Edition 2024/2021
- [vcpkg](https://github.com/microsoft/vcpkg)

### 统一构建脚本

```bash
dart run tool/build.dart [all|ios|ios-obsolete|macos|android|windows|linux] \
  [--release|--profile|--debug] [--device-only] [--sign-only] [--krkr] [--siglus]
```

`all` 表示能够原生构建的全部目标，`ios-obsolete` 为原 Flutter iOS 目标，不会加入 `all` 构建列表。
`krkr` 与 `siglus` 参数均需要额外的环境变量，详情参考错误信息。
需要 H.264 UCI 视频时，设置目标平台的 `FFMPEG_DIR` 后重新构建。

启用 `krkr` 参数时，参考下方环境变量设置：

```bash
VCPKG_ROOT=/path/to/vcpkg \
KRKRSDL3_SOURCE_DIR=/path/to/krkrsdl3 \
KRKRSDL3_BUILD_DIR=/path/to/krkrsdl3_build \
dart run tool/build.dart macos --release --krkr
```

## 当前限制

- Apple 平台默认原生 Metal，不支持时回退 native render。
- 对于 Android 平台，原生 Vulkan 为实验选项，默认使用 ANGLE / OpenGL ES。

## 相关仓库

| 仓库 | 职责 |
|---|---|
| [Alphaly2K/art3m1s](https://github.com/Alphaly2K/art3m1s) | Art3m1s Host |
| [Alphaly2K/art3m1s-core](https://github.com/Alphaly2K/art3m1s-core) | Art3m1s Runtime |
| [Alphaly2K/pfs-upk-rust](https://github.com/Alphaly2K/pfs-upk-rust) | PFS Reader |

## 版本说明

版本变更记录见 CHANGELOG.md。

## 许可证

Mozilla Public License 2.0
