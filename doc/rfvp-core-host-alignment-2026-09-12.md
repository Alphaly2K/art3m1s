# RFVP Core、资源与脏区对齐说明

日期：2026-09-12

## 结论

正式接入目标是 RFVP 的 `RfvpCore + RfvpHost`，不是 `App`。

`App` 自身持有 winit、wgpu surface、desktop audio 和图像后端，本质上也是一个
host。Host ABI 继续复用它只会把 Host 的设备生命周期复制进引擎。当前实现已经改为
windowless、device-free 的 core 路径：

- 渲染通过 `RfvpRenderer` 产生后端中立命令；
- 音频通过 `RfvpAudio` 产生命令，不创建 CoreAudio/CPAL 设备；
- 文件和时钟通过 `RfvpHost` 提供；
- VM、文本、动画和 HCB 解析仍由 RFVP core 负责。

`win95_painter_demo` 的 host ABI smoke 已连续输出 10 帧，尺寸
`1024x640`，每帧约 3223 条 draw command，首帧生成 3 张纹理。

## 资源读取对齐

art3m1s-core 的资源模型是：

1. `HostResources` 持有目录/PFS 索引、overrides 和 save dir；
2. 运行时通过 `read_file`、`read_range`、`query_size` 等路径访问；
3. 脚本层不直接知道文件是目录、PFS 还是 override。

RFVP core 已有等价的宿主边界 `RfvpFileSystem`、`RfvpFile`、`RfvpFileKind`。
正式适配应让 RFVP 只做自己的 `.bin` pack 解析和 VFS 映射，底层目录枚举、override
和存档根由 Host 提供。

当前已对齐：

- `host-runtime` 不再使用 `app_base_path` 或 desktop `App/Vfs` 的扫描逻辑；
- HCB 与 `.bin` pack 由 `RfvpHost::FileSystem` 枚举和读取；
- 无法解析的 `.bin` 会记录 warning 并跳过，不再阻断启动；
- 默认字体缺失时允许 Host 使用内嵌字体回退。

仍需补齐：

- `resources_set_override` 将字节持久化到 `HostFileSystem`，大小写不敏感；
- `resources_set_save_root` 影响 RFVP VFS 的写路径；
- `resources_mount_pack` 以目录名和 pack bytes 建立虚拟 `<name>.bin`；
- Host 侧 PFS 条目若要供 RFVP 使用，统一展开成 override 或 pack mount，不让 RFVP
  直接依赖 art3m1s-core 的 PFS 类型。

## 脏区更新

art3m1s-core 的脏区机制在 `runtime::render::frame_damage`：

- 有稳定 key 的命令比较旧、新 bounds；
- 无稳定 key 时按 position 做保守匹配；
- shader group 和 opaque cover 会参与覆盖裁剪；
- 损伤面积超过阈值会退回全帧。

RFVP core 已经输出 `RenderFrame` 的完整 command 序列和 hit proxy，但没有暴露
damage 结果。接入可分两步：

1. 保守模式：Host 先按全帧更新，保证正确性；
2. 精确模式：给 RFVP `RenderCommand` 增加稳定 `prim_id` 或 command key，再复用
   同一套 draw-list damage 算法，产物是 `Option<RectI16>`。

ABI 侧建议追加：

- capability：`RFVP_CAPABILITY_FRAME_DAMAGE`；
- getter：`rfvp_frame_get_damage(frame, out_rect)`；
- 结构：`RfvpFrameDamageV1 { flags, sequence, rect }`。

因此脏区机制可以接入，而且不需要 RFVP 自己拥有 GPU 后端。缺的不是渲染器，而是
command identity 和共享 damage calculator。全帧 fallback 可以一直保留为安全路径。
