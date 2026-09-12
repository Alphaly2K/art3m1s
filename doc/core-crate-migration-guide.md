# Art3m1s Core 公共 Crate 迁移实施指南

版本：2026-09-12  
适用范围：`art3m1s-core` 向 `art3m1s-log`、`art3m1s-media`、`art3m1s-render`
及可选 `art3m1s-rfvp` 的迁移  
目标读者：后续执行迁移的 Codex/人工 agent

## 1. 目标与范围

把 core 中已经抽出的公共能力逐步切换到独立 crate，同时保持以下边界不变：

- FFI 符号、结构体布局、枚举整数和事件缓冲区布局不变。
- GL、Metal、Vulkan 的渲染结果、视频路径、截图和 surface 行为不回退。
- Host 继续只依赖 engine 总抽象，不直接依赖某个引擎的内部类型。
- RFVP 依赖只允许通过 `art3m1s-rfvp` 和独立 `rfvp_api` 边界进入 core；
  core 主体不得直接引用 RFVP 类型。

本指南覆盖：

- 日志边界迁移到 `art3m1s-log`
- 媒体类型和解码边界迁移到 `art3m1s-media`
- DrawList、GPU backend、external resource 和 shader 边界迁移到 `art3m1s-render`
- 可选 RFVP engine adapter 接入 `art3m1s-rfvp`

本指南不覆盖：

- FFI 重构
- profiler 是否独立成 crate 的最终决策
- gameplay、存档、转场和输入行为修复

## 2. 硬性约束

以下约束优先级高于“尽快删除重复代码”：

1. 当前 FFI 正在由其他 agent 重构。迁移 agent 默认不得修改
   `src/ffi.rs`、`src/ffi_api.rs` 或任何导出 ABI 定义。
2. 如果日志宏或其他迁移必须修改 FFI 文件，任务应停在边界处并报告，
   不要私自改 FFI。
3. 公共 crate 不得反向依赖 core、FFI、Dart callback、wgpu surface 或宿主设备。
4. 对象跨边界使用不透明句柄。
5. 像素、顶点、uniform、序列化和 blob 数据使用裸指针加长度或定长 POD。
6. 先建立 re-export 或适配层，再删除 core 旧实现。禁止一个提交里同时
   “切调用方”和“删除旧实现”。
7. 每个提交只迁移一个边界，不混入 gameplay 修复或无关格式化。

## 3. 允许的依赖方向

```text
art3m1s-core
  -> art3m1s-log
  -> art3m1s-render
  -> art3m1s-media

Host / engine adapter
  -> art3m1s-rfvp
  -> art3m1s-render
  -> art3m1s-log

art3m1s-render
  -> art3m1s-log（最终边界；过渡期可继续直接使用 log facade）
```

明确禁止：

```text
art3m1s-render -> art3m1s-core
art3m1s-render -> Dart FFI
art3m1s-log    -> GPU / 解释器 / 宿主文件系统
art3m1s-media  -> GPU / FFI / 宿主音频设备
art3m1s-core   -> rfvp（必须经由 art3m1s-rfvp 和 src/ffi/rfvp_api.rs）
```

## 4. 当前状态

| 模块 | 当前状态 | 迁移动作 |
| --- | --- | --- |
| `art3m1s-log` | 独立 crate 已可用，包含 `Level`、`Record`、`Sink`、`Filter`、`Logger`、全局安装和标准 `log` 转发宏 | 先接 facade 和 sink，FFI 宏迁移需等待 FFI 冻结结束 |
| `art3m1s-media` | 已被 core 部分接入，FFmpeg 可选 feature 可独立测试 | 继续收口 `src/video` 和 runtime media session |
| `art3m1s-render` | 已包含 draw、backend、external、post-process、shader 和 GL/Metal/Vulkan 可选实现 | 先迁纯类型，再按 GL、Metal、Vulkan 顺序替换 backend |
| `art3m1s-rfvp` | 独立 adapter，不依赖 core；已提供 `host-runtime` 和真实 RFVP 游戏 smoke | 保持引擎逻辑在 adapter，core 只保留独立的 `rfvp_api` ABI 边界 |
| `src/profiler.rs` | 仍是 core 私有实现 | 暂不塞进 `art3m1s-log`；后续可单独抽 `art3m1s-profiler` |

已验证基线：

