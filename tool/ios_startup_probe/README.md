# Art3m1s iOS 启动诊断工具

此工具用于调查 iOS 14.5 / TrollStore 上的启动闪退，不是修复版应用。
它在独立原生界面中逐项加载已有 Art3m1s 构建的动态库，保存加载前后的日志。
不会启动 Flutter engine、Dart 或 Runner 的静态插件注册流程。

截至 2026-09-11，原问题设备已完成 Lazy 的全部 75 步，27 个嵌入库均加载成功；
Now 尚待真机测试。完整证据和限制见[调查报告](../../doc/ios14-startup-crash-2026-09-10.md)。

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
