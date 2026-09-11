# iOS 17.3 注入环境白屏调查

## 当前结论

用户确认 iOS 14.5 的普通入口 Mpv 链接修正版已能正常启动。同时另一位用户报告，
iOS 17.3 环境中此包及此前几乎所有发布版均白屏卡住，但 Native Trace 能进入 Flutter。
这是另一台设备、另一种表现，不能直接沿用 iOS 14.5 的 dyld 缺失符号解释。

本轮分析的是成功启动的 Trace 日志，没有取得普通入口白屏时的线程栈、生命周期日志或
Dart 错误。因此尚不能确定白屏发生于窗口连接、引擎初始化、Dart 启动还是文件访问，
也不能把用户描述的“卡死”直接认定为主线程死锁。
当前保留已通过 iOS 14.5 复测的链接修正，没有据此修改生产 Scene 或添加启动延时。

## 日志与产物对应

- 原文件：`/Users/alphaly/Downloads/startup-trace (1).log`，1400 行。
- 本地归档：`build/ios/startup-probe/feedback-ios17-20260911/startup-trace.log`。
- SHA-256：`8a98c0b3a062098ff3eb6b172ec6dc3673000893e9c3b03a3a1679f52ab6aa65`。
- 系统自报 iOS 17.3 (21D50)，单一进程 7933；未从日志确认具体硬件型号和越狱工具版本。
- 源 Runner UUID `2F501818-B219-3B32-823A-473F11C6C223`，仍为旧 Profile 的 Native Trace，
  不是本次重新链接的 Runner `72E38409-E4A5-3EBF-A665-2A0BEBACA393`。
- 主入口、桥接、RunnerPayload 和 27 个嵌入框架共 30 个 UUID 全部匹配最终 Native Trace 包。
  UUID 对应产物，不证明设备内存没有被 hook 或修改。

| 事件 | UTC 时间 | 日志行 |
| --- | --- | --- |
| 原生界面就绪 | 11:10:29 | 2 |
| 开始 Lazy 加载 | 11:10:31 | 547 |
| 77 步全部完成 | 11:10:47 | 1347 |
| 开始 Runner 启动 | 11:10:47 | 1349 |
| Flutter createShell 成功 | 11:10:47 | 1358 |
| FileSelectorPlugin 注册结束 | 11:10:47 | 1362 |
| 全部实际插件注册结束 | 11:10:47 | 1373 |
| Flutter 引擎启动返回 | 11:10:47 | 1382 |
| Flutter 首帧 | 11:10:48 | 1399 |
| 主队列 15 秒计时回调 | 11:11:02 | 1400 |

77 个 BEGIN 对应 77 个 OK，无 OPTIONAL MISSING、FAILED、EXCEPTION 或 HOOK_SKIPPED。
六个实际调用的插件注册均返回。五次 MethodChannel 调用都记录了回复，包括
`System.initializationComplete`、`getAll` 和 SystemChrome 设置。
引擎启动至首帧约一秒，逐库加载约十六秒；日志只有秒级时间，且包含人为逐步等待，
不能拿它衡量普通入口的性能。末尾回调说明该时刻主队列能够响应，不证明长期运行已验收。

没有发现明确错误消息。Trace 未记录返回值、所有 Pigeon BasicMessageChannel 或所有 FFI 调用，
不能把某个方法没有出现当成它没执行。首帧与用户目视反馈一致，确认显示了 Flutter 应用。

## 明确存在的注入

| 映像 | 首次记录行 | UUID |
| --- | --- | --- |
| `/usr/lib/systemhook-4DF4D82928EEC24C.dylib` | 5 | `58209FB7-268E-3F92-8948-43E3BD04FA87` |
| `.jbroot-4DF4D82928EEC24C/usr/lib/TweakInject/AppHider.dylib` | 432 | `C5EE31C8-5F56-3239-AC70-0AA033D4D307` |
| `.jbroot-4DF4D82928EEC24C/usr/lib/libellekit.dylib` | 433 | `0F2D1EBC-8236-344F-81FD-D6F99B256C9E` |
| `.jbroot-4DF4D82928EEC24C/usr/lib/TweakInject/TrollPadUI.dylib` | 515 | `0F8F0A41-4F48-30C1-BFD1-DB069FE513E1` |

后三项位于 `/private/var/containers/Bundle/Application/` 下的 jbroot 目录。
这是进程加载注入库的直接证据；不能仅凭路径确定完整越狱产品、版本或是否发生了系统版本伪装。
这些库在成功 Trace 里也存在，因此不能声称其存在必然导致失败。
普通应用标识为 `moe.alphaly.art3m1s`，Trace 为 `moe.alphaly.art3m1s.startuplauncher`，
还可能有按应用过滤、不同配置或类加载时机差异。

