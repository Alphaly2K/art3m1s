# KRKR 跨平台构建

`--krkr` 构建真实 KRKRSDL3 runtime；普通构建可能仅含不可运行的
`native-bootstrap` ABI 占位库。构建前准备与
`art3m1s-core/crates/art3m1s-krkr/UPSTREAM.md` 一致的上游源码、构建仓库和
vcpkg 依赖，并设置：

```sh
export KRKRSDL3_SOURCE_DIR=/path/to/krkrsdl3
export KRKRSDL3_BUILD_DIR=/path/to/krkrsdl3_build
export VCPKG_ROOT=/path/to/vcpkg
# 若 vcpkg 安装目录不在 CMake 默认位置，还需设置 VCPKG_INSTALLED_DIR。
```

在对应平台的构建机运行：

```sh
dart run tool/build.dart macos --release --krkr
dart run tool/build.dart ios --release --krkr       # Art3m1sNative (SwiftUI)
dart run tool/build.dart android --release --krkr   # arm64-v8a
dart run tool/build.dart windows --release --krkr   # x64
dart run tool/build.dart linux --release --krkr     # x64
```

Windows/Linux 需在目标系统本机运行；iOS/macOS 需 Xcode；Android 需 Android
SDK/NDK 和 cargo-ndk。构建脚本设置 `ART3M1S_KRKR_REQUIRE_UPSTREAM=1`，缺少真实
上游依赖时直接失败，不会静默打包 bootstrap。iOS 生产入口是
`native/ios/Art3m1sNative`，不是旧 Flutter iOS 项目；它会读取游戏清单的
`krkrEntryXp3` 作为选定的启动 XP3。

同时构建 iOS 真机和模拟器时，请将两个 vcpkg manifest triplet 分别安装到不同目录，
并设置 `VCPKG_INSTALLED_DIR_DEVICE` 与 `VCPKG_INSTALLED_DIR_SIMULATOR`。共用一个
manifest 安装目录会在切换 triplet 时移除另一切片的依赖。

打包时会将 KRKR native host 和 `Res/DroidSansFallback.ttf` 放入各平台所需的位置。
Android 还会从构建 `libSDL3.so` 的 vcpkg SDL3 同版本源码暂存 Java JNI 类，Flutter Activity 负责资产管理器与
菜单/输入框桥接。独立 `.dll`/`.tpm` 插件和真实扬声器输出尚未接入；在发布前应在每个
目标平台用实际 XP3 游戏验证启动、输入、存档和退出。
