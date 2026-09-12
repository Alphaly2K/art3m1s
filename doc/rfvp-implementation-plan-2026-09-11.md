# RFVP 外部渲染器接入实施计划

日期：2026-09-11

关联文档：

- [接入可行性研究](rfvp-integration-feasibility-2026-09-11.md)
- [RenderHost ABI v1 草案](abi/rfvp_render_host_v1.h)

## 目标

- Host 识别、导入并启动解包后的 FVP 游戏。
- RFVP 负责 HCP/HCB、VM、音频和游戏逻辑。
- `art3m1s-core` 负责 GPU、纹理、合成、readback 和 present。
- Flutter 继续负责资料库、生命周期、输入门控和 HUD。
- Android、iOS、macOS 复用现有 shared texture / native surface。

第一版不支持 PFS 包装的 FVP、加密资源、Host 媒体接管或与 Artemis runtime
同时运行。

## 目标架构

```text
Flutter PlayerScreen
  -> RfvpBridge
  -> art3m1s-core RfvpRuntime
  -> rfvp production runtime
  -> RfvpRenderHostV1 callbacks
  -> RfvpRenderAdapter
  -> GpuBackend
  -> Flutter external texture / native surface
```

关键决策：

- rfvp 生产路径不再拥有 `wgpu::Surface`。
- 独立 rfvp launcher 可以继续使用原 wgpu 实现。
- Flutter 只持有 `art3m1s-core` 的 RFVP handle，不直接管理第二个引擎。
- 外部渲染器落地后，不再需要 iOS PlatformView 或桌面独立窗口方案。

## 仓库与分支

### rfvp

分支：`codex/render-host-abi-v1`

目标：生产渲染与 wgpu 解耦，增加外部 renderer host ABI。

### art3m1s-core

本地 fork：`/Users/alphaly/RustroverProjects/rfvp`

分支：`codex/render-host-abi-v1`

目标：实现 RFVP command 到 `GpuBackend` 的 adapter 和 Host FFI。

### Art3m1s

分支：`codex/rfvp-engine-integration`

目标：增加引擎类型、项目发现、RFVP bridge 和 PlayerScreen 路由。

## 前置重构：独立 `art3m1s-render` crate

### 当前进度

已完成第一阶段的 API-only 迁移：

- `crates/art3m1s-render` 已落入 core 仓库；
- `DrawList` / `DrawCommand`、纹理与原生表面类型、external image、
  post-process、runtime shader 和视频纹理命名已从 core 解耦；
- `GpuBackend` 边界、GL reference backend、Apple Metal backend 和 Vulkan
  backend 已迁入；
- macOS 的 `gl,metal,runtime-shader` 组合测试与严格 clippy 通过；
- Android `aarch64-linux-android` 的 `vulkan` 交叉检查与严格 clippy 通过；
- crate 不依赖 `art3m1s-core`、interpreter、FFI 或 Host 文件系统；
- 无 feature 与 `runtime-shader` 两条构建路径均已通过测试和严格 clippy；
- 新 crate 尚未接入 core 或 RFVP；Vulkan 仍需在 Android 真机补 render smoke。

GL 迁移时已经固定两个注入边界：素材源使用 `AssetSource`，ANGLE 路径使用
`backend::gl::platform::set_angle_path_prefix`。日志改用标准 `log` facade。
下一步是 core 兼容 re-export 和宿主注入桥。它们必须保持现有 FFI callback
签名与注册路径不变，等用户的 `ffi.rs` 重构结束后再接线。

### FFI 冻结

在用户完成当前 `ffi.rs` 大规模重构前：

- 不修改 `art3m1s-core/src/ffi.rs`；
- 不移动或重命名 `art3m1s_register_log_callback`；
- 不修改现有 FFI 头、回调签名或 callback 注册路径；
- `art3m1s-log` 先定义独立 sink 和标准 `log` bridge；
- core 与现有 FFI callback 的接线延后，并放在新的独立 bridge 模块。

