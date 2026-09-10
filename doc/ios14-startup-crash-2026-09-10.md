# iOS 14.5 TrollStore 启动崩溃调查

## 结论与证据范围

移除 `flutter_file_dialog` 没有解决报告中的启动崩溃。两次故障的寄存器特征高度一致，
应继续调查原生启动和动态库加载路径。目前没有足够信息确定故障函数或提交已验证的修复。

两份系统报告均缺少调用栈和 Binary Images，且报告生成器自身提示
`Failed to create CSSymbolicatorRef - corpse still valid`。
即使有匹配的 dSYM，没有故障地址所属映像及其加载基址，也不能可靠地符号化 PC。
该提示描述的是报告生成失败，不能直接当作应用崩溃原因。

设备为 iPhone13,2，iOS 14.5 (18E199)。设备是否越狱、原安装是否开启 Unsandbox 暂时未知。

## 两次构建对照

| 项目 | 第一份报告 | 第二份报告 |
| --- | --- | --- |
| 报告文件时间 | 2026-09-10 15:45:06 | 2026-09-10 20:49:08 |
| 对应本地构建 | `build/ios/Release-iphoneos` | `build/ios/Profile-iphoneos` |
| Runner / dSYM UUID | `D04DE598-F51A-3E33-ADB6-2096ECBCA46E` | `2F501818-B219-3B32-823A-473F11C6C223` |
| 启动到崩溃 | 33.2 ms | 32.7 ms |
| PC | `0x102729204` | `0x102d91204` |
| LR | `0x102728be8` | `0x102d90be8` |
| 无效访问地址 | `0x103ec9800` | `0x104531800` |

两份报告均为 `EXC_BAD_ACCESS (SIGSEGV) / KERN_INVALID_ADDRESS`。
PC、LR、无效访问地址分别相差同一个 `0x668000`，与映像地址随机化相符；
`x2=0x765`、`x8=0x800`、`x19=0x9b`、`x22=0x765` 等也一致。
这支持两次走到了相同的故障路径，但不能由此断言某个 dyld 函数有缺陷。

Release Runner 中能找到 221 个匹配 `flutter_file_dialog` 的符号，Profile 中为 0。
因此插件移除确实进入了第二次构建，不能用“修改未生效”解释复现。
调查开始时 HEAD 是 `171f362`，最近提交止于 9 月 9 日；相关插件移除和签名改动位于未提交工作区，
未找到与本次修复对应的 9 月 10 日提交。

## 已做的二进制检查

- Runner、Flutter、Rust、ANGLE、objective_c 的最低系统版本均为 iOS 13.0；未发现高于 14.5 的部署目标。
- 检查的加载信息未发现 chained fixups；具有动态绑定信息的相关二进制使用 `LC_DYLD_INFO_ONLY`。
- Rust 对 MetalFX 是弱链接，不能仅凭出现 MetalFX 就认定 iOS 14 不兼容。
- 对部分 C++、SwiftCore、zlib 导入符号核对了 iOS 14.5 SDK；没有发现可确认的缺失强引用。
  其中 `crc32_z` 在该 SDK 中存在。该抽查不能替代设备运行验证。
- 当前 Profile 应用通过 `codesign --verify --deep --strict`。
  但本地签名相关文件时间约为 21:29，晚于第二次崩溃，所以这不证明当时安装的包签名有效。

这些检查没有证明整个应用兼容 iOS 14.5，也没有把 TrollStore、注入环境或签名因素排除。

## 独立诊断包

输出目录：`build/ios/startup-probe/ios14-diagnostic-20260910/`

- `Art3m1s-startup-probe.ipa`：供同一台问题设备安装。
- `StartupProbe.app.dSYM`：有效调试信息，UUID `00C2ACF2-8D85-3F68-9A5A-CB66052DA57C`。
- `source-inventory.json`：源二进制 UUID、签名前 SHA-256 和加载顺序。

