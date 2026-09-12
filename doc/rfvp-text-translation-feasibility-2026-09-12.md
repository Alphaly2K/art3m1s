# RFVP 文本渲染与实时翻译接入研究

日期：2026-09-12

关联文档：

- [RFVP 接入可行性研究](rfvp-integration-feasibility-2026-09-11.md)
- [RFVP 外部渲染器接入实施计划](rfvp-implementation-plan-2026-09-11.md)

## 结论

RFVP 可以复用 Host 现有在线翻译服务，但接入点必须放在
`TextPrint -> TextManager`，不能放在 DrawCommand、GraphBuff 或 GPU 纹理层。

推荐路线：

1. RFVP 在文本进入 `TextManager` 前提供同步替换和异步请求接口。
2. Host 的 `TextTranslationService` 直接处理请求，不新增翻译 HTTP 实现。
3. 译文完成后回写原 text slot，由 RFVP 重新排版和光栅化。
4. 现有 GraphBuff、primitive、external renderer 和
   `art3m1s-render::DrawList` 继续按原路径输出，不修改 FFI 或渲染 ABI。
5. 字体覆盖作为独立能力加入 RFVP `FontEnumerator`，优先使用 Host 选择的
   TTF/OTF 补足译文缺字。

整体可行性：**高**。主要风险不是渲染，而是异步结果与原 text slot 生命周期
的匹配，以及带 ruby、等待控制和 gaiji 标记文本的安全重排。

## Host 现有翻译链

Artemis runtime 已有完整实现：

```text
ScenarioText
  -> request_text_injection()
  -> 命中 replacement table: 立即显示译文
  -> 未命中且在线翻译开启: 保留原文并发送 text_translate
  -> TextTranslationService.enqueue()
  -> art3m1s_runtime_submit_text_translation(serial, text)
  -> 原 reveal 完成后 replace_text_span()
```

关键组件：

- `lib/services/text_translation_service.dart`
  - patch 表和 protobuf 缓存；
  - provider 协议、请求去重、有限并发、批量 LLM 请求；
  - `enqueue(source, ruby, onComplete)`。
- `lib/services/core_bridge.dart`
  - 提交 replacement table；
  - 处理 `text_translate` UI event；
  - 将结果回填 runtime。
- `art3m1s-core/src/runtime/text.rs`
  - 记录文本跨度、serial 和 layer generation；
  - 译文到达时检查原始跨度是否仍有效；
  - 原文字形显示完成后再替换，避免 reveal 长度变化导致跳字。

RFVP 接入应复用 Dart 服务和无网络依赖的接口语义，但不要调用
`art3m1s_runtime_submit_text_translation`。RFVP runtime 需要自己的回填入口。

## RFVP 文本管线

当前路径：

```text
HCB TextPrint(slot, text)
  -> TextManager::set_text_content()
  -> tokenize_content_text()
  -> TextItem layout / rasterize
  -> GraphBuff 4064 + slot
  -> primitive tree
  -> external renderer
  -> art3m1s-render::DrawList
  -> Art3m1s GPU backend
```

`TextItem` 同时保存原始格式串、解析后的 `FontItem`、槽位样式、布局尺寸、
逐字 reveal 状态和 RGBA surface。`TextPrint` 还可能阻塞当前脚本 thread，
直到该槽位 reveal 完成。

### 文本标记

`content_text` 不一定是纯显示文本：

- `[ruby|base]`：ruby 注音和基础文字；
- `{n}`：等待控制；
- `<name>`：special unit，可能映射到 gaiji texture，也可能是普通字符串。

因此不能无条件把整个字符串交给翻译模型后直接覆盖。第一版必须把控制结构
作为不可翻译片段保留；否则会破坏注音、reveal 和图片字形。

### 槽位生命周期

翻译结果不能仅按 `slot id` 回填。以下操作都会使旧请求失效：