不能只移动 `src/backend`。backend 当前依赖
`render_pipeline::{draw,hlsl,post_process,shader}`、core 日志宏、
视频纹理命名和可选 FFI 素材源；如果新 crate 反向依赖
`art3m1s-core`，RFVP adapter 仍然无法独立调用。

建议新 crate 同时包含渲染 API 和具体 backend：

```text
crates/art3m1s-render/
  src/lib.rs
  src/draw.rs
  src/post_process.rs
  src/hlsl.rs
  src/shader.rs
  src/types.rs
  src/external.rs
  src/naming.rs
  src/gl/
  src/metal/
  src/vulkan/
```

迁移映射：

- `render_pipeline/draw.rs` -> `src/draw.rs`
- `render_pipeline/post_process.rs` -> `src/post_process.rs`
- `render_pipeline/hlsl.rs` -> `src/hlsl.rs`
- `render_pipeline/shader.rs` -> `src/shader.rs`
- `backend/types.rs` -> `src/types.rs`
- `backend/external.rs` -> `src/external.rs`
- `backend/{mod.rs,gl,metal,vulkan}` -> backend 目录
- 视频纹理命名 helper -> `src/naming.rs`

`render_pipeline/transition.rs` 保留在 core，因为它属于 Artemis 场景语义。

新 crate feature：

```toml
default = ["gl", "metal", "vulkan", "runtime-shader"]
gl = ["dep:glow", "dep:image", "dep:libloading"]
metal = ["dep:image", "runtime-shader", "dep:objc2", "dep:objc2-metal"]
vulkan = ["dep:image", "dep:ash", "runtime-shader"]
runtime-shader = ["dep:shaderc", "dep:spirv-cross2"]
```

新 crate 不依赖 `art3m1s-core`、`asb-interpreter`、`art3m1s-emote` 或
`pfs-upk-rust`。

### 可复用日志 crate

日志建议单独抽为 `crates/art3m1s-log`，而不是让 render crate 自己维护日志：

当前状态：已新增独立 `art3m1s-log` crate，并通过自身单元测试；尚未加入
core Cargo target、模块声明或 FFI 接线。

```text
crates/art3m1s-log/
  src/lib.rs
  src/level.rs
  src/sink.rs
  src/filter.rs
  src/log_bridge.rs
```

职责：

- 定义稳定的 `Level`、`Record`、`Sink`、`LogHandle`；
- 安装标准 `log` crate 的 forwarding logger；
- 支持 Flutter 热重启后替换 FFI sink；
- 保留递归过滤和 `setLogFilter` 钩子；
- 不负责 profiler、统计聚合或 UI 展示。

依赖关系：

```text
art3m1s-log  <- art3m1s-render
art3m1s-log  <- art3m1s-core
art3m1s-log  <- rfvp host adapter
```

实现约束：

- `art3m1s-core` 的 `core_info!` / `core_warn!` / `core_debug!` /
  `core_error!` 暂时保持现状，等 FFI 重构结束后再改为兼容别名；
- render 和新 adapter 直接使用 `log` facade，不直接依赖 core；
- 调用 sink 时不能持有全局锁；
- FFI callback 使用可替换槽，不能使用 `OnceLock`；
- level 过滤、Lua filter、debug 模式必须保持现有行为；
- 日志 crate 不依赖任何 GPU、audio 或 interpreter crate。

`art3m1s-log` 不直接包含 `src/ffi.rs`。它与现有 Flutter callback 的适配由
core 后续在独立 bridge 模块中完成。

profiler 暂不并入 logger crate。它的 `FrameProfile`、聚合窗口和快照字段
属于独立的 metrics 领域；需要复用时另建 `art3m1s-profiler` /
`art3m1s-metrics`，logger crate 只提供 session 关联字段。

core 兼容层：

```rust
pub mod backend {
    pub use art3m1s_render::*;
}

pub mod render_pipeline {
    pub use art3m1s_render::{draw, hlsl, post_process, shader};
    pub mod transition;
    pub use transition::*;
}
```

