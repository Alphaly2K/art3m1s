# RFVP 接入 Art3m1s：接口与可行性研究

日期：2026-09-11

研究对象：

- Host：`Art3m1s`，调研基线 `2ec97304cad69bbafea8d375003fe5c41315d0e6`
- Engine：`xmoezzz/rfvp`，固定提交
  `304e773387a9920c9db091ec1fd937c717aea949`，标签 `0.6.0`
- Flutter：`3.44.2`

本文只确定接入边界与实施路线，不改变当前 Artemis runtime 行为。

具体修改顺序和提交边界见
[RFVP 外部渲染器接入实施计划](rfvp-implementation-plan-2026-09-11.md)。

## 结论

RFVP 可以作为第二个引擎接入 Host，但不应被硬塞进现有
`CoreBridge + FileProvider` 抽象。两者拥有不同的文件系统、资源格式、
渲染表面、媒体管线和存档布局。

推荐做法是：

1. Host 增加引擎类型和 runtime 适配层；
2. RFVP 保留自己的 VFS、脚本 VM、音频和视频实现；
3. Flutter 继续负责资料库、窗口、生命周期和覆盖 UI；
4. Android 优先复用 Flutter `SurfaceProducer`，把同一个
   `ANativeWindow*` 交给 RFVP；
5. 正式路线是让 RFVP 输出后端中立 DrawCommand，再由
   `art3m1s-core::GpuBackend` 输出到现有 Flutter 纹理；
6. PlatformView、独立窗口和 pump 模式只保留为 DrawCommand ABI 完成前的
   临时降级方案。

整体可行性：**高**。第一阶段 PoC 的主要风险不在脚本兼容，而在表面所有权、
存档根目录和移动端原生视图生命周期。

## 当前 Host 边界

当前 Host 的启动链是：

```text
LibraryActions
  -> PlayerScreen
  -> CoreBridge
  -> art3m1s_core
```

关键约束：

- `PlayerScreen` 直接构造 `CoreBridge`，并把 `system.ini` 字节传给
  `loadProjectBytes`。
- `CoreBridge` 通过回调把文件、媒体、对话框、字体和纹理操作交给 Flutter。
- 移动端优先显示 `Texture(textureId: ...)`，桌面或共享纹理失败时回退
  CPU RGBA `RawImage`。
- 游戏导入只识别大小写不敏感的 `system.ini` 和 base `.pfs`。
- 每个游戏的存档基准目录由 `AppDataPaths.savesDirectory()` 和稳定
  `gameId` 隔离。

因此 RFVP 不能复用以下 Host 机制：

- `CoreBridge` 的 C ABI；
- `FileProvider` 的 PFS/逻辑文件命名空间；
- `MediaBridge` 的 BGM/SE/Voice/视频转发；
- Artemis 的 `advance/render` 与 CPU RGBA 输出；
- 以 `system.ini` 为中心的项目识别。

## RFVP 0.6.0 接口现状

### 通用启动参数

RFVP 的启动输入只有两项：

- `game_root_utf8`
- `nls_utf8`

`nls` 仅接受：

- `sjis` / `shiftjis`
- `gbk` / `gb2312` / `gb18030`
- `utf8`

RFVP 自己从游戏根目录发现 HCB 脚本和资源，不使用 Host 的
`FileProvider`。因此第一阶段只支持已解包目录，不支持把 Artemis
`.pfs` 作为 RFVP 数据源。

### Android

公开 C ABI：

```c
void rfvp_android_init_context(void* java_vm, void* context_global_ref);
void* rfvp_android_create(
    void* native_window,
    uint32_t width_px,
    uint32_t height_px,
    double native_scale_factor,
    const char* game_root_utf8,
    const char* nls_utf8);
int rfvp_android_step(void* handle, uint32_t dt_ms);
void rfvp_android_resize(void* handle, uint32_t width_px, uint32_t height_px);
void rfvp_android_set_surface(
    void* handle,
    void* native_window,
    uint32_t width_px,
    uint32_t height_px);
void rfvp_android_touch(void* handle, int phase, double x_px, double y_px);
void rfvp_android_set_text_hidpi(void* handle, int enabled);
void rfvp_android_destroy(void* handle);
```

Android 是当前最适合共享 Flutter 纹理的平台：