| 验证 | 结果 |
| --- | --- |
| `art3m1s-log` 单测 | 5/5 |
| `art3m1s-media` 全 feature 单测 | 6/6，含 FFmpeg 解码 |
| `art3m1s-render` 全 feature 单测 | 44/44，含 GL/Metal/YUV420P |
| `art3m1s-rfvp` 全 feature 单测 | 7/7 |
| `art3m1s-rfvp` Clippy | `-D warnings` 通过 |
| RFVP ABI 单测 | `src/ffi/rfvp_api.rs` 2/2 |
| RFVP 移动端交叉检查 | `aarch64-apple-ios`、`aarch64-linux-android` 通过 |
| RFVP 真实游戏 | `/Users/alphaly/847` 运行 1800 帧，进入标题菜单 |

## 5. 迁移总顺序

按下面顺序执行，每一步独立提交：

1. 依赖与 feature 接线
2. `art3m1s-log` facade 和 sink 边界
3. `art3m1s-render` 纯类型和 public trait
4. GL backend
5. Metal backend
6. Vulkan backend
7. `art3m1s-media` 收口
8. 可选 `art3m1s-rfvp` 接线
9. 删除 core 重复模块

`runtime` 和 `ffi` 最后迁移。不要先从这两个目录开始全局替换。

## 6. 阶段一：依赖与 feature 接线

### 目标

只增加依赖和 feature 转发，不改变任何调用方。

### 根 `Cargo.toml`

```toml
[dependencies]
art3m1s-log = { path = "crates/art3m1s-log" }
art3m1s-render = { path = "crates/art3m1s-render" }
```

在现有 feature 数组末尾追加上共享 feature，不要替换 core 当前仍需要的
`dep:glow`、objc2、ash、shaderc 等依赖：

```text
gl-backend      追加 art3m1s-render/gl
metal-backend   追加 art3m1s-render/metal
vulkan-backend  追加 art3m1s-render/vulkan
runtime-shader  追加 art3m1s-render/runtime-shader
ffmpeg           追加 art3m1s-media/ffmpeg
```

保留 core 现有的可选依赖，直到对应 backend 真正迁移完成。不要把
`glow`、Metal/objc2 或 Vulkan/ash 从根清单提前删除。

### 验收

```sh
cargo check --locked --offline
cargo check --locked --offline --no-default-features
cargo check --locked --offline --no-default-features --features gl-backend
cargo check --locked --offline --no-default-features --features metal-backend
cargo check --locked --offline --no-default-features --features vulkan-backend
```

### 提交边界

只提交 `Cargo.toml` 和必要的 `Cargo.lock` 变化。不要在这个提交里改代码。

## 7. 阶段二：art3m1s-log

### 目标

- `art3m1s-log` 只负责记录、过滤和分发。
- core 保留对 FFI 事件格式的所有权。
- 同一进程只安装一次 global logger。
- 不修改 `src/ffi.rs` 里的宏。

### 推荐实现

新增 core 内部模块，例如 `src/logging.rs`：

```rust
use std::sync::Arc;

use art3m1s_log::{Logger, Sink};

pub fn install_once(sink: Arc<dyn Sink>) -> Result<(), art3m1s_log::InstallError> {
    let logger = Arc::new(Logger::with_sink(sink));
    art3m1s_log::install_global(logger)
}
```

具体的 Dart callback、`E/W/I/D/T` 等级编码和事件缓冲区继续留在 core 的
host events/FFI 层。

### FFI 边界

当前 `core_info!`、`core_warn!`、`core_debug!`、`core_error!` 定义在
`src/ffi.rs`。在 FFI 重构未完成前：

- 不修改这些宏。
- 不让 `art3m1s-log` 知道 Dart ABI。
- 可以先用 core 内部 bridge 接收 sink 和过滤配置。

FFI 冻结结束后，再由 FFI 所有者把宏体改成标准 `log` 或
`art3m1s-log` 的薄包装。

### profiler

不要把 `src/profiler.rs` 直接塞进 `art3m1s-log`。profiler 的边界应保持为：

- `art3m1s-profiler`：采样、聚合、快照和 JSON
- `art3m1s-log`：日志记录和过滤
- core：GPU、解释器和媒体计时点

在 profiler 独立前，必须明确标记它仍是 core 私有实现。

### 验收

```sh
cargo test --manifest-path crates/art3m1s-log/Cargo.toml --locked --offline
cargo test --locked --offline
```

还必须验证 Flutter 日志等级、文本格式、sink 替换和重复安装保护没有变化。

## 8. 阶段三：art3m1s-render 纯类型

### 目标

先统一下列公共类型，避免 core 与 crate 各有一套同名类型：