必须清理的反向依赖：

1. 日志
   - 当前只新增独立的 `art3m1s-log`；
   - 待 FFI 重构完成后再安装 forwarding logger 到最终 log callback；
   - render/core/RFVP 使用标准 `log` facade；
   - backend 不再引用 `crate::core_warn!` 等宏。
2. 素材源
   - 删除 core 专属 `GlTextureProvider::with_ffi_source()`；
   - 新 crate 只接受 `replace_asset_source` / `with_source`；
   - core runtime 负责注入 FFI reader。
3. 视频命名
   - `video_layer_texture_name` / `is_video_layer_texture_name` 放入
     `art3m1s-render::naming`。
4. 移动端 ASTC
   - 确认 backend 是否直接依赖 `mobile_astc`；需要时移入 render crate。

拆分提交：

1. `refactor(render): create art3m1s-render crate`
2. `refactor(log): add standalone art3m1s-log crate`
3. `refactor(render): remove core-specific asset coupling`
4. `test(render): add feature-matrix and backend smoke coverage`

`art3m1s-log` 与 core FFI 的实际接线不在这些提交中执行；它作为后续独立
提交，依赖用户当前的 FFI 重构结果。

验收：

- `cargo check --manifest-path crates/art3m1s-render/Cargo.toml --locked
  --no-default-features`
- 分别启用 `gl`、`metal`、`vulkan`、`runtime-shader`
- `cargo test -p art3m1s-core` 行为不变
- `art3m1s-render` 依赖树中没有 `art3m1s-core`
- `art3m1s-log` 不依赖 render/core/interpreter/GPU
- RFVP `log` 输出、core 日志和 render 日志可以进入同一 Host session
- core FFI、NativeSurface、video import 和 Host 构建不变

## 阶段 0：冻结 ABI

产出：

- 固定 [RFVP RenderHost ABI v1](abi/rfvp_render_host_v1.h)；
- 固定调用时序、字段宽度、错误码和生命周期；
- 固定 v1 明确不支持项。

v1 支持：

- texture create/update/destroy；
- begin/end frame；
- image、solid、glyph；
- 屏幕矩形裁剪；
- nearest/linear filter；
- alpha/add/reverse-subtract/multiply/screen blend；
- optional mesh、readback、present。

v1 限制：

- 顶点颜色必须一致，否则 adapter 返回 unsupported；
- effect id 暂时只接受 0；
- overlay UI 必须转成普通 draw command；
- 不允许跨 callback 保留指针。

验收：

- C11、C++17 编译通过；
- `abi_version` 和 `struct_size` 有拒绝策略；
- 无 Rust `Vec`、trait object 或平台句柄跨 ABI。

## 阶段 1：rfvp 生产渲染器抽象

修改：

1. `crates/rfvp/Cargo.toml`
   - 增加 `external-renderer` feature；
   - 该 feature 依赖 runtime/audio/image，但不依赖 wgpu/winit/softbuffer。

2. `crates/rfvp/src/host_api/render.rs`
   - 补齐 `DrawSolid`；
   - 明确 screen clip 与 texture UV clip；
   - 为命令增加稳定 generation；
   - 保持现有 `RfvpRenderer` 独立 launcher 兼容。

3. `crates/rfvp/src/rendering/prim_commands.rs`
   - 提升为生产可复用 command collector；
   - 输出 root=0 与 overlay 两段顺序；
   - texture upload 改为 command，不直接操作 GPU；
   - 保留 hit proxy。

4. `crates/rfvp/src/app.rs`
   - `render_frame()` 分成 collect 和 submit；
   - 不再直接取得 surface / render pass；
   - SaveWrite 缩略图改用 renderer readback；
   - LegacySaveLoadUi、ExitConfirmUi 输出 draw command；
   - present 交由 renderer。

5. `crates/rfvp/src/lib.rs`
   - 增加 `rfvp_host_create_with_renderer`；
   - 增加 `rfvp_host_step/push_event/destroy`；
   - 新 ABI 不依赖 winit。