包名为 Art3m1s Probe，标识为 `moe.alphaly.art3m1s.startupprobe`，可与原应用并存。
它复制第二份报告对应 Profile 构建的 Frameworks，重新签名副本，使用原生 UIKit 启动界面。
未加入 `platform-application` 或 Unsandbox 权限，未重签名或修改原 Profile 应用。

点击运行后，先载入系统依赖，再按嵌入库的依赖关系逐项 `dlopen`，共 75 步。
每一步先写 `BEGIN` 并 `fsync`，返回后写 `OK`、`OPTIONAL MISSING` 或 `FAILED`。
同时记录加载映像的地址与 UUID，并将 stdout/stderr 写入日志。
日志位于诊断应用自己的 `Documents/startup-probe.log`，重新打开时保留并追加。

### 设备复测步骤

1. 使用 TrollStore 安装诊断 IPA；保留原应用及其数据。首次测试保持诊断包默认沙盒，不开启 Unsandbox。
2. 打开 Art3m1s Probe，保持 `Lazy`，点击右上角播放按钮。
3. 如果完成或显示错误，点击右上角分享按钮，导出 `startup-probe.log`。
4. 如果运行中闪退，重新打开诊断应用，先分享保留下来的日志，并提供新的系统 `.ips`。
5. 如果 Lazy 完成，可彻底结束诊断应用进程，重新打开，选择 `Now` 后再运行并分享日志。
   同一进程不允许重复运行，因为已经加载的库会影响结果。

`Now` 会提前解析通常延迟到首次调用的符号，其失败不必然等同于原应用启动时的失败。
最后一个没有对应 `OK` 的 `BEGIN` 是后续调查入口；故障也可能发生在该库的依赖或初始化函数中。
如果诊断界面本身打不开，请保留它的 `.ips`，这能把范围缩小到原生基础启动或安装环境。

### 限制

探针不启动 Flutter engine、Dart 入口或 Runner 中静态链接的插件注册逻辑。
逐项 `dlopen` 与原程序启动时同时加载依赖的顺序不同，应用标识、签名和权限也不同。
所以探针全部通过时，仍需获取原应用启动时的设备 Console 日志，或使用 LLDB 捕获故障线程、
`image list -o -f` 和 backtrace，再定位 engine 初始化、静态插件、加载顺序或环境相关问题。

## 本地验证

- 真机诊断包构建成功，最低系统版本 iOS 13.0；入口可执行文件仅链接系统库。
- dSYM UUID 匹配，`dwarfdump --verify` 检查通过且包含 `main.m` 的编译单元。
- 签名深度校验、IPA CRC 与 `Payload/` 布局检查通过，无 `__MACOSX`。
- 构建后重新校验源清单，原 Profile 应用的 28 个源二进制 SHA-256 全部保持不变。
- iOS 26.5 / iPhone 17 Pro 模拟器上，使用既有 Debug 模拟器 Frameworks 的独立版本分别完成 Lazy、Now 的 75 步加载，
  两次运行间结束并重启进程，旧日志完整保留。检查了完成后的界面截图，日志换行与控件布局正常。
  模拟器验证使用不同二进制，只用于验证工具流程，不能复现 iOS 14.5 / TrollStore 环境。
- 本机无可用 iOS 14.5 测试设备；用户提供的设备复测结果见下文。

重新构建命令，要求 macOS、Xcode 命令行工具和 Python 3：

```sh
python3 tool/ios_startup_probe/build.py build/ios/Profile-iphoneos/Runner.app
```

默认生成新的输出目录。`--output` 可指定尚不存在的目录。
模拟器构建额外传入 `--sdk iphonesimulator` 并选择模拟器 `.app`。
自动化验证可向探针进程传 `--probe-run`，另加 `--probe-now` 选择立即绑定。

## 2026-09-11 设备反馈