- Host 已经通过 `TextureRegistry.SurfaceProducer` 创建 Flutter 外部纹理；
- `MainActivity` 已经能从该 surface 取得 `ANativeWindow*`；
- RFVP 正好接受 `ANativeWindow*`；
- RFVP 自己会持有并释放 window reference。

建议把现有 `shared_texture` 通道扩展为通用 surface 通道，再增加
`RfvpBridge`：

```text
TextureRegistry.SurfaceProducer
  -> Surface -> ANativeWindow*
  -> rfvp_android_create
  -> rfvp_android_step
  -> Flutter Texture(textureId)
```

该路线可以保留 Flutter HUD、触摸板、退出按钮和日志浮窗。

限制：

- 最低平台为 Android API 28；
- 当前 RFVP 只实现单指 touch，没有 Android 键鼠/手柄 host ABI；
- `surfaceDestroyed` 时必须先停止 ticker 并销毁 engine，不能只替换窗口；
- RFVP 的 `step` 必须与 surface 生命周期处于同一 UI 线程。

### iOS

公开 C ABI 分两组：

- `rfvp_run_entry`：旧式 winit 入口，不应在 iOS 嵌入模式使用；
- `rfvp_ios_*`：UIKit 托管模式。

核心接口：

```c
void* rfvp_ios_create(
    void* ui_view,
    uint32_t width_px,
    uint32_t height_px,
    double native_scale_factor,
    const char* game_root_utf8,
    const char* nls_utf8);
int rfvp_ios_step(void* handle, uint32_t dt_ms);
void rfvp_ios_resize(void* handle, uint32_t width_px, uint32_t height_px);
void rfvp_ios_touch(void* handle, int phase, double x_points, double y_points);
void rfvp_ios_mouse_button(
    void* handle, int button, int phase, double x_points, double y_points);
void rfvp_ios_mouse_wheel(
    void* handle, int delta, double x_points, double y_points);
void rfvp_ios_key(void* handle, int key, int phase);
void rfvp_ios_destroy(void* handle);
```

`ui_view` 必须是 `CAMetalLayer` 背衬的 `UIView`。这与 Host 当前使用的
`FlutterTexture + CVPixelBuffer/IOSurface` 不是同一种输出表面。

这是 RFVP 自带 wgpu 渲染器的现有能力，不是正式 Host 集成路线。正式路线
应让 RFVP 输出 DrawCommand，再由 `art3m1s-core` 投递到现有
`CVPixelBuffer/IOSurface` 或 Metal texture。

仅在 DrawCommand ABI 尚未落地时，才考虑以下临时降级：

1. 首版用 `UiKitView` 或原生 `UIViewController` 承载 RFVP 的
   `RFVPMetalView`；
2. Flutter 层通过 MethodChannel 传递尺寸、触摸、鼠标和退出事件；
3. 原生层拥有 `CADisplayLink`，在每帧调用 `rfvp_ios_step`；
4. Flutter 的 HUD 是否可覆盖原生视图，需要真机验证 Hybrid Composition
   的层级和触摸命中行为。

若首版直接全屏原生播放器，则实现和风险最低，但会暂时失去 Host 的游戏内
HUD、触摸板、翻译浮层等功能。

部署目标冲突：

- Host 当前最低 iOS 为 `13.0`；
- RFVP launcher 工程最低 iOS 为 `14.0`。

如果 RFVP 产物真实声明 iOS 14 最低版本，则 Host 要么整体提升到 iOS 14，
要么把 RFVP 模块拆成仅在 iOS 14+ 可用的弱链接能力。不能仅修改 launcher
的 `project.yml` 后假定静态库兼容 iOS 13，必须检查最终 Mach-O 和链接结果。

### macOS / Windows / Linux

桌面公开接口：

```c
void rfvp_run_entry(const char* game_root_utf8, const char* nls_utf8);
void* rfvp_pump_create(const char* game_root_utf8, const char* nls_utf8);
int rfvp_pump_step(void* handle, uint32_t timeout_ms);
void rfvp_pump_destroy(void* handle);
```

`rfvp_pump_create` 虽然允许宿主继续掌握主循环，但 `PumpInstance` 仍会创建
RFVP 自己的 winit 窗口。它不会把画面提交到 Flutter 场景。