- `DrawList`、`DrawCommand`、`DrawMesh`
- `TextureId`、`TextureInfo`、`TextureProvider`
- `FrameTarget`、`Extent2D`、`TextureDesc`
- `TextureData`、`TextureUpdate`、`RenderTarget`
- `ExternalImage`、`ExternalTextureHandle`、`VideoSurfaceHandle`
- `RenderRegion`、post-process 描述
- HLSL/runtime shader ABI

### 推荐策略

过渡期在 core 旧模块内做 re-export：

```rust
pub use art3m1s_render::draw::*;
pub use art3m1s_render::external::*;
pub use art3m1s_render::hlsl::*;
pub use art3m1s_render::post_process::*;
pub use art3m1s_render::types::*;
```

此时不要从 core 旧路径删除模块，先保证旧引用仍然编译。调用方稳定后再逐步把
import 改成 `art3m1s_render::...`。

### core 专属策略

以下内容继续留在 core：

- `BackendSelection`
- `create_backend(selection, width, height)`
- 旧整数到 backend 的映射
- macOS、iOS、Android 的默认 backend 选择

它们属于产品和平台策略，不属于公共 render crate。

### image 版本

core 当前使用 `image 0.25`，`art3m1s-render` 当前使用 `image 0.24.9`。
迁移时不要让 `image::DynamicImage` 等第三方类型直接穿过 core/crate 边界。
边界应传递 `TextureData` 或裸数据，避免类型不匹配。

### 验收

```sh
cargo test --manifest-path crates/art3m1s-render/Cargo.toml \
  --locked --offline --all-targets --all-features
cargo check --locked --offline
cargo test --locked --offline
```

## 9. 阶段四：GL backend

### 目标

- 让 core 使用 `art3m1s_render::backend::gl::GlBackend`。
- 删除 core 内重复的 GL 实现前，先保留旧路径一版作为对照。
- 保留 `glow`、CGL、ANGLE、纹理上传、damage 和截图行为。

### 迁移顺序

1. 在 backend factory 中先创建共享 `GlBackend`。
2. 让 core 的 `GpuBackend` 对象安全地持有或包装共享 backend。
3. 跑 crate GL 测试和 core GL feature。
4. 用真实游戏检查首帧、持续帧、视频、截图和 damage 更新。
5. 最后删除 `src/backend/gl/*` 的重复实现。

### YUV

共享 trait 已包含：

```rust
fn supports_video_yuv420p(&self) -> bool;
fn upload_video_yuv420p(
    &mut self,
    name: &str,
    width: u32,
    height: u32,
    planes: Yuv420pPlanes<'_>,
) -> bool;
```

GL 和 Metal 都实现了 GPU 侧 YUV420P 转换。禁止静默改成 CPU RGBA 上传，
否则 iOS/Android 视频性能和测试基线会变化。

### 验收

```sh
cargo check --locked --offline --no-default-features --features gl-backend
cargo test --locked --offline --no-default-features --features gl-backend
```

至少验证一个 GL 离屏路径和一个真实游戏渲染路径。

## 10. 阶段五：Metal backend

### 目标

- 使用 `art3m1s_render::backend::metal::MetalBackend`。
- 保持 CoreVideo、IOSurface、CAMetalLayer、MetalFX 和截图路径。
- 保留 Metal 的 YUV420P 转换和 damage 行为。

### 迁移顺序

1. 保留 core 的 platform/surface 选择和 factory。
2. 将 backend 实例切换为共享 Metal backend。
3. 逐项跑 crate 的 Metal 测试。
4. 跑 iOS/macOS 真实游戏、视频和 surface 恢复。
5. 最后删除 `src/backend/metal/*` 的重复实现。

### 验收

```sh
cargo check --locked --offline --no-default-features --features metal-backend
cargo test --locked --offline --no-default-features --features metal-backend
```

必须覆盖：

- iOSurface 零拷贝导入
- CoreVideo 像素缓冲导入
- MetalFX present
- GL/Metal 切换后的 surface 重建
- 视频 YUV420P 上传

## 11. 阶段六：Vulkan backend

### 目标

- 使用共享 Vulkan backend。
- 保持 Android 默认 ANGLE/GL 不变。
- 保留 Vulkan scratch buffer、render pass 重用和 present fence 行为。
- Vulkan 仍作为实验性 backend，除非用户明确改变默认策略。

### 验收

```sh
cargo check --locked --offline --no-default-features --features vulkan-backend
cargo test --locked --offline --no-default-features --features vulkan-backend
```

Android 至少覆盖：

- app 启动
- 文本密集场景连续运行
- 切后台与恢复
- surface 重建
- 截图

