# 显式集成验证

这些测试需要自行提供游戏资源、编码音频或与当前 ABI 匹配的 core library，默认 `flutter test` 不会发现它们。常规单元测试使用合成输入，不需要这些材料。

- RFVP 启动、舞台和音频命令：设置 `RFVP_SMOKE_GAME`（游戏目录）及 `ART3M1S_CORE_LIBRARY`（自行编译的 core library），运行 `flutter test tool/integration_tests/rfvp_runtime_smoke_test.dart tool/integration_tests/rfvp_stage_probe_test.dart tool/integration_tests/rfvp_audio_probe_test.dart`。
- RFVP 音频解码：设置 `RFVP_AUDIO_PROBE_INPUT`（可合法使用的编码音频），运行 `flutter test tool/integration_tests/rfvp_media_decode_test.dart`。
- macOS 引擎验证：准备与项目 ABI 一致的 native runtime，并设置 `ART3M1S_SIGLUS_TEST_GAME` 或 `ART3M1S_ARTEMIS_TEST_GAME`（对应游戏目录），运行 `flutter test tool/integration_tests/engine_native_test.dart`。
- KRKR/Siglus ABI：构建同时启用两种引擎的 core，设置 `ART3M1S_CORE_LIBRARY` 为其动态库路径，运行 `flutter test tool/integration_tests/engine_abi_test.dart`。该检查只验证真实库的契约加载与非法句柄处理，不需要游戏或音频设备。

SwiftUI 目录服务的合成输入验证可在安装 Xcode 命令行工具的 macOS 上运行 `bash tool/native_host_tests/run.sh`，无需游戏、core library 或模拟器。它覆盖导入冲突、重复扫描保留配置、旧数据恢复、路径边界和翻译关闭行为；归档读取使用拒绝加载的测试替身。