如果 DrawCommand ABI 尚未完成，桌面 PoC 可以临时启动 RFVP 独立窗口或
子进程。正式集成应使用 `GpuBackend + native surface`，不再为每个桌面平台
分别维护窗口所有权或 `AppKitView` 分叉。

### 日志、媒体和存档

RFVP 0.6.0 的宿主 ABI 没有日志回调、媒体回调、文件回调或自定义存档根目录。

当前行为：

- 日志走 Rust `log` / `env_logger` 体系；
- BGM、SE、Voice、视频由 RFVP 自己解码和播放；
- 存档路径基于游戏根目录下的 `save/`；
- 存档格式是 RFVP 自己的完整快照格式，和原 FVP 不完全相同；
- 没有宿主字体覆盖 ABI，只能使用内置字体或游戏目录 `font/*.ttf`。

移动端导入后游戏目录位于可写沙箱，因此第一版可以让 RFVP 直接在游戏目录
下写 `save/`。但这与 Host 现有的每游戏 `Saves/<gameId>` 隔离机制不一致。

建议给 RFVP 增加一个向后兼容的 create 变体：

```c
void* rfvp_*_create_with_options(const RfvpHostOptions* options);
```

其中至少包括：

- `game_root_utf8`
- `save_root_utf8`
- `nls_utf8`
- `log_callback`
- `log_user_data`
- `flags`

这比在 Host 中复制或移动整个游戏目录更可靠，也能让日志接入现有
`Logger` 会话。

## DrawCommand 与 core 渲染后端复用

### 已存在的命令抽象

RFVP 已有两层后端中立渲染接口：

- `crates/rfvp/src/host_api/render.rs`
  - `RfvpRenderer`：纹理创建/更新/销毁、begin/end frame、draw sprite、
    draw solid、present；
  - `RenderCommand`：`DrawImage`、`DrawGlyph`、`SetClip`、`ClearClip`；
  - `RenderFrame`：命令列表加 `HitProxyTable`。
- `crates/rfvp/src/rendering/prim_commands.rs`
  - `render_motion_to_host()` 把 `PrimManager`、GraphBuff、SnowMotion 转成
    `RenderFrame`。

该抽象足以覆盖基础场景树、纹理、雪花、文本图、裁剪和命中区域。

### 生产路径现状

不能只把上述接口直接标注为 C ABI 就完成接入，因为 RFVP `0.6.0` 的生产
路径没有走它：

```text
App::render_frame
  -> GpuPrimRenderer
  -> wgpu RenderPass / RenderPipeline
  -> wgpu Surface
```

`render_motion_to_host()` 当前只被 `RfvpCore` 的 `no_std` 路径调用。
生产 `App` 另外直接处理：

- root=0 与 overlay/custom root 的分段顺序；
- global dissolve / dissolve2；
- `LegacySaveLoadUi` 与 `ExitConfirmUi`；
- 保存缩略图 GPU readback；
- aspect-preserving present；
- movie/text GraphBuff 的 GPU 上传。

所以正确方案是：

1. 先把生产 `App` 的渲染阶段统一到一个后端无关的命令记录器；
2. 再给该记录器增加稳定 C ABI；
3. Host 用 `art3m1s-core` 的 `GpuBackend` 实现该 ABI；
4. 最终不再创建 RFVP 自己的 `wgpu::Instance/Surface`。

如果跳过第 1 步，只桥接现有 `render_motion_to_host()`，会得到一个能画基础
场景但没有 dissolve、存档缩略图和原生 UI 的残缺播放器。

### core 侧可复用能力

`art3m1s-core` 已经提供比当前 RFVP 命令流更完整的后端契约：

- `render_pipeline::DrawList` / `DrawCommand`；
- `GpuBackend` 的纹理、离屏目标、原生表面、readback 和 present；
- Metal、Vulkan、GL/ANGLE 三种实现；
- `DrawMesh` 动态网格；
- shader group、stencil/mask、颜色过滤和多种 blend；
- Flutter Host 已经使用的 native surface 与共享纹理路径。

因此核心后端不需要为 RFVP 新建一套渲染器。真正缺的是“RFVP 生产渲染能
输出 DrawCommand”这一步。

### 语义映射