## 12. 阶段七：art3m1s-media

### 已完成部分

- core 根依赖已接 `art3m1s-media`
- `lib.rs` 已 `pub use art3m1s_media as media`
- `host_files.rs` 已实现 `MediaSource`
- `runtime/media_session.rs` 已使用 `FrameQueue`、`MediaTime` 和
  `FfmpegVideoDecoder`

### 剩余工作

1. `src/video/engine.rs`、`src/video/state.rs` 只保留迁移期逻辑状态。
2. 不再复制媒体装载、时钟和队列类型。
3. runtime 继续负责解码器、PTS 和完成事件。
4. Host 只拥有最终 present 和音频设备。
5. `ffmpeg` feature 继续转发到 `art3m1s-media/ffmpeg`。
6. `art3m1s-media` 不依赖 core、FFI、GPU 或宿主音频设备。

### 验收

```sh
cargo test --manifest-path crates/art3m1s-media/Cargo.toml \
  --locked --offline --all-targets --all-features
cargo check --locked --offline --features ffmpeg
```

必须用真实视频验证：

- PFS 内视频可 seek
- 解码线程停止后无泄漏
- 音频时钟和视频帧同步
- 切后台后不继续占用解码器

## 13. 阶段八：art3m1s-rfvp

`art3m1s-rfvp` 是 RFVP command protocol 到 `art3m1s-render::DrawList` 的
适配层，并可选提供直接驱动 RFVP fork 的 `host-runtime`。

```text
RFVP runtime
    |
    v
art3m1s-rfvp
    |
    v
art3m1s-render::GpuBackend
```

core 通过可选 feature 暴露独立的 RFVP host ABI；当前发布构建默认启用该
feature，但引擎实现不能因此进入 core 主体：

```toml
rfvp-engine = [
  "dep:art3m1s-rfvp",
]
```

发布依赖必须固定 RFVP fork 的仓库和 revision，不能指向本机浮动路径。

### RFVP 边界规则

- runtime 只产出 `ExternalFrame`、音频命令和 hit proxy。
- `ExternalRenderer` 负责 texture upload、DrawList 转换和 backend 提交。
- Host 不接收逐对象 `RfvpDrawCommandV1` 指针。
- Texture、frame、runtime、resource 使用句柄。
- 像素、顶点、payload、effect data 使用指针加长度。
- `Sub`、`Mul`、mesh、clip 和 negative rect 行为由 adapter 测试锁定。
- `src/ffi/rfvp_api.rs` 独立于 `Art3m1sApiV1`；不得把 RFVP 字段塞入现有 ABI 表。
- `engine/` 以外的 Host 代码只能调用跨引擎抽象，不能引用 RFVP 私有类型。

### smoke

```sh
cargo test --manifest-path crates/art3m1s-rfvp/Cargo.toml \
  --locked --offline --all-targets --all-features

cargo run --manifest-path crates/art3m1s-rfvp/Cargo.toml \
  --locked --offline --features winit-smoke \
  --bin rfvp_win95_smoke -- <game-root> /tmp/rfvp.png 180 16
```

2026-09-12 已验证：

- `win95_painter_demo` 首帧 3223 条命令、3 张纹理
- `/Users/alphaly/847` 运行 1800 帧后进入标题菜单
- Logo 阶段稳定为 17 条命令、17 张纹理

## 14. API 映射表

| core 旧路径 | 目标 crate | 备注 |
| --- | --- | --- |
| `src/render_pipeline/draw.rs` | `art3m1s_render::draw` | DrawList 和纹理合同 |
| `src/render_pipeline/post_process.rs` | `art3m1s_render::post_process` | 只迁类型和策略描述 |
| `src/render_pipeline/hlsl.rs` | `art3m1s_render::hlsl` | 保持 shader ABI 和 reflection |
| `src/render_pipeline/shader.rs` | `art3m1s_render::shader` | 内置 shader 源码 |
| `src/backend/types.rs` | `art3m1s_render::types` | 保持整数和 FFI 映射 |
| `src/backend/external.rs` | `art3m1s_render::external` | handle + data 规则 |
| `src/backend/mod.rs` 的公共 trait | `art3m1s_render::backend` | core 只保留 factory 和平台策略 |
| `src/video/engine.rs` 的命名函数 | `art3m1s_render::naming` | 视频层纹理命名 |
| `src/video` 的媒体类型 | `art3m1s_media` | 时钟、队列、解码帧 |
| `core_*!` 日志宏 | `art3m1s_log` / `log` | FFI 冻结结束后再改宏体 |