6. `platform/*/RFVPLauncher/Headers/rfvp.h`
   - 同步新 ABI；
   - 保留旧 `rfvp_ios_*`、`rfvp_android_*`。

提交边界：

- `refactor(render): separate frame collection from GPU submission`
- `feat(host): add external renderer ABI v1`
- `test(render): cover command ordering, clip and readback`

验收：

- `cargo test -p rfvp --features external-renderer` 通过；
- 原有 wgpu/launcher 测试通过；
- external-renderer 依赖树不包含 wgpu/winit；
- 固定场景 command fixture 与旧 portable 路径一致。

## 阶段 2：art3m1s-core adapter

### 当前进度

已新增独立 `art3m1s-rfvp` crate，并完成 RFVP fork 与 DrawList 转换层的
真实类型桥接：

- 镜像 RFVP `RenderFrame` / `RenderCommand` 协议类型；
- 维护 `TextureHandle(u32) -> TextureId(u64)` 的显式绑定表；
- 轴对齐精灵保留 quad 路径，旋转或畸变精灵转成 `DrawMesh`；
- `SetClip` / `ClearClip` 只写 `DrawCommand::clip_bounds`；
- `Sub` 映射到 `NativeReverseSubtract`；
- `DrawGlyph`、未来的 `DrawSolid` 和 `HitProxyTable` 都有转换出口；
- 逐顶点异色、非零 `effect_id` 和非法负尺寸会显式返回错误；
- RFVP fork 位于 `/Users/alphaly/RustroverProjects/rfvp`，维护分支为
  `codex/render-host-abi-v1`；
- fork 新增 `external-renderer` feature 和纯记录后端，提交
  `feat(render): add external renderer frame collector`；
- Host crate 通过可选 `rfvp-fork` feature 直接依赖该 fork，并调用
  `convert_rfvp_frame()` 将真实 `rfvp::host_api::RenderFrame` 转成
  `art3m1s_render::DrawList`；
- 纯转换层 6 项测试、真实跨仓库桥接 1 项测试和严格 clippy 已通过；
- `external-renderer` 依赖树不包含 wgpu/winit。

尚未完成的部分：

- `rfvp::App::render_frame` 生产路径仍使用原 wgpu `GpuPrimRenderer`，尚未
  改为从 RFVP App 收集 `RenderFrame` 后交给 Host；
- 没有接入 `GpuBackend` 的 texture create/update/destroy、present/readback；
- 没有加入 core Cargo target、FFI callback 或 Host 启动路径；
- 还需要固定 RFVP 生产 `App` 的 collect/submit 命令 fixture。

新增模块：

```text
src/rfvp/mod.rs
src/rfvp/adapter.rs
src/rfvp/commands.rs
src/rfvp/ffi.rs
```

职责：

- 管理 `Box<dyn GpuBackend>`；
- 维护 `rfvp_texture_id(u32) -> TextureId(u64)`；
- 将 callback command 转成 `DrawList`；
- 管理 native surface、readback、present；
- 提供 `RfvpRuntime`，持有 rfvp host handle。

该 adapter 直接依赖独立的 `art3m1s-render` crate，不依赖 `art3m1s-core`
的 compositor、runtime、FFI 或项目加载模块。

转换规则：

- image -> `DrawCommand` transform 或 `DrawMesh`；
- solid -> white texture draw 或专用 solid path；
- glyph -> texture + dst rect；
- screen clip -> `clip_bounds`；
- texture UV -> `ClipRect`；
- blend 枚举一一映射；
- hit proxy 不进入 GPU，返回 Host。

Host API：

```c
void* art3m1s_rfvp_create(
    const char* game_root_utf8,
    const char* save_root_utf8,
    const char* nls_utf8,
    uint32_t width,
    uint32_t height,
    int32_t backend);
int32_t art3m1s_rfvp_step(void* runtime, uint32_t delta_ms);
int32_t art3m1s_rfvp_set_surface(
    void* runtime, int32_t kind, void* handle, uint32_t width, uint32_t height);
void art3m1s_rfvp_clear_surface(void* runtime);
void art3m1s_rfvp_destroy(void* runtime);
```