| RFVP | art3m1s-core | 结论 |
|---|---|---|
| `TextureHandle(u32)` | `TextureId(u64)` | 建立稳定映射表 |
| `create/update/destroy_texture` | `GpuBackend::create/update/destroy_texture` | 直接映射 |
| `begin_frame` | `GpuBackend::begin_frame(FrameTarget::Main)` | 直接映射 |
| `DrawImage` 四顶点 | `DrawCommand`，必要时用 `DrawMesh` | 可行 |
| `DrawGlyph` | 带裁剪的 `DrawCommand` | 可行 |
| `SetClip` / `ClearClip` | 记录器状态转 `DrawCommand::clip_bounds` | 可行 |
| `CommandBlendMode::Normal` | `BlendMode::Alpha` | 直接映射 |
| `CommandBlendMode::Add` | `BlendMode::Add` | 直接映射 |
| `CommandBlendMode::Sub` | `BlendMode::NativeReverseSubtract` | 需要补齐，不能继续映射成 Alpha |
| `CommandBlendMode::Mul` | `BlendMode::Multiply` | 直接映射 |
| `Rgba8` / `LumaA8` 纹理 | `Rgba8Unorm` / CPU 扩展成 RGBA | 第一版可转换 |
| `HitProxyTable` | Host 命中测试或忽略 | 可选消费 |
| dissolve / UI overlay | `draw_solid` 或普通 `DrawCommand` | 需要统一命令记录器 |
| 保存缩略图 | `GpuBackend::readback` | 不要求 RFVP 自己 readback |

两个需要特别注意的差异：

- RFVP `Vertex2D` 带逐顶点颜色，而 core `DrawCommand` 默认只有 uniform color
  filter。当前主要路径四个顶点颜色相同，可以折算；若未来保留任意逐顶点
  颜色，应给 core 增加通用 `vertex_colors`/material，而不是借用 E-Mote
  专用 corner color。
- RFVP `SetClip` 是屏幕矩形，core `ClipRect` 是纹理 UV 子区域，
  `clip_bounds` 才是屏幕裁剪矩形。适配器必须分别转换这两个概念。

### 建议的 C ABI v1

不建议暴露 Rust `Vec`、引用或 Rust enum。建议提供只含固定宽度字段的
callback vtable：

完整草案见 [`doc/abi/rfvp_render_host_v1.h`](abi/rfvp_render_host_v1.h)。

```c
typedef struct RfvpRenderHostV1 {
    uint32_t abi_version;
    void* user_data;

    int32_t (*create_texture)(
        void* user_data,
        uint32_t texture_id,
        const RfvpTextureDescV1* desc,
        const uint8_t* rgba);
    int32_t (*update_texture)(
        void* user_data,
        uint32_t texture_id,
        const RfvpTextureRectV1* rect,
        const uint8_t* rgba);
    void (*destroy_texture)(void* user_data, uint32_t texture_id);

    int32_t (*begin_frame)(
        void* user_data,
        uint32_t width,
        uint32_t height);
    int32_t (*submit_commands)(
        void* user_data,
        const RfvpDrawCommandV1* commands,
        uint32_t command_count);
    int32_t (*end_frame)(void* user_data);
    int32_t (*present)(void* user_data);
    int32_t (*readback)(
        void* user_data,
        uint8_t* rgba,
        size_t capacity,
        size_t* written);
} RfvpRenderHostV1;
```

`RfvpDrawCommandV1` 第一版应覆盖：

- draw image，固定四顶点；
- draw solid，用 rect + RGBA；
- 屏幕裁剪矩形；
- blend、filter、texture id；
- 可选的 mesh offset/count，为后续变形图层预留；
- effect id 或 shader name，但第一版可为 0/unsupported。

调用时序应固定为：

```text
begin_frame
  -> create/update/destroy texture（允许穿插）
  -> submit_commands（可多次）
end_frame
  -> optional readback
  -> present
```

Host 侧实现可以放在 `art3m1s-core` 的 FFI 层：

- 维护 `u32 -> TextureId`；
- 将命令批转换为一个 `DrawList`；
- 逐条转换为 `DrawCommand`；
- 最后调用当前 `GpuBackend::render()`；
- present、readback 和 native surface 全部沿用现有实现。

这样 RFVP 不需要理解 Metal/Vulkan/ANGLE，也不需要把 wgpu 带进 Host。

### 推荐实施顺序

