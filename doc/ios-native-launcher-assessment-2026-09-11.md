# iOS 原生启动入口

## 当前状态

2026-09-11：按用户要求，所有 iOS 构建长期统一使用原生入口，包括 Debug、Profile、Release、
真机、模拟器及发布归档；该路径直接配置在 Runner target，不依赖单独测试开关。
iOS 14.5 的 Mpv 链接修复保留。iOS 17.3 注入设备的白屏根因仍未被证明；
这次选择将已成功的 Native Trace 启动流程用于生产项目，而不是继续分发定位探针。
最终 IPA 仍需原设备验收；模拟器成功不能代替越狱环境验证。

## 与成功 Trace 的对应关系

| 启动阶段 | 已成功的 Native Trace | 当前生产入口 |
| --- | --- | --- |
| 进程初始链接 | 仅系统库 | 仅系统库，构建脚本强制检查 |
| 原生窗口 | UIApplication + UIWindow，无 Scene 配置 | 相同 |
| 框架加载 | 系统库在先，应用框架按依赖排序，主队列逐项 dlopen | 相同；共同依赖沿用成功包的顺序 |
| 符号可见性 | RTLD_LAZY + RTLD_GLOBAL，句柄不关闭 | 相同 |
| Flutter 启动 | 交给原 FlutterAppDelegate，Main storyboard 创建隐式引擎 | 相同 |
| 首帧呈现 | UINavigationController push Flutter | 相同，隐藏原生导航栏 |
| 后续页面 | 保留 Probe 导航页 | 首帧与导航转场完成后交给全屏 Flutter 根控制器 |

明确的生产化差异：

- 自动启动，不需要点击 Play；按用户要求移除每步 150 ms 人工等待。
  因此不能声称所有调度时序与旧 Trace 完全相同。
- Art3m1sRuntime.dylib 由源码和链接器正常生成，取代转换后的 RunnerPayload 和调试桥。
  新二进制有自己的 UUID/dSYM，不修改 Mach-O 类型、不安装 Flutter 私有方法 hook。
- 保留正式 bundle ID、版本、数据目录、文件共享和设备方向配置。
- 补发注册完成后的插件启动事件，排队的文件打开事件在 Flutter 根页面准备后交付。
- Trace 的导航转场完整结束后，先让旧容器完成 Flutter 页面消失，再由 UIWindow 呈现
  同一个 Flutter 控制器。直接在首帧回调里同步切根曾导致 viewDidDisappear 最后到达，
  Flutter 停在 paused，表现为必须打开控制中心后才能交互。已通过独立 UI 测试修正。
- 框架签名使用与成功 Trace 相同的无额外权限 ad-hoc 方式；不自动使用
  ios/TrollStore.entitlements 中的 platform-application/容器覆盖权限。

加载顺序基线位于 ios/Native/ProbeLoadOrder.json，来自已成功 Trace 的
Runner UUID 2F501818-B219-3B32-823A-473F11C6C223。新增系统依赖在应用框架之前加载，
新增应用库仍按实际依赖排序，运行时最后加载。AVFoundation 的显式链接修复保留。
最终 Profile 清单的 75 个共同加载项与成功 Trace 顺序完全一致，另加 AVFoundation 和
新 Art3m1sRuntime.dylib，替代旧 Trace 的 RunnerPayload/RunnerBridge 两项。
后续增加依赖时必须重新生成清单，不能只编辑一份写死的库列表。

## 构建结构

- ios/Native/main.m：Runner 的唯一应用入口，只引用 UIKit 等系统库。
- ios/Runner/Runtime.m：延迟加载桥、storyboard、启动诊断通道。
- ios/Runner/AppDelegate.swift：原有插件注册、目录访问、共享纹理通道。
  仅移除 @main 并固定 Objective-C 类名；纹理和文件通道代码保持原样。
- tool/ios_native_bootstrap.py：检查系统库入口、嵌入依赖和旧式窗口配置，
  生成 NativeLibraries.plist，并复制 Swift Package 的资源 bundle。
- ios/Podfile 的 post_integrate：pod install 后仍把 Pods 链接放在运行时；
  Runner 负责嵌入 framework，避免 Flutter 被重新接入初始链接链。
- tool/package_ios_native.py：只签名暂存副本，检查 Runner/Runtime 的 dSYM UUID，
  输出 IPA、dSYMs 目录及 SHA-256/UUID 清单。

正常构建入口不变：

```bash
dart run tool/build.dart ios --release --device-only
dart run tool/build.dart ios --profile --device-only
```

仅打包某个指定的 Xcode 真机构建：

```bash
python3 tool/package_ios_native.py \
  build/ios/Profile-iphoneos/Runner.app \
  build/ios/Art3m1s-native-profile.ipa
```

