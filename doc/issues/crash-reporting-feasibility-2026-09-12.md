# Host 崩溃与日志上报可行性

日期：2026-09-12

## 目标

减少用户逐份导出 `art3m1s.log` 的成本，同时保留：

- Dart 未捕获异常；
- Rust/runtime 日志和异常；
- Android/iOS 原生崩溃；
- 用户主动上报；
- 可控的隐私和网络开关。

## 当前 Host 日志链

当前实现集中在 `lib/services/logger.dart`：

- 内存 ring buffer；
- 当前 runtime session 日志；
- 500ms 批量写入 `Documents/art3m1s.log`；
- 用户手动导出为 `art3m1s_<timestamp>.log`。

Rust 日志经 FFI callback 进入同一 Dart logger。`StartupDiagnostics` 只记录
iOS 原生启动阶段，不能替代通用崩溃上报。

因此当前缺口是：

- 进程被 native crash 终止前，Dart 日志可能来不及落盘或上传；
- 用户必须自己操作导出和发送；
- Android/iOS/macOS/Windows/Linux 没有统一远端标识；
- 日志中可能包含游戏绝对路径、存档名和脚本文本。

## SDK 可行性

### Bugly

可用的 Flutter 社区插件：`flutter_bugly`。

- 最新版本：`1.1.1`；
- 发布时间：2026-01-08；
- 平台：Android、iOS、OpenHarmony；
- 不覆盖 macOS、Windows、Linux；
- `bugly` 包已 discontinued；
- `bugly_crash` 最后版本停留在 2021。

评价：

- 适合国内 Android/iOS 崩溃采集；
- 有原生 crash 采集能力，适合补 Dart 层无法捕获的 native crash；
- 社区 Flutter 插件不是腾讯官方 Flutter SDK，需要审计；
- 需要 App ID、隐私协议初始化时序和平台隐私清单；
- 不适合作为 Host 全平台唯一方案。

### Sentry Flutter

`sentry_flutter` 最新稳定版本为 `9.30.0`，平台声明包含：

- Android；
- iOS；
- macOS；
- Linux；
- Windows；
- Web。

评价：

- 覆盖 Host 当前所有主要平台；
- Dart、原生层、Rust breadcrumb 和 stack trace 的整合路径最完整；
- 支持 SaaS 和自托管；
- 需要选择数据区域和隐私策略；
- 国内网络可达性和合规性需要按部署地区验证。

### Firebase Crashlytics

`firebase_crashlytics` 最新版本为 `5.3.0`，插件平台为：

- Android；
- iOS；
- macOS。

评价：

- 不适合覆盖 Linux/Windows；
- 强依赖 Firebase/Google 服务配置；
- 国内分发和网络可用性需要单独评估。

## 推荐架构

不要让 `Log` 直接依赖 Bugly 或 Sentry。建议增加 provider 无关的 telemetry
边界：

```text
Dart Log / Rust log
  -> TelemetryService
     -> LocalSessionSink
     -> ManualUploadSink
     -> BuglySink (Android/iOS, optional)
     -> SentrySink (all platforms, optional)
```

职责划分：

- `Logger` 负责收集和本地 ring buffer；
- `TelemetryService` 负责 breadcrumb、error、user context 和 flush；
- 原生日志采集由平台 SDK 负责；
- 日志上传必须经过统一 redaction；
- UI 只观察统一状态，不关心具体 SDK。

## 隐私和数据边界

默认策略必须是：

- 默认不上传或仅在用户明确同意后上传；
- 不上传游戏脚本、图片、音频、字体或存档内容；
- 不把游戏绝对路径原样上传；
- 用户目录、用户名、卷标和导入目录做 hash/placeholder；
- 翻译 API key、Token、Cookie、URL query 全部脱敏；
- 只上传当前 runtime session 的尾部 N 条日志；
- 设置最大字节数、去重、采样和退避；
- 提供“关闭崩溃上报”“清除本地诊断数据”“导出日志”三个独立入口；
- 隐私政策必须说明 SDK、数据区域、保存期限和退出方式。

## 实施阶段

### 阶段 1：本地会话报告

- 把当前 `Log` 抽象成多个 sink；
- 增加 session ID、app version、commit、platform、engine kind；
- 增加 `上传诊断日志` 按钮；
- 先接自有 HTTPS endpoint 或对象存储，不接第三方 SDK；
- 生成 report ID 和本地待上传状态。

验收：

- 手动导出行为不变；
- 上传失败不阻塞 UI；
- 日志有大小上限和重试退避；
- 脱敏规则有单元测试。

### 阶段 2：Dart/Sentry 或自有上报

二选一：

- 引入 `sentry_flutter`，覆盖全平台；
- 使用自建 endpoint，不依赖第三方 SDK。

验收：

- `FlutterError.onError`；
- `PlatformDispatcher.instance.onError`；
- `runZonedGuarded`；
- runtime session 日志作为 breadcrumbs；
- release 可以关闭 debug 采样。

### 阶段 3：移动端 Bugly

仅在明确需要国内 Android/iOS crash 后台时启用：

- Android/iOS native 初始化；
- 与现有 logger breadcrumb 对接；
- iOS privacy manifest / Android manifest 合规；
- 隐私同意前不初始化；
- macOS/Windows/Linux 保持 Sentry 或本地上传。

## 建议

短期最稳妥：

1. 先做 provider 无关的诊断上报接口；
2. 先实现本地日志聚合和自有 endpoint 上传；
3. 再选 Sentry 做全平台崩溃收集；
4. 如果发行主战场是国内 Android/iOS，再增加 Bugly 作为可选 sink。

不建议：

- 直接把 `flutter_bugly` 写进全局 `Log`；
- 五种平台分别维护互不兼容的日志上传；
- 默认静默上传游戏路径和用户文本；
- 依赖 2021 年停更的 Bugly 社区包。