1. 在 RFVP 上游把 `render_frame()` 拆成“场景收集”和“后端提交”两阶段；
2. 为生产模式实现 `RfvpRenderer`，保留现有 wgpu 实现用于独立启动器；
3. 增加 `RfvpRenderHostV1` C ABI 和版本号；
4. 在 `art3m1s-core` 编写 callback adapter 和纯 CPU 测试后端；
5. 用固定 DrawCommand 回归帧做字节级/像素级对比；
6. 再替换 Flutter 侧的 surface 创建路径。

最小验证不应只检查“命令数量”。需要至少覆盖：

- 纹理更新后 UUID/世代失效；
- 裁剪矩形与 UV 裁剪不同语义；
- Sub/Mul blend；
- dissolve 双阶段顺序；
- 文本更新与字形纹理复用；
- 保存缩略图 readback；
- 窗口 resize 后的 aspect-preserving present。

## 接口分层建议

不要在 `CoreBridge` 内按引擎类型写 `if`。建议增加一层很薄的 runtime
契约：

```dart
enum GameEngine { artemis, rfvp }

abstract interface class GameRuntime {
  Future<void> initialize();
  Future<void> load();
  int step(int deltaMs);
  void resize(int widthPx, int heightPx);
  void dispose();
}
```

实现：

- `ArtemisRuntimeAdapter`：包装现有 `CoreBridge`，行为保持不变；
- `RfvpRuntimeAdapter`：只负责 RFVP FFI、native surface 和输入转发；
- `PlayerSurface`：根据 `GameEngine` 选择 Flutter `Texture`、平台视图或
  CPU RGBA 回退。

`PlayerScreen` 仍保留通用职责：

- 页面生命周期；
- 60 Hz 调度；
- 输入门控；
- HUD、触摸板和退出；
- 日志会话。

但媒体、字体、翻译和存档不能跨引擎强绑。RFVP 第一版应明确：

- 不支持 Host 媒体接管；
- 不支持 Artemis 翻译补丁；
- 不支持已包装 `.pfs`；
- 存档由 RFVP 自己管理；
- HUD 是否可覆盖取决于平台视图实现。

## 项目数据模型

建议在 `GameEntry` 和 `GameManifest` 增加向后兼容字段：

```json
{
  "engine": "rfvp",
  "nls": "sjis"
}
```

兼容规则：

- 缺省 `engine` 为 `artemis`；
- `nls` 仅对 `rfvp` 生效；
- 旧资料库 JSON 不需要迁移；
- `runtimePlatform`、`reportedOs`、`environmentPatchEnabled` 等 Artemis
  专有字段对 RFVP 忽略；
- manifest 中显式 `engine` 优先于自动识别。

## 游戏发现

RFVP 常见根目录特征：

- 根目录存在 `se_sys.bin`；
- `data/se_sys.bin` 存在；
- 根目录存在其他 `.bin`，并伴随 `data/` 或 `savedata/`；
- 根目录存在 `.hcb`，但移动端只把所选目录本身视为游戏根。

Host 的 `discoverUnpackedProjects` 应改为返回“项目 + 引擎类型”：

```dart
class DiscoveredGame {
  final String name;
  final String path;
  final GameSource source;
  final GameEngine engine;
  final String nls;
}
```

发现顺序建议：

1. 显式 manifest；
2. `system.ini` -> Artemis；
3. RFVP 根目录特征 -> RFVP；
4. 两者都不满足 -> 忽略。

现有“所选目录中没有 `system.ini`”提示需要改成“未发现支持的游戏项目”。

## 分阶段实施

### Phase 0：兼容性验收

目标：不接入 Host，先证明 RFVP 0.6.0 在当前目标设备能运行至少一个合法
测试游戏，并记录脚本版本、NLS、启动时长、内存和日志。

验收：

- macOS、Android API 28+、iOS 14+ 至少各完成一次真实启动；
- 确认 `rfvp_android_create/step/destroy` 在 Flutter UI 线程稳定；
- 确认 iOS `CAMetalLayer` 视图的缩放和触摸坐标；
- 记录存档实际落盘目录。

预计：1-2 个工作日。

### Phase 1：Host 抽象与项目识别

目标：加入 `GameEngine`、`nls`、发现逻辑和 runtime 选择，不改 Artemis
行为。

验收：

- 旧资料库和旧 manifest 全部保持默认 Artemis；
- 新增 RFVP 目录可进入资料库；
- `flutter analyze` 和现有测试通过；
- 新增发现逻辑单元测试。