Flutter 3.44.2 的配置生成和 pod install 已验证不会把此项目自动迁移回 Scene。
工具仍提示未来 iOS 将要求 Scene 生命周期支持。该提示是未来 SDK 迁移约束，
不能把这次旧式入口视为永远不需要维护的方案。

## 日志与性能边界

Documents/startup-native.log 只记录当前进程。重新启动时截断，单文件上限 64 KiB。
若上次启动未完成，最多另外保留一份独立的 .previous 失败日志；
重复停留恢复页不会覆盖那次失败记录，不会把多个进程追加在一个日志文件里。

在库加载前写入 Library/Application Support/art3m1s-startup.pending，
Flutter 首帧及窗口交接成功后删除。标记存在时，下次启动停在原生恢复页，
提供重试与分享日志。强退/系统终止也可能留下标记，因此只提示“上次启动未完成”。
如果 dyld 阻塞主线程或进程崩溃，日志分享要等下一次进入原生恢复页。

Profile/Debug 记录每个库的一条加载节点和四项 Dart 初始化的 BEGIN/END。
Release 编译关闭逐库节点和 Dart 正常启动阶段记录，只保留少量原生阶段及失败信息。
不重定向 stdout/stderr，不枚举所有系统映像，不记录每个 MethodChannel 调用或纹理帧。
进入 Flutter 后停止启动日志写入并销毁启动看门狗；没有常驻启动轮询。
原有业务日志 art3m1s.log 的首次写入也会清空旧进程内容，仍保留原来的批量落盘机制。

运行时只有一个 FlutterEngine，沿用原有 texture registry、CVPixelBuffer、IOSurface、
Metal texture 和 FFI 指针路径。原生入口不新增离屏渲染 pass、逐帧拷贝或第二个引擎。
启动文件 I/O、dlopen 和窗口交接有一次性成本；没有在目标越狱设备上完成帧率、
内存或能耗基准测试，因此不承诺性能数值完全不变。

## 已完成的本地验证

- Profile 和 Release 真机构建、Debug 模拟器构建；主可执行文件不链接 Flutter/业务库。
- Release 原生二进制不含逐库 LOAD 日志和正常 DART 阶段日志分支；失败信息仍保留。
- 清单生成的六项测试：缺失依赖、非系统入口、强弱链接、依赖顺序、资源 bundle、dyld 输出解析。
- 独立 XCUITest 测试程序启动正式 bundle ID，避免把测试框架注入被测入口：
  冷启动后立即点击设置、后台返回、横竖屏切换、再次冷启动。
- 曾在模拟器触发库签名失败，验证原生失败页、下次启动恢复页及重试进入 Flutter。
- 本机 Debug 首次记录约 2 秒到首帧，仅作为功能验证，不代表真机冷启动基准。

本次模拟器验证使用之前已有的 Core/PFS/ANGLE 模拟器二进制，
因为工作区当前 XCFramework 仅有真机切片；没有为此改动真机 Rust 构建结果。

自动验证命令：

```bash
python3 -m unittest discover -s tool -p test_ios_native_bootstrap.py -v
ruby tool/ios_native_tests/create_project.rb build/ios/native-ui-tests
xcodebuild -project build/ios/native-ui-tests/NativeStartupTests.xcodeproj \
  -scheme NativeStartupTests -destination 'platform=iOS Simulator,id=<UDID>' \
  -parallel-testing-enabled NO test
```

先在模拟器安装并签名 Runner.app。NativeStartupTests-Runner 是独立测试程序，
不会进入 IPA；测试完成可从模拟器卸载。

## 真机交付验收

请测试者覆盖安装一次，检查无需控制中心/任务切换即可操作，并连续启动两次。
同次测试顺便验证现有游戏目录和存档、启动游戏与画面声音、后台返回和旋转。
这些路径涉及原数据与实际 GPU/注入环境，本地模拟器不能替代。

## 本次交付

- 文件：Downloads/Art3m1s-1.3.0-native-profile-20260911.ipa，约 33 MiB。
- 同名 .dSYMs 目录保存 Runner 和 Art3m1sRuntime 的匹配符号；同名 .json 保存加载清单。
- IPA SHA-256：86e7a5e446dd98cb308cdb77343808fc8954c429034581853fee9fbb8d6ef04d。
- Runner UUID：6E99A7C3-3951-3170-B9D8-507878059F91。
- Runtime UUID：53B57055-888D-3B5D-B3F1-323F3D37CA9E。
- 保留正式 moe.alphaly.art3m1s 标识；完成签名深度验证，包内没有 XCTest 程序。
- 独立 UI 测试程序已从模拟器卸载。用户随后要求先提交至 Host main；真机反馈仍待确认。
