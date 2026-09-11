# Art3m1s iOS 启动诊断工具

此工具用于调查 iOS 14.5 / TrollStore 上的启动闪退，不是修复版应用。
Probe 在独立原生界面中逐项加载已有 Art3m1s 构建的动态库，保存加载前后的日志，
不会启动 Flutter engine、Dart 或 Runner 的静态插件注册流程。
Native Trace 则沿用 Probe 的原生界面和分享按钮，在加载完成后继续启动 Flutter，成功后显示正式 Flutter UI。

截至 2026-09-11，原问题设备已分别完成 Lazy、Now 的全部 75 步，27 个嵌入库均加载成功；
Native Trace 也已两次进入 Flutter，原正式应用仍打开即闪退。
后续调查发现 Mpv 依赖的 AVFoundation / AVFAudio 在 Trace 中提前加载，已补充生产链接配置。
候选修复通过 Profile 构建验证，随后用户确认原 iOS 14.5 设备已能正常启动；
官方 dyld 对照仍不能排除越狱环境差异，也不等于全部业务功能已验收。
完整证据和限制见[调查报告](../../doc/ios14-startup-crash-2026-09-10.md)。
另一台 iOS 17.3 设备的普通包白屏、Trace 成功及注入库情况，见
[独立白屏记录](../../doc/ios17-startup-white-screen-2026-09-11.md)。

后续生产构建已统一采用原生启动路径，见[生产入口说明](../../doc/ios-native-launcher-assessment-2026-09-11.md)。
本目录保留历史诊断工具，Native Trace 的 payload 转换仅适用于原来的普通 Runner 构建；
不要对新的原生入口 Runner 再运行 `build_launcher.py`。生产 IPA 使用 `tool/package_ios_native.py` 打包。

## 测试人员操作

无需开发环境，由维护者提供诊断 IPA。包名为 Art3m1s Probe，可与原应用同时安装。

1. 记录设备型号、完整 iOS 版本、TrollStore 版本、是否越狱及安装时的 Unsandbox 设置。
   不确定的项目写“不清楚”，无需为了测试改变越狱状态。
2. 记录正在测试的原应用版本和 IPA 来源，确认它是否打开即闪退。保留原应用及数据，
   不要通过卸载或清除数据来准备测试。
3. 使用 TrollStore 安装维护者提供的诊断 IPA，保持默认沙盒，不主动开启 Unsandbox。
4. 打开 Art3m1s Probe，保持 Lazy，点击右上角播放按钮，等待出现 COMPLETE 或错误。
5. 点击分享按钮导出 `startup-probe.log`。若中途闪退，重新打开后先导出旧日志，并收集对应 `.ips`。
6. 如果 Lazy 完成，从多任务界面彻底结束诊断进程。重新打开，选择 Now，再运行并导出日志。
   两种模式必须分开启动进程测试；日志会保留之前的记录。

若诊断界面本身无法打开，反馈现象和诊断应用的 `.ips`，无需反复重装。
系统崩溃报告可在“设置 > 隐私（或隐私与安全性）> 分析与改进 > 分析数据”中查找；
原应用通常以 Runner 命名，诊断应用通常以 StartupProbe 命名。

### 反馈模板

```text
设备型号：
iOS 版本及构建号：
TrollStore 版本：
是否越狱 / 是否有插件注入（不清楚可注明）：
原应用版本 / IPA 文件名及来源：
原应用安装时的 Unsandbox 设置：
原应用启动结果：
诊断 IPA 文件名及维护者提供的 SHA-256：
诊断包安装时的 Unsandbox 设置：
Lazy 结果 / 测试时间：
Now 结果 / 测试时间：
附件：startup-probe.log；如有闪退，附对应 .ips
```

## 构建与分发

需要 macOS、带 iOS SDK 的完整 Xcode、Python 3.9 或更高版本，以及已经构建好的 `.app`。
构建目标为 arm64；模拟器版本用于 Apple Silicon。脚本不负责构建 Flutter 或 Rust 源码。
调查既有崩溃时，应选择 UUID 与报告匹配的应用，并保留它的 dSYM。

从仓库根目录运行：

```sh
python3 tool/ios_startup_probe/build.py build/ios/Profile-iphoneos/Runner.app
```

脚本复制源应用的 Frameworks 到新目录，编译原生入口，生成 dSYM，
对副本进行 ad-hoc 签名和深度校验，最后生成 IPA。源应用不被修改。
该真机 IPA 供 TrollStore 安装，不是 App Store 或普通开发签名包。

输出位于 `build/ios/startup-probe/iphoneos-*/`，也可通过 `--output` 指定尚不存在的目录：

| 文件 | 用途 |
| --- | --- |
| `Art3m1s-startup-probe.ipa` | 发给测试人员安装 |
| `StartupProbe.app.dSYM` | 维护者留存，用于诊断包自身崩溃的符号化 |
| `source-inventory.json` | 源应用路径、源二进制 UUID、签名前 SHA-256、加载步骤 |
| `Payload/StartupProbe.app/ProbeManifest.plist` | 诊断包实际使用的加载清单 |

每次分发记录 IPA 的 SHA-256，并把这一输出目录与反馈日志一起归档；不同构建的结果分开记录。
只提交源码及文档到 Git，生成的二进制、dSYM 和设备原始日志留作调查产物。

```sh
shasum -a 256 build/ios/startup-probe/<输出目录>/Art3m1s-startup-probe.ipa
```

模拟器版本可由已有模拟器应用生成：

```sh
python3 tool/ios_startup_probe/build.py build/ios/Debug-iphonesimulator/Runner.app --sdk iphonesimulator
```