预计：2-3 个工作日。

### Phase 2A：Android 共享纹理 PoC

目标：复用现有 `SurfaceProducer`，让 RFVP 输出到 Flutter `Texture`。

验收：

- surface 创建、销毁、前后台切换不崩溃；
- `step` 与 `resize` 不错序；
- 单指触控坐标准确；
- 游戏画面与 Flutter HUD 同层显示。

预计：3-5 个工作日。

### Phase 2B：iOS 原生表面临时降级

目标：在 DrawCommand ABI 完成前，临时桥接 `RFVPMetalView` 和
`CADisplayLink`，确认 PlatformView 与 Flutter 覆盖 UI 的层级行为。

验收：

- Metal view 尺寸与 Retina scale 正确；
- 触摸、右键和滚轮事件进入 RFVP；
- 退出和后台恢复不会破坏 Flutter engine；
- 至少验证 iOS 14 和当前最低目标版本的关系。

预计：4-7 个工作日。

### Phase 2C：桌面 pump/独立窗口临时降级

目标：先证明 RFVP 游戏可在 Host 发起的桌面运行流中启动和退出。

验收：

- RFVP 窗口生命周期与 Host 页面一致；
- 游戏退出或关闭窗口能正确回收；
- 后续再决定是否补原生 surface ABI。

预计：1-2 个工作日。

### Phase 3：产品化

目标：补齐存档根目录、日志、字体、错误恢复、许可证和发布构建。

建议上游 RFVP 最小补丁：

1. `create_with_options` 和自定义 `save_root`；
2. 日志回调；
3. Android 键鼠/手柄输入；
4. 宿主提供 Metal/AppKit surface 的可选接口；
5. 可读取的帧/表面说明，避免不同平台再分叉。

预计：1-2 周，不含大规模游戏兼容测试。

单人完成 Android + iOS 基础接入的合理估计是 **3-5 周**；三桌面平台
统一到 Flutter 内嵌画面需要额外上游改造，不应按现有 C ABI 承诺。

## 验证矩阵

| 项目 | Android | iOS | macOS | Windows/Linux |
|---|---|---|---|---|
| RFVP 启动/退出 | 必测 | 必测 | 必测 | 必测 |
| 外部渲染器到 core | 首选 | 首选 | 首选 | 首选 |
| Flutter 纹理输出 | 现有通道 | 现有通道 | 现有通道 | platform surface |
| 原生 PlatformView | 不需要 | 仅临时降级 | 仅临时降级 | 不适用 |
| 独立窗口 | 不适用 | 不适用 | 仅临时降级 | 仅临时降级 |
| 单指触控 | 有 ABI | 有 ABI | 窗口事件 | 窗口事件 |
| 键鼠/滚轮 | 无 ABI | 部分 ABI | 窗口事件 | 窗口事件 |
| Host HUD 覆盖 | 应可行 | 应可行 | 应可行 | 应可行 |
| Host 媒体接管 | 否 | 否 | 否 | 否 |
| Host 自定义存档根 | 需补 ABI | 需补 ABI | 需补 ABI | 需补 ABI |

## 许可证与发布

RFVP 使用 MPL-2.0，与 Art3m1s 当前许可证一致。静态链接不改变 Host
闭源分发能力，但：

- 修改过的 RFVP 文件必须继续按 MPL-2.0 提供对应源码；
- 发布包需要保留 RFVP 的 MPL-2.0 文本和版权说明；
- 需要重新生成第三方依赖许可证清单；
- 不得打包或分发测试使用的游戏脚本、图片、音频、字体或密钥。

## 最终建议

第一阶段不要重写 Artemis 的合成逻辑。采用
“RFVP DrawCommand -> `art3m1s-core::GpuBackend` -> 统一纹理/surface”路线：

- 先在 RFVP 上游把生产 `App::render_frame()` 拆成命令收集和后端提交；
- 再为命令收集器增加稳定 ABI；
- 在 `art3m1s-core` 实现 RFVP command adapter；
- Host 最后增加 `engine`/`nls`、发现逻辑和 `RfvpBridge`；
- 在 RFVP 上游同步补 `save_root` 和日志回调；
- PlatformView、独立窗口只作为外部渲染器落地前的临时验证。