验收：

- fake backend 覆盖全部命令和错误路径；
- Metal/Vulkan/GL 至少各有一个 offscreen render smoke；
- texture update 不无条件重建 GPU 对象；
- resize、surface recreation、destroy 无泄漏；
- readback 像素阈值的测试明确。

## 阶段 3：Host 数据模型与发现

数据模型：

- 新增 `lib/models/game_engine.dart`；
- `GameEntry` 增加 `engine`、`nls`；
- `GameManifest` 增加可选 `engine`、`nls`；
- 缺省保持 `artemis`，旧 JSON 不迁移。

发现规则：

- 根目录 `se_sys.bin`；
- `data/se_sys.bin`；
- 根目录 `.bin` 且存在 `data/` 或 `savedata/`；
- 根目录 `.hcb`。

顺序：

1. manifest 显式 engine；
2. `system.ini` -> Artemis；
3. RFVP 特征 -> RFVP；
4. 未识别 -> 忽略。

提交：

- `feat(engine): add engine kind and nls metadata`
- `feat(import): discover rfvp game roots`

## 阶段 4：Host runtime 接入

新增 `RfvpBridge`：

- 调用 `art3m1s_rfvp_*`；
- 映射 tick、触摸、鼠标、滚轮和键盘；
- 复用 shared texture 通道；
- 日志进入现有 `Logger` 会话。

`PlayerScreen`：

```text
GameEngine.artemis -> CoreBridge
GameEngine.rfvp    -> RfvpBridge
```

生命周期要求：

- RFVP step 在 UI isolate 同步执行；
- 前后台切换暂停 step；
- surface destroy 前停止 ticker，再销毁/runtime；
- RFVP 与 Artemis 不共享已绑定 handle。

提交：

- `feat(rfvp): add native runtime bridge`
- `feat(player): route rfvp games through external renderer`
- `test(rfvp): cover detection, lifecycle and input mapping`

## 阶段 5：发布

- 固定 rfvp commit；
- 更新 MPL-2.0/NOTICE/第三方许可证；
- 最终确认 iOS 最低版本；
- Android API 28 以下提示不支持 RFVP；
- 不打包测试游戏或提取资源；
- 真实游戏完成后台切换、存档、resize、退出重进和长稳测试。

## 测试矩阵

| 层级 | 测试 |
|---|---|
| ABI | C/C++ 编译、struct size、版本拒绝 |
| Renderer | fake backend、GL offscreen、Metal/Vulkan smoke |
| rfvp | command fixture、旧 wgpu launcher 回归 |
| core | texture cache、clip、blend、readback、surface |
| Host | discovery、manifest migration、input、lifecycle |
| 真机 | iOS、Android API 28+、macOS 各一个游戏 |
| 长稳 | 30-60 分钟、存档、切后台、resize、退出重进 |

## 回滚规则

- rfvp 旧 launcher 不依赖新 ABI；
- core adapter 由 feature 控制；
- 缺少 `art3m1s_rfvp_*` 时 Host 必须继续加载 Artemis；
- engine 缺省为 Artemis；
- RFVP 接入失败不能破坏旧资料库、存档或 Artemis 启动。

## 第一笔代码修改

第一笔只做 ABI 和 compile-time gate，不接 Host：

1. 在 rfvp 增加 `external-renderer` feature；
2. 把 ABI 草案转为 Rust `#[repr(C)]` 类型；
3. 实现纯记录器后端并生成固定 command fixture；
4. 保持默认构建和现有 launcher 行为不变；
5. 合并条件为 ABI layout、命令顺序、无 wgpu 依赖树。

如果这一笔无法在无 wgpu 构建下完成一帧，后续 core/Host 修改不应开始。