收到 `startup-probe(1).log`，记录系统为 iOS 14.5 (18E199)，来源 Runner UUID 与第二份崩溃报告一致。
27 个嵌入 Framework 的加载 UUID 均与诊断包源清单匹配，确认使用了对应 Profile 构建的库。

本次仅运行 `RTLD_LAZY`：75 个 BEGIN，69 个 OK，6 个 OPTIONAL MISSING，最终 COMPLETE，
没有 FAILED 或 EXCEPTION。全部 27 个嵌入库均加载成功。
六个缺失项为 `libswiftOSLog`、`libswiftSpatial`、`libswiftXPC`、`libswiftFileProvider`、
`libswiftDataDetection` 和 MetalFX，均已在源依赖清单中标记为弱链接。
这些缺失在加载阶段允许存在，但后续代码是否正确保护相关 API 调用仍未验证。

另有一条 `CFBundleDevelopmentRegion` 非字符串警告：初版诊断包未写入该键，
已在构建脚本补上字符串 `en`。已发出的 IPA 保持原样；无需为了这条警告重装，原包仍可继续测 Now。
该警告属于诊断包配置，不能作为原 Runner 崩溃的解释。

这一结果显著降低了“某个嵌入库在该系统上必然加载失败”的可能性。
仍需彻底结束诊断进程后以 Now 模式复测延迟符号；正式 Runner 的初始链接、静态插件、
Flutter engine、Dart 初始化以及签名和权限差异尚未覆盖。

## 测试交接状态

截至 2026-09-11，原测试人员暂时无法联系，iOS 14.5 的 Now 测试尚无结果，根因仍未确定。
新测试人员可按[诊断工具说明](../tool/ios_startup_probe/README.md)执行并反馈。
优先寻找 iOS 14.5、尤其是 iPhone 12 的 TrollStore 用户；其他设备的结果应作为独立样本记录。
先确认新设备上的原应用能否复现闪退，再分别测试诊断包的 Lazy 和 Now。
若原应用没有复现，诊断成功只能作为兼容性对照，不能证明原问题已解决。

下一步根据结果选择：Now 若失败，核对错误符号及其引用方；若两种模式都通过但原应用仍闪退，
再制作正式 Runner 的分阶段启动诊断，必要时采集设备 Console 或 LLDB 信息。
正式 Runner 的分阶段诊断包尚未实现，本提交仅包含动态库加载探针及其构建工具。
IPA、dSYM、源二进制清单和原始设备日志作为本地调查产物保留，不纳入 Git。

交接时重新构建的诊断包位于 `build/ios/startup-probe/handoff-20260911/`，包含
`CFBundleDevelopmentRegion=en` 修正，仍取自同一 Profile 应用。
IPA SHA-256 为 `cbe546cc04abad566bd95c44713f2e8704aaed13462a0e254394ff785ab7eb1e`，
探针 / dSYM UUID 为 `5C4A8800-6FF2-35A0-98BE-1A906F18C985`。
构建、签名深度校验、dSYM 校验和 IPA 完整性检查通过；28 个源二进制哈希保持不变。
该交接包尚未在 iOS 14.5 真机运行，上文设备反馈来自初版诊断包。

## 工作区中另外观察到的问题

以下是现存未提交修改中的问题，本次保留原样，未将其认定为上述 SIGSEGV 的原因：

- `scripts/ios_build_rust.sh` 给 Debug 加了 Cargo 不支持的 `--debug`，模拟器分支仍会传入该参数。
- `tool/build.dart` 将 Flutter Profile 模式映射到 Rust Debug，应在发布测试前明确这一选择。
- `_iosAppCandidates` 会跨构建模式寻找包并签名多个历史产物；缺少期望模式时可能打包旧版本。
- README 中“巨魔所需的 platform-application”表述没有通用依据。
  [TrollStore 官方说明](https://github.com/opa334/TrollStore#entitlements)指出它还会收紧部分沙盒行为；
  不宜把添加该权限当作已证实的通用修复。