核对 [TrollPad 公开源码](https://github.com/khanhduytran0/TrollPad/tree/3a841b3aa26d96df2acbcdb129dcfddf69a62b06)：

- `TrollPadUI.plist` 以 UIKit bundle 为注入条件，没有只针对 Flutter 的过滤。
- `TweakUI.x` 修改键盘 idiom、输入视图布局及 `UIPointerInteraction`，不能描述为直接 hook
  Flutter 或 SceneDelegate 的代码。
- `TweakSB.x` 修改 SpringBoard 多任务、方向和 Scene 请求行为，例如
  `UISApplicationInitializationContext` 的 `supportAppSceneRequests`、`SBApplication` 多任务能力。
  它属于 SpringBoard 进程，不能从应用日志断言该模块已经加载。
- 未取得设备上实际插件文件或版本，也未找到可以与该 AppHider UUID 对应的源码。
  公开 TrollPad 源码仅提供可检查方向，不构成本设备已命中的故障证据。

## 两个入口仍存在的差异

| 项目 | 普通入口修正版 | 成功 Native Trace |
| --- | --- | --- |
| 库加载 | 启动时由 dyld 加载链接依赖 | 原生界面先启动，再逐项全局 dlopen |
| 窗口连接 | Scene manifest、Runner.SceneDelegate、Main storyboard | 原生窗口，手动实例化 Main，导航控制器中显示 Flutter |
| 应用代理 | UIKit 持有原 Runner 代理 | 运行中替换代理，并手动调用启动回调 |
| 应用身份和数据 | 正式 bundle ID 和原数据 | 独立 bundle ID 和独立数据容器 |
| 插件注入环境 | 白屏进程尚无映像记录 | 明确有 systemhook、ElleKit、AppHider、TrollPadUI |
| 诊断包装 | 没有 Trace hook | 包装 Flutter 和插件的若干方法，有额外刷盘和等待 |

Trace 记录了 Scene 方法的 HOOK 安装，但没有 `BEGIN Runner.SceneDelegate scene:willConnectToSession:options:`。
结合桥接源码，确认成功路径没有执行普通 Scene 连接流程。
这使 Scene / 窗口行为成为需要对照的变量，但不证明 FlutterSceneDelegate 有缺陷。
Trace 仍使用隐式 Flutter 引擎；不能把成功解释成已切换显式引擎。

`lib/main.dart` 在 `runApp` 前等待目录创建/迁移、SharedPreferences 和版本信息。
普通包的原数据与 Trace 的独立容器不同，初始化抛错或未完成可能留下空白界面；
当前仅有成功日志，不能排除这一路径，也不应通过删除原数据来测试。

## 下一步

首先请求测试者仅对正式 Art3m1s 关闭 AppHider / TrollPadUI 的进程内注入，再结束进程重开；
保留应用数据和安装包，记录设备型号、实际越狱/Bootstrap 名称及禁用结果。
这一对照无需重新构建，也不要求退出整个越狱。
如成功，应逐一恢复并复测，区分具体插件或组合；成功也不能直接证明需要移除 Scene。

若仍失败，不能据此排除 systemhook 或 SpringBoard 侧改动。
下一份对照可保持已修正 Runner、框架、bundle ID 和数据不变，仅在包副本切换 Scene 与传统
AppDelegate 窗口入口，并对照结果；这是隔离变量的诊断，不能直接作为永久生产修改。
对于仍停留白屏的普通进程，优先采集主线程和其他线程的挂起快照，或普通入口的原生/Dart
初始化节点，区分“没执行到 runApp”和“已运行但没显示”。纯成功 Trace 无法代替这份失败数据。

## 后续实施决定

用户随后要求直接采用成功 Trace 的原生启动路径，且取消每库 150 ms 的人工等待。
Debug、Profile、Release 已统一为系统库原生入口、旧式 UIWindow、延迟加载运行时及
Main storyboard 隐式引擎启动；没有继续沿用 Scene 入口。完整行为差异、日志策略和本地
验证见[原生入口说明](ios-native-launcher-assessment-2026-09-11.md)。

本地发现并修复了首帧后切换根控制器的生命周期问题：画面已显示但 Flutter 停留 paused，
只有进入控制中心或任务切换后才恢复响应。独立 UI 测试已确认修正后冷启动可立即操作。
这属于生产化窗口交接中的问题，不能据此反推那台 iOS 17.3 普通发布版白屏的原始根因。
此次提供 Profile IPA 进行真机验收；用户随后要求先提交至 Host main，所有后续 iOS 构建
均使用该入口。真机测试反馈仍待确认，不把提交动作作为设备验收通过的证据。
