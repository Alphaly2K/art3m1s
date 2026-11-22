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
翻译补丁和翻页后迟到的译文、音效结束和读档恢复、H.264 与 AVI 图层呈现、WMV 全屏循环和跳过，
以及项目切换后的解码失败处理。
需要 macOS 桌面、Metal 设备，以及 `PATH` 中支持 `libx264`、`wmv2`、`wmav2`、`msmpeg4v3` 编码的 `ffmpeg`。
无需提供游戏文件。

设置 `ARTEMIS_V2_THEORA_FIXTURE` 指向 Core 测试中的 `blue-theora.ogv`，可用无音轨 Ogg
替换图层 AVI，复用相同的呈现、截图和完成回调断言。全屏片段仍使用 WMV。

验证 v2 的 ANGLE/Metal 可选后端时，沿用上述构建命令，把 `--target` 改为
`tool/integration_tests/artemis_v2_angle_smoke.dart`，再运行生成的应用。该入口使用包内 ANGLE
库和合成 GLSL 项目，检查 Flutter 纹理的合成像素和脚本保存的 PNG，无需游戏文件或 FFmpeg。

验证真实 macOS 音频播放器时，将同一命令的 `--target` 改为
`tool/integration_tests/artemis_v2_audio_smoke.dart`。该入口自建短 WAV，检查 B 段播放位置回绕、
交叉淡出、应用后台和会话冻结分别暂停媒体、恢复以及释放顺序，无需游戏文件或 FFmpeg。运行时会播放短音。

验证脚本窗口操作时，将 `--target` 改为 `tool/integration_tests/artemis_v2_window_smoke.dart`。
测试窗口会进入全屏、最小化并恢复，验证这些操作不切换播放器所在的 Shell，最小化期间脚本等待
不推进，恢复后可从原场景存档。需要活跃的 macOS 桌面会话，无需游戏文件或 FFmpeg。

验证 v1 和 v2 存档互读时，将 `--target` 改为
`tool/integration_tests/artemis_save_interop_smoke.dart`。该入口自建项目和存档，验证非默认
`SAVEPATH` 的系统存档与编号存档能在两版之间往返，以及旧预览目录仍可读写。

验证 HLSL 时，将 `--target` 改为 `tool/integration_tests/artemis_v2_dxvk_smoke.dart`，构建时
同时设置 `ARTEMIS_V2_DXVK_RUNTIME_DIR` 和 `ARTEMIS_V2_HLSL_COMPILER_DIR`，指向渲染运行时和
编译器的打包目录。在 macOS 桌面运行应用时设置 `ARTEMIS_DXVK_TEST_CACHE_TOKEN` 为一个新的
字母数字标识；再用同一标识和 `ARTEMIS_DXVK_TEST_WARM=1` 运行一次，验证缓存复用。测试使用
合成项目，检查首帧前预热、启动缓存被拒绝后的首次读取恢复、Flutter 纹理像素和脚本截图。
应用同时打包 ANGLE 时，设置 `ARTEMIS_DXVK_TEST_MIXED=1`，额外检查 GLSL 背景取样能读到
同一帧的 HLSL 绘制结果。
用 `--release` 构建并同时设置 `ARTEMIS_DXVK_TEST_1080P=1` 和 `ARTEMIS_DXVK_TEST_MIXED=1`，可对照
纯 DXVK 和分别叠加一层、四层 GLSL 的 1080p 帧耗时。探针丢弃前 20 帧，报告后续 120 帧的中位数
和 P95，并检查每层效果的颜色累加。

验证原始归档中的着色器时，将 `--target` 改为
`tool/integration_tests/artemis_v2_archive_shader_smoke.dart`，保留 ANGLE、DXVK 和编译器。
运行时用 `ARTEMIS_SHADER_TEST_ARCHIVE` 指定可使用的 PFS 单卷归档，用 `ARTEMIS_SHADER_TEST_HLSL`
和 `ARTEMIS_SHADER_TEST_GLSL` 指定归档内实现反色的两个项目资源键。探针复制归档到临时目录，
使用合成场景检查两种效果同帧绘制的窗口纹理和脚本截图。此检查不进入默认测试范围。