- `TextClear(slot)`；
- `TextBuff(slot, ...)` 重置槽位；
- 对同一槽位再次 `TextPrint`；
- 页面切换或存档恢复；
- 槽位被 fade-out motion 延迟释放。

每次对外部可见内容变化都应递增 slot generation，并清理该槽位之前的 pending
request。

## 推荐引擎接口

RFVP 增加一个不依赖 Flutter、FFI 或具体 GPU 的文本翻译边界：

```rust
pub struct TextTranslationRequest {
    pub serial: u64,
    pub slot: u32,
    pub generation: u64,
    pub source: String,
    pub ruby: Option<String>,
}

pub enum TextTranslationDecision {
    KeepOriginal,
    Replace(String),
    Pending,
}
```

建议由 `App` 或一个独立 `TextTranslationController` 持有：

- 单调递增 serial；
- 每槽位 generation；
- pending request 表；
- 已提交但等待 reveal 完成的译文；
- 从 Host 安装的同步 replacement table。

接口分层：

```rust
impl PumpInstance {
    pub fn set_text_replacements(&mut self, replacements: HashMap<String, String>);
    pub fn drain_text_translation_requests(&mut self) -> Vec<TextTranslationRequest>;
    pub fn submit_text_translation(&mut self, serial: u64, text: Option<&str>) -> bool;
}
```

`drain` 和 `submit` 只传递普通 Rust 数据。未来 production host adapter 负责把
它们转成 Flutter bridge 事件，不要求 RFVP 认识 Dart 或 JSON。

## 同步与异步路径

### 对照文件和缓存

1. Host 启动时把当前 patch/cache 表交给 RFVP。
2. `TextPrint` 在调用 `set_text_content()` 前查询精确匹配。
3. 命中时直接用译文解析、排版和光栅化。
4. 不创建待翻译请求，不等待网络。

这条路径适合已有的汉化对照文件，也能避免重复请求已经缓存的文本。

### 在线翻译

1. 未命中 replacement table 时保留原文并立即渲染。
2. 生成 request，记录 slot、generation、source 和 ruby。
3. Host 调用 `TextTranslationService.enqueue()`。
4. 结果返回后调用 `submit_text_translation()`。
5. RFVP 校验 serial、slot generation 和 source revision。
6. 等待原 reveal 完整显示后，用译文替换该槽位的 `content_text`。
7. 重新解析、排版、rasterize，并更新同一个 GraphBuff。

建议译文到达时保留 `visible_chars = total_chars`，直接显示完整译文，而不是
把原文的 reveal 进度强行映射到译文字符数。长度变化后的逐字映射没有稳定语义。

## 标记安全策略

第一版分两步：

1. 在 RFVP 内把 `content_text` 拆成 literal、ruby、wait 和 special-unit
   segments；只有 literal 与 ruby/base 文本进入翻译。
2. 翻译完成后按原 segment 顺序重建格式串。

请求协议可以保留完整 source，但必须同时附带结构化 segments，让 Host 在构造
LLM 输入时使用占位符并校验返回结果。

LLM 输出不符合原占位符结构时：

- 丢弃本次结果；
- 保留原文；
- 记录 warning；
- 不影响当前 reveal 和后续文本。

## 字体覆盖

RFVP `FontEnumerator` 已有：

- 项目 `font/` 目录字体；
- MS Gothic/Mincho 等内置字体；
- 可选系统 CJK fallback；
- 主字体缺字时的 fallback 集合。

Host 翻译设置已有 `fontPath`。RFVP 应增加一个 runtime-only host font：

```rust
pub fn set_host_font_override(&mut self, generation: u64, bytes: Vec<u8>);
pub fn clear_host_font_override(&mut self);
```

要求：

- 只接受可解析的 TTF/OTF；
- 世代变化时重新解析，不按每个字符重复建字体；
- 放在 CJK fallback 优先级前列；
- 清理后恢复项目字体行为；
- 字体变化后重排当前已加载的翻译文本。

