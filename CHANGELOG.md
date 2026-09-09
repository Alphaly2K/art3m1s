# Changelog

本文档记录 Art3m1s Flutter 前端的重要变更。

## [1.3.0] - 2026-09-09

### 变更

- 项目许可证由 AGPL-3.0 更换为 MPL-2.0（文件级 copyleft，兼容 App Store 分发）。
- 资料库、游戏编辑和关于页按平台改用更接近原生的样式；封面与标题合并到同一编辑项。
- Apple 平台默认使用原生 Metal；Android 默认仍为 ANGLE / OpenGL ES，原生 Vulkan 仅作实验选项。
- 音频播放统一走 libmpv；画面优先提交系统共享纹理，必要时回退 RGBA。

### 新增

- 可停靠到侧边的平台原生游戏内 HUD，桌面端不再显示虚拟键盘按钮。
- Android 可在 Material Design 与 Miuix 之间切换主题；底部导航为资料库 / 设置 / 关于。
- 游戏 Manifest（`art3m1s.json`）支持一键导入配置、翻译、输入门控、上报机种和 Eluna 开关。
- 输入门控可屏蔽特定键鼠/触摸，避免部分移动端移植被引擎默认键盘行为带偏。
- 移动端双指拖动映射为 Artemis 滚轮键；可启用相对移动触摸板。
- 渲染输出目标：原始分辨率、跟随显示器、固定 1.5× / 2× 或自定义分辨率，供 MetalFX Spatial 使用。
- 翻译缺字形时可安装运行时覆盖字体；每个游戏可独立开关实验性 Eluna E-Mote。
- Android 通过 SAF 将外部解包目录复制进应用存储后再导入。

### 修复

- 修复 Android 通过 SAF 导入解包游戏过慢且没有进度提示的问题。
- 修复 FPS / Profiler 在大 R 角和刘海屏上被裁切的问题。
- 修复 iOS 卡片深色模式、缺少边框，以及二级页面未隐藏底部导航栏、Tab 贴边的问题。
- 修复 Miuix 添加菜单和游戏设置行挤在一起、封面按钮缺少间距的问题。
- 修复双指滚动与指针输入互相抢事件、右键在松手前误触发的问题。
- 修复触摸配置清单迁移后指针失效的问题。
- 修复桌面滚轮和移动端双指滚动键码错误，以及同帧滚轮脉冲丢失的问题。
- 语言表补充识别 `["game_title"]`，避免另一类 init 模板导入时只能落到目录名。
- 修复 macOS 游戏编辑弹窗过挤，以及桌面端 HUD 越出安全区的问题。

### 升级说明

- 本版本应与 `art3m1s-core 0.4.0` 配套使用。
- 已保存的图形后端选择会保留；新安装的 Android 默认仍是 OpenGL ES。

## [1.2.0] - 2026-09-01

首个正式发布版本

### 新增

- 新增移动端侧 ASTC 纹理压缩支持。
- 新增 DXT5 纹理压缩支持。
- 新增静止帧跳过重新渲染机制。
- 新增脏区渲染更新机制。
- 调试模式新增 Profiler 功能。
- 宿主侧新增文件请求缓存。
- 新增 libmpv 解码器预热以加速视频解码播放。

### 变更

- 将原先的音频播放路径统一为libmpv。
- 将原先 Darwin 侧的 ANGLE 实现由 MetalANGLE 替换为 Google 官方的 Metal 库。
- 将 iOS 的 targetSdk 版本提升到 iOS13。
- 移除了在游戏界面的左滑退出手势。

### 修复

- 修复了 emote 播放计时器和游戏渲染时序不同步的问题。
- 修复了音频播放内存泄漏的问题。
- 修复了在线翻译 OpenAI API 调用路径的一系列问题。

### 升级说明

- 本版本应与 `art3m1s-core 0.3.0` 配套使用。

## [1.1.2-0.2.2c] - 2026-07-31

### 新增

- 新增移动端相对移动触摸板，支持轻点单击、长按拖动、舞台边界约束和项目内快捷开关。
- 每个游戏可以独立选择本地翻译对照文件，不再共用一个全局补丁路径。
- 在线翻译缓存改用 Protobuf 二进制格式，并提交 schema 与生成代码。
- iOS 构建脚本支持 arm64 真机/Simulator XCFramework，也可通过 `--device-only` 仅构建真机。

### 变更

- 存档、翻译缓存和封面统一存放到各平台的应用数据根目录，并自动迁移已知旧目录。
- Artemis `*_a` 引导段与 `*_b` 循环段 BGM 改用原生无缝播放列表，消除段间静音。
- iOS core framework 的版本元数据改为读取对应 crate 的 `Cargo.toml`。

### 修复

- 修复 macOS Release 从 Finder 启动时找不到 bundle 内 PFS library，并补齐 ANGLE runtime。
- 修复 macOS App Sandbox 阻止已导入的外部游戏目录继续访问。
- 修复触摸板光标阴影不随主体移动、残留黑色印记以及指针方向不自然的问题。
- 修复 iOS 输入对话框提交时过早释放 `TextEditingController` 触发 Flutter assert。
- 修复翻译设置仍把对照文件放在全局设置，以及项目编辑后路径没有正确持久化的问题。
- 修复非 macOS 测试环境构建 macOS shell 时无条件创建系统菜单项导致的 Flutter 异常。

### 升级说明

- 旧 JSON 在线翻译缓存不会迁移；首次运行会按需生成新的 `.pb` 缓存。
- 本版本应与 `art3m1s-core 0.2.2` 配套使用。

## [1.1.1-0.2.1c] - 2026-07-27

### 新增

- 新增每个项目独立的环境补丁开关；headless 标题探测会安全启用补丁。
- 新增 Shift_JIS/UTF-8 项目字符集探测，并按字符集读取 PFS 路径与 table。
- 新增直接扫描 table 中 `gametitle` 的快速标题探测，保留 headless runtime 回退。
- 新增同一目录多个基础 PFS 的自动发现和逐个导入。
- 新增 Android JNI bridge 源码与 Apple 平台 CocoaPods 配置。

### 变更

- 游戏条目改用稳定项目 ID 映射目录、具体 PFS、存档、封面和设置；显示名称与用户的
  文件夹名称保持不变，并自动迁移旧资料库。
- PFS 游戏条目现在绑定具体基础归档，不再把整个父目录视为单个游戏。
- iOS 原生导入与资料库管理流程扩充为 security-scoped 文件复制。
- macOS 应用构建同时打包 `libart3m1s_core.dylib` 和 `libpfs_upk.dylib`。

### 修复

- 修复多个 `root.pfs` 因文件名相同而共享 `system.dat`、存档、封面和设置的问题。
- 修复选择 PFS 后临时文件失效，以及移动端目录枚举/整文件缓冲引发的导入失败。
- 修复脚本隐藏鼠标后宿主光标状态未能正确恢复的问题。
- 修复 macOS Release 从 Finder 启动时找不到 bundle 内 PFS dylib、遗漏 ANGLE
  EGL/GLES library，以及 App Sandbox 阻止旧资料库继续访问外部游戏目录的问题。
- 配合 core 0.2.1 修复大型加密 PFS 中 OTF 等资源跨 chunk 解密损坏。

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
