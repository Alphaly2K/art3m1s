# 显式集成验证

这些测试需要自行提供游戏资源、编码音频或与当前 ABI 匹配的 core library，默认 `flutter test` 不会发现它们。常规单元测试使用合成输入，不需要这些材料。

- RFVP 启动、舞台和音频命令：设置 `RFVP_SMOKE_GAME`（游戏目录）及 `ART3M1S_CORE_LIBRARY`（自行编译的 core library），运行 `flutter test tool/integration_tests/rfvp_runtime_smoke_test.dart tool/integration_tests/rfvp_stage_probe_test.dart tool/integration_tests/rfvp_audio_probe_test.dart`。
- RFVP 音频解码：设置 `RFVP_AUDIO_PROBE_INPUT`（可合法使用的编码音频），运行 `flutter test tool/integration_tests/rfvp_media_decode_test.dart`。
- macOS 引擎验证：准备与项目 ABI 一致的 native runtime，并设置 `ART3M1S_SIGLUS_TEST_GAME` 或 `ART3M1S_ARTEMIS_TEST_GAME`（对应游戏目录），运行 `flutter test tool/integration_tests/engine_native_test.dart`。
- KRKR/Siglus ABI：构建同时启用两种引擎的 core，设置 `ART3M1S_CORE_LIBRARY` 为其动态库路径，运行 `flutter test tool/integration_tests/engine_abi_test.dart`。该检查只验证真实库的契约加载与非法句柄处理，不需要游戏或音频设备。

SwiftUI 目录服务的合成输入验证可在安装 Xcode 命令行工具的 macOS 上运行 `bash tool/native_host_tests/run.sh`，无需游戏、core library 或模拟器。它覆盖导入冲突、重复扫描保留配置、旧数据恢复、路径边界和翻译关闭行为；归档读取使用拒绝加载的测试替身。

## macOS Artemis v2

从项目根目录运行 `dart run tool/build.dart macos --debug --artemis-v2` 构建预览。应用同时打包
v1、独立 v2 Core、Metal Host 和媒体 Host。默认构建仍使用 v1；预览支持资源、存档、输入、对话框、
共享纹理、脚本截图、HTTP、翻译及宿主音视频播放。

完成上述构建后，可显式验证合成项目：

```sh
ARTEMIS_V2_RUNTIME_DIR="$PWD/.build/artemis-v2" flutter build macos --debug \
  --dart-define=ARTEMIS_V2=true --target=tool/integration_tests/artemis_v2_macos_smoke.dart
build/macos/Build/Products/Debug/art3m1s.app/Contents/MacOS/art3m1s
```

冒烟自建游戏、存档目录、音视频和本地 HTTP 服务，验证 v1 可加载及 v2 保存、截图、HTTP 取消、
翻译补丁和翻页后迟到的译文、音效结束和读档恢复、H.264 与 WMV 图层呈现、全屏循环和跳过，
以及项目切换后的解码失败处理。
需要 macOS 桌面、Metal 设备，以及 `PATH` 中支持 `libx264`、`wmv2`、`wmav2` 编码的 `ffmpeg`。
无需提供游戏文件。