正式 Host 可以直接复用 `translation.fontPath`，但通过 RFVP bridge 提交，而不是
调用现有 Artemis FFI。

## 与渲染后端的衔接

该方案不需要改 `art3m1s-render` 或 external renderer ABI：

- 译文仍写入 text slot；
- slot 仍映射到 GraphBuff `4064 + slot`；
- generation 更新会让 GPU texture cache 重传；
- RFVP primitive tree 和 DrawCommand 数量不变；
- `ExternalRenderer` 只观察到新的纹理像素。

这能把翻译问题限制在文字系统内，不会再次触碰刚稳定的 draw-list 和 Metal
后端。

## Host 接线

未来新增 `RfvpBridge` 时：

1. 复用 `TextTranslationService.create()`。
2. 启动时提交 `hostReplacementTable`。
3. 每次 pump 后 drain RFVP translation requests。
4. 对每个 request 调用 `enqueue()`。
5. 回调中调用 RFVP `submit_text_translation()`。
6. 翻译设置变化时重建 service，并刷新 replacement table。
7. 游戏退出前 dispose service，清理缓存写入定时器。

RFVP bridge 不应直接依赖 `CoreBridge` 或共用 runtime handle。

## 存档与恢复

需要明确选择：

- 推荐只持久化显示的 `content_text`，恢复后继续显示译文；
- 同时保留 source revision，加载后允许重新提交 replacement table；
- pending 网络请求不进入存档；
- 加载完成后清空旧 serial，避免上一局结果回填。

还要覆盖 `TextManagerSnapshotV1`：

- 新增字段必须有默认值，旧存档可读取；
- 不建议把一次性 pending 状态写入存档；
- 恢复后由新 generation 决定是否需要重新翻译。

## 分阶段实施

### 阶段 A：引擎内同步替换

- 增加 replacement table；
- 在 `TextPrint` 进入 `TextManager` 前做精确替换；
- 保留 ruby/wait/special-unit 结构；
- 覆盖 TextClear、TextBuff、重复 TextPrint。

验收：

- 固定文本 fixture 可替换；
- 原文、ruby 和等待顺序不变；
- 未命中时行为与当前完全一致；
- `external-renderer` 依赖树不增加 winit/wgpu。

### 阶段 B：异步 request/response

- 增加 serial、slot generation、pending 表；
- 增加 drain/submit API；
- 结果过期、槽位清空、页面变化时丢弃；
- 原 reveal 完成后应用译文。

验收：

- 译文不会覆盖同槽位的新文本；
- 槽位清空后不会重新出现旧译文；
- 长译文换行、reveal 和 sync print 不挂起；
- 连续文本片段保持请求顺序和上下文。

### 阶段 C：Host 接线

- `RfvpBridge` 复用 `TextTranslationService`；
- 补 patch、缓存和在线 provider 的集成测试；
- 增加字体覆盖；
- 真机验证 iOS/Android/macOS。

验收：

- 在线翻译关闭时零网络请求；
- 重复文本只翻译一次；
- 切页后过期结果不显示；
- 翻译失败只保留原文，不阻塞游戏；
- 字体缺失时译文不再显示空白。

## 当前不做

- 不修改 `art3m1s-core/src/ffi.rs`；
- 不增加或修改 Host FFI callback 签名；
- 不把翻译逻辑放进 `GpuBackend`；
- 不在 DrawCommand 上挂原文文本；
- 不依赖 OCR 或截屏识别；
- 不要求 RFVP 直接依赖 Flutter/Dart。

## 待确认问题

1. `TextPrint` 是否覆盖目标游戏全部剧情文本，还是还有直接操作 TextBuff
   像素/字符串的路径。
2. `<...>` special unit 在各目标游戏中的实际语义和 gaiji 映射比例。
3. 译文比原文长时，脚本预设 message window 是否允许增高或只允许换行。
4. 存档是否需要保留原文与译文双份内容。
5. 目标语言字体在移动端是随包提供还是由用户选择。

