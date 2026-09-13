# 接入新引擎指南

日期:2026-09-13

本文列出向 Host 接入一个新引擎(如 KRKR)时,导入链路和每游戏设置所必须
实现/扩展的全部接口。引擎身份以 `GameEngineKind` 为准,能力用声明式描述符
表达,不要在 UI 或导入层散落 `if (engine == ...)` 分支。

## 1. 引擎身份与能力描述符

`lib/models/game_engine.dart`:

- 在 `GameEngineKind` 中新增枚举值(`id`, `label`)。`id` 是持久化到资料库
  JSON 和 `art3m1s.json` manifest 的字符串,一旦发布不能再改。
- 实现 `supportedGameSettings`:该引擎在「每游戏设置」中有意义的
  `GameSettingField` 集合。设置页(全部 5 套平台对话框)和 manifest 的读写
  过滤都由它驱动——集合里没有的字段,编辑页不渲染、manifest 不写入、
  加载时不应用。
- 实现能力查询:
  - `supportsPfsArchives`:是否能发现/挂载 PFS 归档项目(PFS 是 Artemis
    专属格式,其他引擎通常为 false);
  - `supportsCaptionProbe`:是否支持导入前的原生 caption 探测。
- `fromId` 的未知值回落 art3m1s 是迁移期兼容行为,新引擎不需要也不应该
  修改它;新引擎的条目必须显式携带自己的 id。

## 2. 导入链路

统一导入契约:**全平台均为「选择文件夹 → 探测 → 原地入库」,不复制**。

- 目录标记探测:`GameImporter.discoverUnpackedProjects` /
  `detectDirectoryEngine`(`lib/services/game_importer.dart`)。Artemis 以
  `system.ini` 为根标记,RFVP 以 `.hcb` 为根标记。新引擎在
  `_isSystemIniName`/`_isHcbName` 旁增加自己的标记判定,并在
  `detectDirectoryEngine` 中排定优先级(现有规则:同时命中时 system.ini
  优先,即 Artemis 优先)。
- iOS 扫描:`ios/Runner/AppDelegate.swift` 的 `scanIosAppGamesFolder`
  需要识别新引擎的根标记(目前识别 `system.ini` 和 `.hcb`)。
- Android:无需引擎相关改动。`MANAGE_EXTERNAL_STORAGE` 授权 + SAF 选目录
  + URI→路径解析是引擎无关的。
- manifest 发现:目录项目在根目录/一级子目录查找 `art3m1s.json`;
  PFS 归档发现仅 Artemis 支持。manifest 的 `engine` 字段优先于标记探测
  (`LibraryActions._resolveProjectEngine`)。

## 3. Runtime 接入

- `lib/engine/engine_runtime.dart`:实现 `EngineRuntime` 接口。不适用的
  能力保持 no-op/false(参考 `RfvpEngineRuntime` 与兜底
  `UnsupportedEngineRuntime`),不要假装支持。
- `lib/engine/engine_runtime_factory.dart`:`create()` 的 switch 中登记
  新实现;`probeCaption()` 在未实现时返回 null 并记录日志。
- `lib/engine/engine_archive.dart`:不支持归档的引擎让 `listEntries` /
  `readFile` 返回空(与 RFVP 现状一致)。
- core 侧 ABI:独立入口 `art3m1s_<engine>_get_api_v1` 版本化函数表,
  不复用 `Art3m1sApiV1` 的字段;详见 core 仓库 `doc/HOST_INTEGRATION.md`。
  反向通信一律 Host 拉取(事件/日志队列),不注册 native→Dart 回调。

## 4. 每游戏设置

不需要改设置页代码:5 套平台编辑对话框(`lib/adaptive/dialogs.dart`
的 `showGameEditDialog` 及各 `_<Platform>EditDialog`)都按
`engine.supportedGameSettings` 条件渲染。新增设置字段时:

1. 在 `GameSettingField` 中新增枚举值;
2. 在 `GameManifest` 中加字段、`fromJson`/`toJson`/`applyTo` 中接线
   (toJson/applyTo 必须过 `_supports` 过滤);
3. 在 `GameEditData` 和 5 套对话框中按字段条件渲染;
4. 在 `game_manifest_test.dart` 补按引擎过滤的用例。

## 5. 验收清单

- [ ] `flutter analyze` 无告警;`flutter test` 全绿。
- [ ] `test/game_importer_test.dart` 覆盖新引擎的标记探测与优先级。
- [ ] `test/game_manifest_test.dart` 覆盖新引擎的 manifest 字段过滤。
- [ ] iOS 扫描能识别新引擎目录;Android 全文件访问授权流程不受影响。
- [ ] 资料库删除条目时不会删除用户原目录(托管根白名单仅针对遗留沙箱拷贝)。