安装到模拟器后，可用 `simctl launch` 传入 `--probe-run` 自动运行 Lazy，
额外传入 `--probe-now` 运行 Now。每次运行前结束旧进程。
模拟器的库与系统不同，其通过不能代替 iOS 14.5 真机结果。

## 解读结果

- `BEGIN` 后的日志已刷入磁盘。闪退前最后一个未完成的步骤是调查入口，
  但故障也可能位于它的依赖或初始化函数中。
- `OPTIONAL MISSING` 表示声明为弱链接的库加载失败，应保留完整错误。
  旧系统缺少新系统库可能是正常情况，但后续调用是否正确做版本保护尚未验证。
- `FAILED` / `EXCEPTION` 表示该轮诊断提前停止；反馈完整日志，不只截最后一行。
- `COMPLETE` 仅表示该模式下所有必需库加载完成。Now 会提前解析延迟符号，
  但两种模式都不会执行完整应用初始化。

原应用与探针的入口、加载顺序、签名和权限不同。两种模式都通过且原应用仍闪退时，
应继续采集正式 Runner 的启动过程和设备日志，不能据此认定原问题已修复。

## 第二阶段：Art3m1s Native Trace

### 测试操作

1. 用 TrollStore 安装维护者提供的 `Art3m1s-native-trace.ipa`，保持默认沙盒。
   应用显示为 Art3m1s Trace，标识为 `moe.alphaly.art3m1s.startuplauncher`，与原应用和 Probe 并存。
2. 打开后先看到 Probe 风格的原生日志界面。点击播放按钮，工具会先复用 Probe 的 75 步加载，
   然后加载 Runner 副本、注册插件并启动 Flutter。成功后会进入正式 Flutter UI，右上角保留分享按钮。
3. 若 Flutter 启动前或启动中闪退，重新打开同一个 Trace 应用，原生界面会显示上次已刷盘的
   `startup-trace.log`，先点击分享按钮导出，不要先点播放。正常打开不会自动重跑 Flutter；
   日志导出不依赖 Files 中是否可见，也不依赖 Flutter 或 Dart 创建 `Art3m1s` 目录。
4. 如果连原生界面都打不开，附上对应时间的诊断应用 `.ips`（通常以 StartupProbe 命名）；若日志文件没有出现，明确反馈“无日志”，
   不需要反复重装。原应用及数据继续保留。

Native Trace 使用独立数据容器，不会读取原应用的游戏和存档；诊断期间不必导入游戏。

### 构建

另需 Python 3.12 或更高版本及固定版本的 LIEF，用于把 Runner 的可执行代码转换成可延迟加载的 payload：

```sh
python3 -m venv build/ios/startup-probe/trace-tools
build/ios/startup-probe/trace-tools/bin/pip install -r tool/ios_startup_probe/requirements-trace.txt
build/ios/startup-probe/trace-tools/bin/python tool/ios_startup_probe/build_launcher.py \
  build/ios/Profile-iphoneos/Runner.app \
  --flutter-framework build/ios/Profile-iphoneos/Flutter.framework
```

`--flutter-framework` 必须提供带 Headers 的对应 Flutter.framework。
模拟器构建使用模拟器 `.app` 和 Flutter.framework，并传入 `--sdk iphonesimulator`。
脚本沿用 Probe 的原生入口和库清单，在副本中加入 `RunnerPayload.dylib`、`RunnerBridge.dylib`，
并重新签名生成 IPA。Runner payload 的 section 内容、地址、偏移，以及依赖顺序、
符号绑定、重定位和导出地址在转换前后校验一致；
header padding 不足时拒绝构建，不移动原代码。Debug 的 `Runner.debug.dylib` 存在时使用它作为 payload。

输出包含 `Art3m1s-native-trace.ipa`、`StartupProbe.app.dSYM`、`RunnerBridge.dylib.dSYM`、
`launcher-inventory.json`，以及源应用旁存在的 Runner dSYM 副本。Runner payload 保留原 UUID 以使用原 dSYM；
它被转换成 dylib，不能用 UUID 相同来认定文件未经修改，应核对清单中的 SHA-256。

### 覆盖与限制

Native Trace 通过 Probe 先写原生日志，再记录 Runner 生命周期、Flutter 引擎创建及启动、插件注册，
并最多记录 200 次 Flutter MethodChannel 调用的方法名及回复状态，不主动记录参数与返回值。
stdout / stderr 也写入同一个文件，其内容由原应用和引擎决定。
私有 Flutter 方法在签名匹配时才包装，不匹配会记录 `HOOK_SKIPPED`。
`METHOD` 能证明 Dart 已经调用原生通道，但不会覆盖直接 FFI 调用或所有 Dart 初始化步骤。

`NATIVE_UI_READY` 和 `BEGIN 1/77` 能证明原生界面及 Probe 加载阶段已开始；
`RUNNER_APPLICATION_START`、`RUNNER_DELEGATE_INIT`、`FLUTTER_FIRST_FRAME` 用于缩小 Flutter 启动阶段。
日志在每条关键记录后 `fsync`。进程级崩溃仍会关闭整个应用，但下次启动只进入原生界面，
可导出已落盘的记录。日志文件创建失败或原生入口自身崩溃仍可能导致无日志。

Native Trace 改变了应用标识、数据容器、签名和启动时序，默认不添加原应用的特殊 entitlements。
它在原生导航界面中调用 Runner 代理并创建原 Main storyboard，未复刻原应用完整的 Scene 生命周期。
它能帮助定位，不是对原崩溃环境的完全复刻。若 Trace 正常而原应用仍崩溃，
应继续对照这些差异，不能直接把 Trace 当作正式修复版。