## 15. 验证矩阵

### 公共 crate

```sh
CARGO_TARGET_DIR=/tmp/art3m1s-log-target cargo test \
  --manifest-path crates/art3m1s-log/Cargo.toml --locked --offline

CARGO_TARGET_DIR=/tmp/art3m1s-media-target cargo test \
  --manifest-path crates/art3m1s-media/Cargo.toml \
  --locked --offline --all-targets --all-features

CARGO_TARGET_DIR=/tmp/art3m1s-render-target cargo test \
  --manifest-path crates/art3m1s-render/Cargo.toml \
  --locked --offline --all-targets --all-features

CARGO_TARGET_DIR=/tmp/art3m1s-rfvp-target cargo test \
  --manifest-path crates/art3m1s-rfvp/Cargo.toml \
  --locked --offline --all-targets --all-features
```

### core feature matrix

```sh
cargo check --locked --offline --no-default-features
cargo check --locked --offline --no-default-features --features gl-backend
cargo check --locked --offline --no-default-features --features metal-backend
cargo check --locked --offline --no-default-features --features vulkan-backend
cargo check --locked --offline --features ffmpeg
cargo test --locked --offline
```

### 真实路径

每个 backend 迁移提交必须至少通过一个真实游戏路径：

- macOS Metal：启动、首帧、持续帧、视频、截图
- GL：离屏测试和真实游戏
- Android：ANGLE/GL 启动和切后台恢复
- Android Vulkan：至少启动并跑文本场景

只通过 `cargo check` 不算 backend 迁移完成。

## 16. 提交拆分

建议提交顺序：

```text
build(core): add shared crate dependencies
refactor(log): bridge core logging to art3m1s-log
refactor(render): reuse art3m1s-render contracts
refactor(gl): consume art3m1s-render GL backend
refactor(metal): consume art3m1s-render Metal backend
refactor(vulkan): consume art3m1s-render Vulkan backend
refactor(media): consume art3m1s-media contracts
docs(rfvp): document optional multi-engine integration
refactor(core): remove duplicated render and media modules
```

每个提交必须：

- 只迁移一个边界。
- 保留旧类型别名或 re-export 一个版本周期。
- 通过对应 crate 单测。
- 通过相关 core feature matrix。
- 至少跑一个真实宿主路径。
- 在提交说明中写清楚性能基线是否改变。

## 17. Agent 交接模板

分派任务时使用以下模板：

```text
目标：
迁移边界：
允许修改：
禁止修改：
基线提交：
完成后的验证命令：
必须保留的 ABI：
真实路径验证：
停止条件：
提交标题：
```

示例：

```text
目标：让 core 消费 art3m1s_render::draw 的 DrawList 和 TextureId
迁移边界：render pure types only
允许修改：Cargo.toml、src/render_pipeline/draw.rs、相关 import
禁止修改：src/ffi.rs、src/ffi_api.rs、backend implementation
基线提交：core master 79b542b
完成后的验证命令：cargo test --locked --offline
必须保留的 ABI：TextureId(u64) 和所有 FFI handle 整数宽度
真实路径验证：Metal 启动到首帧
停止条件：需要修改 FFI 布局或 backend public trait
提交标题：refactor(render): reuse art3m1s-render contracts
```

## 18. 停止条件

遇到下列情况时立即停止当前迁移并报告：

1. 需要改变 FFI 符号、结构体大小、枚举值或 Dart callback 布局。
2. 需要让 `art3m1s-render` 依赖 core 或宿主类型。
3. 需要把 GPU device、surface 或 feature 对象跨 FFI 传递。
4. YUV420P 只能通过 CPU RGBA 转换才能通过编译。
5. GL、Metal 或 Vulkan 的公共 trait 需要不兼容修改。
6. 同一提交必须同时改动两个以上 backend。
7. 真实游戏无法启动，且问题不能在当前边界内独立定位。

## 19. 完成标准

迁移完成必须同时满足：

- core 不再持有与 `art3m1s-render` 重复的公共类型定义。
- `core_info!` 等宏不再拥有独立日志实现，只做薄包装。
- profiler 已独立成 crate，或被明确标记为 core 私有。
- `art3m1s-render` 不反向依赖 core、FFI 或 host。
- FFI 符号、结构体大小和枚举整数保持不变。
- GL、Metal、Vulkan、视频、截图和 surface 恢复通过真实路径验证。
- RFVP 接在 engine adapter 或 Host engine 抽象后面，不进入公共 render crate。
- 每个提交都能独立回滚，不依赖未提交的后续修改。
