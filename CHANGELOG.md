# Changelog

本文档记录 Art3m1s Flutter 前端的重要变更。

## [1.1.0-0.2.0c] - 2026-07-27

### 新增

- 新增 macOS、iOS、Windows、Linux 和 Android 的平台化应用界面。
- 新增 macOS 沉浸式标题栏、原生应用菜单、文件/视图/窗口菜单和快捷键。
- 新增 headless caption probe 与 VNDB 标题/封面自动补全。
- 新增本地 JSON/JSONL/TSV 翻译补丁。
- 新增 OpenAI、Anthropic、DeepL、Google、百度和有道在线翻译服务。
- 新增异步翻译队列、并发限制、任务去重、项目缓存和 Ruby 上下文。
- 新增每个项目独立的翻译开关，并兼容旧资料库数据。
- 新增正式品牌图以及 Android、iOS、macOS、Windows AppIcon。
- 新增 `AppInfo` 统一版本信息，并支持显示构建对应的 Git 短提交号。
- 新增 `tool/run.sh`，自动向 Flutter 注入完整预发布版本和提交号。

### 变更

- 按目标平台选择 macOS、Cupertino、Fluent 或 Material/Yaru 应用外壳。
- 翻译请求改为非阻塞异步回填，避免网络请求卡住剧情。
- 日志导出改为当前 runtime 会话，而不是直接导出共享调试浮窗缓冲区。
- 重做游戏内悬浮控制面板，加入明确的开关状态和更紧凑的布局。
- 统一 macOS 明暗主题图标颜色和标准蓝强调色。
- 关于页面与各平台侧栏改为从 `pubspec`/构建参数读取版本，不再硬编码 `1.0.0`。

### 修复

- 修复调试浮窗关闭后切换场景再次显示的问题。
- 修复调试日志使用比例字体导致列与数值难以对齐的问题。
- 修复 macOS 深色模式下返回、复制和圆形按钮图标对比度不足的问题。
- 修复各平台关于页面版本与实际构建版本不一致的问题。
- 修复旧翻译设置与旧项目条目缺少新字段时无法正常读取的问题。

### 已知问题

- `widget_test.dart` 在非 macOS 测试平台创建 macOS `servicesSubmenu` 时失败；实际
  macOS 菜单不受影响。
- 帧显示仍使用 CPU RGBA buffer 到 `ui.Image` 的复制路径。
- 部分引擎平台事件仍等待对应 target 的宿主实现。
- 移动端导入大型游戏需要额外的沙箱复制空间。

## [1.0.0-0.1.0c] - 2026-07-26

- 首个 Flutter 前端版本。
- 提供基础游戏资料库、PFS/目录资源读取、Rust core FFI、离屏画面显示和存档接入。
