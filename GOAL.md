# 引擎平台适配与宿主完整性

## 当前阶段：KRKR 与 Siglus 平台适配

已完成跨平台源码与构建接线；平台运行验证的范围见下文。

- Siglus Flutter 宿主开放 Windows、Linux、Android 与旧 iOS 入口；统一加载各平台 core，补齐 Android 原生音频上下文。
- 新增 SwiftUI iOS Siglus 播放器，接入导入、输入、Metal 共享表面、RGBA 回退、音量、暂停与退出。
- Siglus 使用 core 的原生音频设备输出；设备回调只消费有界 PCM 队列，VM 与 GPU 保持在宿主线程。
- KRKR 在各平台使用 SDL 原生音频输出，移除 Flutter/SwiftUI 的假消费时钟，实际转发音量和暂停；补齐 Android SDL JNI 初始化。
- 修正异步初始化和纹理创建期间的关闭竞态，Siglus 暂停时释放输入，并限制多点触摸对单指 VM 的干扰。
- 所有构建目标转发 `--krkr` / `--siglus`；修正 KRKR Linux triplet、Linux/Android FFmpeg 链接、Android libc++ 打包及动态依赖复制。
- 更新 Rust 许可证导出，覆盖可选依赖与源码文件的独立许可；增加 Windows/Linux 原生引擎 CI，现有 Android/Apple 构建启用 Siglus。

### 当前验证

- Flutter 静态检查通过；常规单元测试 181 项通过，后续宿主与构建局部改动的相关测试再次通过。
- Rust FFI、音频队列及新增 ABI 契约测试 18 项通过，不依赖游戏或音频设备。
- macOS core 动态库成功构建，Dart 从真实库加载两种引擎及音频控制 ABI 的显式验证通过。
- KRKR 完整上游原生库在 macOS 编译、链接成功。
- Siglus iOS 模拟器 core 编译、链接成功；SwiftUI 使用该新 core 的 Debug 模拟器不签名构建成功。该次 core 使用纯 Rust 解码路径。
- SwiftUI iOS 类型检查、原生合成输入服务测试、Xcode 工程及 shell 脚本检查通过。

### 待运行验证与保留限制

- 本机缺少 Android SDK/NDK，未执行 Android APK/Kotlin 构建；Windows/Linux 未在本机编译或运行。已配置的 CI 尚未运行，需配套发布修改后的 core。
- 尚未运行真实游戏、真机音频设备、前后台切换及视频格式回归；显式验证入口见 `tool/integration_tests/README.md`。
- KRKR 仍使用游戏自身的 savedata，独立存档根目录仍待上游接入；每个进程只允许一次 KRKR 引擎初始化。
- Siglus 的 H.264 UCI 视频需要目标平台 FFmpeg；非 Apple 默认构建不包含该解码能力。

## 前一阶段：宿主完整性与鲁棒性检查

已完成 Flutter、平台入口与 SwiftUI iOS 宿主的源码检查，以及已确认缺陷的修复。

- 补齐两套 Artemis 宿主的脚本 HTTP 请求、取消、超时和结果回填，隔离过期响应。
- SwiftUI 快捷启动实际打开播放器；编辑配置原子保存到 manifest，并保留最新游玩时间。
- 扫描资料库改为增量合并，保留游戏身份、封面、自定义配置和游玩记录；同名目录独立导入，失败复制不会留下可扫描的半成品。
- 兼容旧资料库缺失字段、日期格式与存档 ID；单条损坏记录不再丢弃整库，原始数据保存在恢复键中。容器迁移保留 Games 内的相对路径与正确的 PFS sidecar 路径。
- 收紧托管删除与游戏文件读取的路径边界，阻止目录穿越、外部符号链接和误删保留条目；目录扫描跳过链接循环和不可读子目录。
- 修复播放器异步初始化、设置加载及媒体解码结束后的关闭竞态；翻译任务随会话取消，缓存按服务和语言隔离并串行写入。
- 补齐 Flutter RFVP 的 F32 PCM 转换，处理越幅和非有限样本；补充网络正文读取超时与封面响应大小限制。
- 原生翻译提供商切换同步默认接口和模型；移除未接入的崩溃上报开关，只向 Artemis 展示其项目补丁设置。Siglus 条目保留正确引擎身份。
- 将真实游戏与外部音频验证移到独立集成目录，补齐显式运行说明；新增的原生合成输入检查已接入 Apple CI。

## 验证结果

- `flutter analyze --no-pub`：无诊断。
- `flutter test --no-pub`：179 项全部通过。
- `bash tool/native_host_tests/run.sh`：通过，覆盖导入冲突、重复扫描、旧数据恢复、路径边界、关闭翻译和 HTTP 接线。
- 完整 SwiftUI iOS 源码的 iOS 16 类型检查：通过。
- SwiftUI Debug 模拟器不签名构建：成功。
- Xcode 工程格式与 Git 差异检查：通过。

## 平台能力边界与后续验证

- SwiftUI 暂无在线崩溃采集和上传链路，目前提供本地日志导出。
- 尚未运行真实游戏的真机回归。后续需验证实际引擎版本下的音视频、HTTP 脚本、前后台切换和大目录导入；显式集成验证入口见 `tool/integration_tests/README.md`。
