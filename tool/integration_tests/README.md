# 显式集成验证

这些测试需要自行提供游戏资源、编码音频或与当前 ABI 匹配的 core library，默认 `flutter test` 不会发现它们。常规单元测试使用合成输入，不需要这些材料。

- RFVP 启动、舞台和音频命令：设置 `RFVP_SMOKE_GAME`（游戏目录）及 `ART3M1S_CORE_LIBRARY`（自行编译的 core library），运行 `flutter test tool/integration_tests/rfvp_runtime_smoke_test.dart tool/integration_tests/rfvp_stage_probe_test.dart tool/integration_tests/rfvp_audio_probe_test.dart`。
- RFVP 音频解码：设置 `RFVP_AUDIO_PROBE_INPUT`（可合法使用的编码音频），运行 `flutter test tool/integration_tests/rfvp_media_decode_test.dart`。
- macOS 引擎验证：准备与项目 ABI 一致的 native runtime，并设置 `ART3M1S_SIGLUS_TEST_GAME` 或 `ART3M1S_ARTEMIS_TEST_GAME`（对应游戏目录），运行 `flutter test tool/integration_tests/engine_native_test.dart`。
- KRKR/Siglus ABI：构建同时启用两种引擎的 core，设置 `ART3M1S_CORE_LIBRARY` 为其动态库路径，运行 `flutter test tool/integration_tests/engine_abi_test.dart`。该检查只验证真实库的契约加载与非法句柄处理，不需要游戏或音频设备。

SwiftUI 目录服务的合成输入验证可在安装 Xcode 命令行工具的 macOS 上运行 `bash tool/native_host_tests/run.sh`，无需游戏、core library 或模拟器。它覆盖导入冲突、重复扫描保留配置、旧数据恢复、路径边界和翻译关闭行为；归档读取使用拒绝加载的测试替身。

## RFVP 播放器版本

Flutter 优先使用 RFVP v2。旧动态库只提供 v1 时，播放器自动使用 v1。构建时传入
`--dart-define=RFVP_V2=false` 或在桌面设置 `RFVP_V2=0` 可指定 v1。Dart 定义优先于进程环境。

在 Core 仓库用 `cargo build --locked --features rfvp-engine,metal-backend --lib` 构建 macOS
动态库，再运行 `python3 tools/host-smoke/rfvp_tile.py "$RFVP_SMOKE_GAME/tile.hcb" --services`
生成合成项目。`RFVP_SMOKE_GAME` 指向一个空目录。使用当前构建的动态库运行：

```sh
RFVP_SMOKE_WIDTH=640 RFVP_SMOKE_HEIGHT=480 RFVP_SMOKE_TILE=1 \
RFVP_SMOKE_SERVICES=1 RFVP_SMOKE_EXPECT_VERSION=2 \
flutter test tool/integration_tests/rfvp_runtime_smoke_test.dart
```

将版本期望改成 `1`，并传入 `--dart-define=RFVP_V2=false`，可验证 v1 路径。

验证 v2 的资源和存档时，用 `--io` 生成另一个合成项目，并通过 `RFVP_SMOKE_GAME` 指向该目录。
保持同一个 macOS 动态库，运行下列测试。它核对封包与松散资源的渲染像素、编号存档及全局存档，
并检查编号存档保存在播放器选择的目录。

```sh
RFVP_SMOKE_WIDTH=640 RFVP_SMOKE_HEIGHT=480 RFVP_SMOKE_IO=1 \
RFVP_SMOKE_EXPECT_VERSION=2 flutter test --dart-define=RFVP_V2=true \
  --plain-name='reads v2 Host assets' tool/integration_tests/rfvp_runtime_smoke_test.dart
```

验证 macOS 窗口里的共享纹理时，运行
`flutter build macos --debug --target=tool/integration_tests/rfvp_macos_smoke.dart`。
在桌面会话中用相同的 `RFVP_SMOKE_GAME` 和 `ART3M1S_CORE_LIBRARY` 运行生成的应用可执行文件。
`RFVP_SMOKE_EXPECT_VERSION=2` 检查默认路径。设置 `RFVP_V2=0 RFVP_SMOKE_EXPECT_VERSION=1`
检查 v1。探针核对 Flutter 合成像素，以及会话恢复后能否重新绑定并呈现。

## KatzeSystem2

