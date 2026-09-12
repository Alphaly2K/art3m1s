# Host 跨引擎抽象

日期：2026-09-12

状态：第一阶段已接入 Artemis core；RFVP backend 尚未实现。

## 目标

Host 的播放器、资料库、媒体层、翻译层和 HUD 只依赖引擎无关契约，不直接调用
`art3m1s-core`、RFVP C ABI 或任意 native 库。

```text
PlayerScreen
  -> EngineRuntime
       -> Art3m1sEngineRuntime
            -> CoreBridge
                 -> art3m1s-core
       -> RfvpEngineRuntime (planned)
            -> rfvp_* ABI
```

## 目录边界

```text
lib/engine/engine_runtime.dart
lib/engine/engine_runtime_factory.dart
lib/engine/backends/art3m1s_engine_runtime.dart
lib/services/core_bridge.dart
```

- `engine_runtime.dart` 只定义 Host 可见的数据类型和接口。
- `engine_runtime_factory.dart` 根据资料库里的 `GameEngineKind` 选择实现。
- `backends/art3m1s_engine_runtime.dart` 是唯一的 core 适配点。
- `CoreBridge` 继续负责 `DynamicLibrary`、`CoreApiV1`、shared texture、
  host events 和 native lifetime，不向 UI 暴露。
- RFVP 后续放在 `lib/engine/backends/rfvp_engine_runtime.dart`，不得把
  RFVP 分支塞进 `CoreBridge`。

## Host 依赖的契约

`EngineRuntime` 当前覆盖：

- 初始化、销毁、调试和生命周期；
- 舞台尺寸、共享纹理和 CPU RGBA 输出；
- native surface 是否支持 spatial upscale；
- 逻辑 tick、present 和 readback；
- 键鼠、触摸、滚轮输入；
- 文本翻译、字体、存档、机种和输入门控配置；
- media host、光标状态、紧急回避覆盖和 profiler。

其中 shared texture 和 RGBA readback 是 Host 的输出传输方式，不是 core API
对象。RFVP adapter 可以选择：

- 通过 `art3m1s-render` 输出 Flutter texture；
- 返回 CPU RGBA；
- 后续扩展 native surface；
- 在引擎不支持时把能力查询返回 false。

## 引擎身份

`GameEntry` 和 `GameManifest` 增加可选 `engine` 字段：

- `art3m1s`：默认值，兼容旧资料库和旧清单；
- `rfvp`：选择 RFVP backend。

旧数据缺字段时始终落到 `art3m1s`。RFVP adapter 未接线时工厂返回安全的
`UnsupportedEngineRuntime`，资料库和 UI 不会因句柄构造而崩溃。

## RFVP 接线顺序

1. 在 RFVP fork 完成 v1 ABI 的 runtime/resources/frame 实现。
2. 新增 `RfvpEngineRuntime`，只依赖 Host 的 engine contract 和 RFVP ABI。
3. 资源目录、PFS/自定义 pack、存档根分别映射到 RFVP resources handle。
4. shared texture 优先走 `art3m1s-render`；无外部渲染时再提供 RGBA fallback。
5. 文本替换和翻译请求接到 `TextTranslationService`。
6. 最后才在资料库导入流程启用 `engine=rfvp` 的自动识别。

## 约束

- `PlayerScreen`、`LibraryActions` 和 HUD 不导入 `core_bridge.dart`。
- 不让 RFVP 复用 `CoreApiV1`、`_HostEventApi` 或 core 的 runtime handle。
- 不在 `CoreBridge` 内通过平台判断混入 RFVP 路径。
- 平移期间保持 Artemis 行为不变；抽象层只做转发，不改变 tick、输入和媒体时序。