在 macOS 上，用与动态库配套的头文件构建合成宿主。测试调用开发 ABI 0，验证绘制命令经 Flutter 呈现后的像素、独立混音生成的 PCM，以及会话结束时的资源释放。它使用合成 KCS 和音频，不需要游戏、窗口或声音设备。

```sh
katze=/absolute/path/to/KatzeSystem2
(cd "$katze" && cargo build --locked --release -p katze-system2-ffi)
binding="$katze/crates/katze-system2-ffi"
fixtures="$PWD/.dart_tool/katze-smoke"
python3 "$binding/examples/fixtures.py" "$fixtures"
cc -std=c11 -Wall -Wextra -Werror -dynamiclib -I "$binding/include" \
  tool/integration_tests/katze_fixture_host.c -o "$fixtures/libkatze_fixture_host.dylib"
KATZE_LIBRARY="$katze/target/release/libkatze_system2_ffi.dylib" \
  KATZE_FIXTURE_HOST="$fixtures/libkatze_fixture_host.dylib" KATZE_FIXTURES="$fixtures" \
  flutter test tool/integration_tests/katze_abi_test.dart
```

构建带有归档、输入及存档回调的示例宿主并运行读写测试。PFS 或原引擎资源不参与合成存档回归。

```sh
(cd "$katze" && cargo build --locked --release -p katze-system2-host --features builtin-mpeg)
KATZE_GAME_HOST="$katze/target/release/libkatze_system2_host.dylib" \
  KATZE_FIXTURES="$fixtures" flutter test tool/integration_tests/katze_storage_test.dart
```

使用同一 `KATZE_GAME_HOST`，再指定 `KATZE_GAME` 为已解包项目目录，可显式运行 `flutter test tool/integration_tests/katze_game_test.dart`。`KATZE_GAME_ENCODING` 可覆盖默认 CP932。可设置 `KATZE_GAME_TEST_CLICK` 为 `x,y,按下轮次,总轮次`，采样指针所在场景和点击后的画面及 PCM。验证默认使用内存音频。

设置 `KATZE_GAME_HOST` 后，Flutter 的游戏库可识别含 `config/startup.xml` 的目录，并通过通用播放器加载。每个游戏可在 `art3m1s.json` 中设置 `katzeScriptEncoding`，例如 `"gbk"`。缺省时可用 `KATZE_GAME_ENCODING` 提供调试默认值。`tool/integration_tests/katze_player_test.dart` 使用同样的两个变量及 `KATZE_GAME`。设置 `KATZE_OFFSCREEN_AUDIO=1` 核对导入、推进、暂停恢复、软件画面和内存混音。宿主也可启用 `device-audio`，测试时设置 `SDL_AUDIODRIVER=dummy` 以验证设备启停。

运行 `dart run tool/build.dart macos --katze --debug` 可从 KatzeSystem2 源码构建并打包 Host。将 `KATZE_SRC` 指向源码目录，或使用与 Flutter 项目同级的源码。

可把同一宿主装入本地 macOS 预览构建。用 `KATZE_RUNTIME_DIR` 指定含宿主动态库的目录，然后执行普通的 `flutter build macos`。应用从自己的 Frameworks 目录加载库，`KATZE_GAME_HOST` 仍可用于指定本地调试构建。 同一目录可放入配套 `libart3m1s_artemis_media_host.dylib`，支持从游戏归档播放 WebM。打包时沿用应用的 FFmpeg 库，运行时自动发现该媒体宿主。

设置 `KATZE_RUNTIME_DIR` 后运行 `dart run tool/build.dart macos --debug`，预览中的 core 会提供 E‑Mote 模型回调。Flutter 创建会话时自动挂载该服务。离屏测试可通过 `ART3M1S_CORE_LIBRARY` 指定启用了 `metal-backend,katze-model-host` 的 core 动态库。

设置 `KATZE_GAME_HOST`、`KATZE_FIXTURES` 和 `KATZE_OFFSCREEN_AUDIO=1` 后，运行 `flutter test tool/integration_tests/katze_window_test.dart` 核对脚本窗口请求与状态回报。

沿用同一合成资源和环境变量，运行 `flutter test tool/integration_tests/katze_text_entry_test.dart` 核对脚本文字输入、空字符串提交与取消。

沿用同一合成资源和环境变量，运行 `flutter test tool/integration_tests/katze_script_log_test.dart` 核对脚本消息在同步和异步推进后进入调试日志，并验证报错前的消息可导出。

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
