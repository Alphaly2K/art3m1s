# iOS 14.5 TrollStore 启动崩溃调查

## 结论与证据范围

2026-09-11 更新：目前证据最强的解释是 `media_kit_libs_ios_video` 内的 `Mpv.framework`
依赖未声明的系统符号，原启动在 dyld 解析符号时失败，并可能在生成终止信息时再次访问无效内存。
Native Trace 在加载 Mpv 前已经加载 AVFoundation / AVFAudio，能够解释两种入口的结果差异。
已补充生产链接配置并完成 Profile 构建验证。随后用户确认分发的普通入口修正版在原 iOS 14.5
设备上已没有启动问题；这是启动复测通过，不表示文件访问、音视频和性能的所有项目均已验收。
该结果进一步支持链接修正，但此前签名等变量及设备符号化限制仍然保留。

同次反馈中的另一台 iOS 17.3 注入环境设备仍白屏，Native Trace 可启动，已单独记录于
[iOS 17.3 白屏调查](ios17-startup-white-screen-2026-09-11.md)，不将其混同为原 iOS 14.5 崩溃。

这不是已完成的设备符号化：设备可能越狱，实际 dyld、系统框架或内存代码可能与官方固件不同。
下文的官方 dyld 地址匹配是有多项交叉验证的推断，不能代替故障进程的映像和指令数据。
移除 `flutter_file_dialog` 未解决问题，也没有证据支持继续删除 `FileSelectorPlugin`。

两份系统报告均缺少调用栈和 Binary Images，且报告生成器自身提示
`Failed to create CSSymbolicatorRef - corpse still valid`。
仅有 Runner dSYM 不能解决缺失映像基址的问题；本轮另用同系统构建的官方 dyld 进行假设检验。
该提示描述的是报告生成失败，不能直接当作应用崩溃原因。

设备为 iPhone13,2，iOS 14.5 (18E199)。设备是否越狱、原安装是否开启 Unsandbox 暂时未知。

Native Trace 已在 iOS 14.5 两个不同进程中完成原 Runner 插件注册和 Flutter 首帧渲染。
这一结果证明该加载流程可运行；本轮优先补齐依赖声明，原生壳保留为后备方案。

## Mpv 依赖与 dyld 故障路径复核

### 包内可以直接确认的事实

使用匹配第二份报告的 `Fix(1).ipa`，而非 UUID 不匹配的下载目录 fix 包。
Mpv 的普通绑定表中有四个非弱 flat-namespace 引用：

| 符号 | 绑定地址 | 系统提供者 |
| --- | --- | --- |
| `_AVAudioSessionCategoryPlayback` | `0x110000` | AVFAudio，iOS 14.5 的 AVFoundation 重导出它 |
| `_AVAudioSessionModeMoviePlayback` | `0x110008` | 同上 |
| `_OBJC_CLASS_$_AVAudioSession` | `0x143208` | 同上 |
| `_OBJC_CLASS_$_EAGLContext` | `0x143210` | OpenGLES |

另有十个 CoreVideo 的 CVOpenGLES / CVPixelBuffer 延迟绑定。Mpv 的加载命令未声明
AVFoundation、AVFAudio、OpenGLES 或 CoreVideo，原 Runner 直接依赖中也没有 AVFoundation。
这意味着它依赖其他框架或宿主预先提供这些全局符号，而不是拥有完整的显式依赖声明。
缺少直接声明本身不证明实际启动闭包一定缺少提供者，因为系统库还可能间接加载它们。

真机 Trace 日志第 275/276 行及 1409/1410 行，分别在两次加载开始前记录了
AVFoundation / AVFAudio。Mpv 到第 584、1715 行的 `BEGIN 68/77` 才开始 `dlopen`。
日志可确认提供者已经存在，但没有记录到底是哪次 UIKit 调用或哪条间接依赖加载了它。
它解释了为什么逐项加载和 Now 全部通过仍不能排除原入口的符号解析问题。

复核命令：

```sh
xcrun otool -L build/ios/startup-probe/fix1-analysis-20260911/Payload/Runner.app/Frameworks/Mpv.framework/Mpv
xcrun llvm-objdump --macho --bind build/ios/startup-probe/fix1-analysis-20260911/Payload/Runner.app/Frameworks/Mpv.framework/Mpv
xcrun dyld_info -imports build/ios/startup-probe/fix1-analysis-20260911/Payload/Runner.app/Frameworks/Mpv.framework/Mpv
```

### 官方 dyld 对照与设备差异限制

对照文件来自 Apple 的 `iPhone13,2,iPhone13,3_14.5_18E199_Restore.ipsw`，
其 Restore ramdisk `038-45071-293.dmg` 内的 `/usr/lib/dyld`。
从 Apple CDN 用 ZIP 范围读取取得 ramdisk，没有下载整个 IPSW；只读挂载后复制 dyld，已卸载磁盘。
固件地址可由 [IPSW 元数据](https://api.ipsw.me/v4/device/iPhone13,2?type=ipsw) 中的 18E199 项复核。

- 本地文件：`build/ios/startup-probe/ios14-system-analysis-20260911/dyld`。
- arm64e UUID：`CA553810-334F-3516-92EC-AEDEAA5C0426`。
- SHA-256：`98e2170b7a36a71545657caf90c45cb6eb8fa0bd3cb27d69c9c67a771be40fab`。

假设故障处代码与该对照文件相同，用 PC 的候选指令偏移推导基址后，还可同时解释 LR、
全局数据地址和实际无效访存。第二份报告的候选 dyld 基址为 `0x102d3c000`：

| 寄存器 | 报告地址 | 对照 dyld 偏移及含义 |
| --- | --- | --- |
| PC | `0x102d91204` | `0x55204`，`strlen + 4` |
| LR | `0x102d90be8` | `0x54be8`，`__platform_strlcpy + 40` |
| x17 | `0x102d8f0d8` | `0x530d8`，`__simple_bprintf + 512` |
| x23 / x27 | `0x102db8000` | `0x7c000`，`dyld_all_image_infos` |
| x26 | `0x102db8778` | `0x7c778`，`dyld::gProcessInfo` |

第一份报告以 `0x1026d4000` 为候选基址时，也得到上述五个相同偏移。
不能把 x17 等寄存器当成实际调用栈；这里使用的是多个地址布局的一致性。

对照 `strlen` 的前两条指令是：

```asm
0x55200: and x1, x0, #0xfffffffffffffff0
0x55204: ldr q0, [x1]
```

第二份报告的 `x0 = 0x10453180a` 经 16 字节对齐正好得到 `x1 = 0x104531800`，
与故障地址一致。`strlcpy` 又在 `0x54be4` 调用此 `strlen`，返回地址正好是 LR 对应的
`0x54be8`；其保存参数的方式解释了 `x0 = x21` 和 `x2 = x22`。
这些证据比单独挑一个基址后得到函数名更强，但不能证明设备内存未经修改。

两份原报告均无设备 dyld UUID 和 Binary Images。Trace 的映像记录也未包含 `/usr/lib/dyld`；
其中的 `/usr/lib/system/libdyld.dylib` 是另一个映像，不能拿它的 UUID 代替。
Trace 记录的 452 个不同映像路径均来自系统目录或诊断包，没有发现常见注入库路径。
这不能排除越狱、按应用启用的注入、隐藏映像、系统文件替换或保持 UUID 的内存补丁，
也不能证明 Trace 与原应用拥有相同的加载环境。官方 ramdisk 还不是设备运行内存的直接副本。

### 丢失符号与二次崩溃的推断

对照 dyld 的 `halt` 构造 2048 字节终止信息：先放 20 字节头部，再复制目标库路径、
引用方路径和符号名。两份报告都满足 `0x800 - 0x9b = 0x765`，恰好对应剩余缓冲区长度。
用报告中的安装目录构造 Mpv 路径，长度都是 119 字节：

```text
20 + strlen("flat namespace") + 1 + strlen(".../Runner.app/Frameworks/Mpv.framework/Mpv") + 1
= 20 + 14 + 1 + 119 + 1
= 155 = 0x9b
```

Mpv 文件偏移 `0x14580a` 是 `_AVAudioSessionCategoryPlayback` 字符串，
它也是普通绑定表中的第一个 flat-namespace 引用；其 16 KB 页内偏移 `0x180a`
与两次无效源指针的页内偏移一致。页内偏移和路径长度不是唯一标识，不能单独确定符号。
将它们与代码、寄存器、依赖和 Trace 记录一起考虑，才支持 Mpv 的这项引用为首要候选。

Apple 开源 [dyld-852.2 ClosureBuilder.cpp](https://github.com/apple-oss-distributions/dyld/blob/dyld-852.2/dyld3/ClosureBuilder.cpp)
第 1505 行附近，缺失符号错误会复制库路径，却直接保存 `symbolName` 指针；
第 3084 行的退出清理会解除临时映像映射。
[dyld2.cpp](https://github.com/apple-oss-distributions/dyld/blob/dyld-852.2/src/dyld2.cpp)
第 6296 行附近在构建失败后调用 `halt`，第 4430 行附近再复制错误符号。
这一对象生命周期可产生悬空指针，符合本次在 `strlen` 读取无效地址的特征。
因此 SIGSEGV 可能是报告符号缺失时的二次故障，而不是业务插件在运行时崩溃。
源码和官方机器码构成机制解释，尚未取得设备原始错误文本或内存来确认完整调用链。

可直接检查小段机器码，不要给以下命令加 `--macho`，该模式可能忽略地址范围：

```sh
xcrun llvm-objdump -d --start-address=0x55200 --stop-address=0x55220 build/ios/startup-probe/ios14-system-analysis-20260911/dyld
xcrun llvm-objdump -d --start-address=0x54bc0 --stop-address=0x54c10 build/ios/startup-probe/ios14-system-analysis-20260911/dyld
xcrun llvm-objdump -d --start-address=0x5260 --stop-address=0x52dc build/ios/startup-probe/ios14-system-analysis-20260911/dyld
```

### 生产修正与验证状态

新增 `ios/Flutter/MediaKit.xcconfig`，由 Debug 和 Release 配置包含，Profile 复用 Release。
通过 `-Wl,-needed_framework,AVFoundation`、CoreVideo、OpenGLES 把已有导入的提供者
加入 Runner 的显式启动依赖，避免被未使用依赖剥离。保留继承的 CocoaPods 链接参数。
采用 AVFoundation 而非直接强链接 iOS 14 才拆出的 AVFAudio，以保留项目 iOS 13 的部署目标。

独立输出目录 `build/ios/link-fix-validation-20260911/Profile-iphoneos/` 已完成
无签名 Profile 构建，Runner / dSYM UUID 均为 `72E38409-E4A5-3EBF-A665-2A0BEBACA393`。
`otool -L` 确认三个框架实际存在，`dyld_info -validate_only` 与 `dwarfdump --verify` 通过。
与原 IPA 对照，Runner 直接依赖新增 AVFoundation 和 OpenGLES，没有删除原有依赖；CoreVideo 原已存在。
新旧 Mpv 的整个文件 SHA-256 一致，均为
`3dad619c02fc89da9958131887d698fb6fe38280e2bb9e1d3750a04cf47c9728`。
应用标识、最低 iOS 版本、两项文件共享设置和 Scene manifest 解析结果一致。
Release 真机及 Debug 模拟器的 `-showBuildSettings -json` 也确认新参数和继承的 Mpv 链接参数同时生效；
实际完整构建验证只执行了 Profile。
原 `build/ios/Profile-iphoneos/Runner.app/Runner` 的 SHA-256 仍为
`2083e48cb79b6e74bbd6c267eab9050b4175de4146719eee337ea15527fa6cd7`，原证据产物未被替换。
构建日志与 dSYM 校验日志保存在上述 `ios14-system-analysis-20260911` 目录。

本轮构建命令：

```sh
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Profile -sdk iphoneos -destination generic/platform=iOS \
  -disableAutomaticPackageResolution \
  BUILD_DIR="$PWD/build/ios/link-fix-validation-20260911" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

这是补齐依赖声明的候选修复，不依赖设备使用官方 dyld 的假设才有意义；
但不能因此保证它能修复被修改的系统环境。启动代码、数据路径、bundle ID 和权限未因这项修改改变，
没有引入 Trace 的逐步等待、日志包装或代理替换。框架提前加载仍可能影响冷启动时间和驻留内存，
本地构建验证不能给出真机性能结论，也不等于文件选择、读写和音视频功能已验收。

下一步应验证原问题设备上的普通入口修正版，保留原数据和原安装设置，并记录实际构建与签名。
本次本地编译基于当前工作区，不是与旧 IPA 仅一个变量不同的设备 A/B 试验。
如需确认故障函数，应取得原失败进程的实际 dyld 映像及 PC 附近指令或早期 Console 信息；
仅取得相同 UUID 仍不能排除运行时补丁。原生壳暂作为后备，无需先继续扩大诊断包。

### 普通入口修正版交接

按用户要求，将上述 Profile 构建复制后签名打包，输出位于
`build/ios/mpv-link-fix-20260911/Art3m1s-1.3.0-ios14-mpv-link-fix.ipa`。
大小 34,761,970 字节，SHA-256 为
`a3ccf539e1520ce15e58669b18e1159e8f035ca95e79eddec597f012c90a076d`。
同目录保存 `TESTING.md`、`package-manifest.json` 和三份匹配 dSYM。
包内 Runner UUID 仍为 `72E38409-E4A5-3EBF-A665-2A0BEBACA393`。

使用与成功 Probe / Trace 相同的 ad-hoc 签名方式，不附加 entitlements；没有使用工作区的
`TrollStore.entitlements`，也没有修改该文件。最终安装权限取决于 TrollStore 和设备设置。
这与原 Fix(1).ipa 主程序无签名、以及本地后来加入自定义权限的版本均有差异，
复测结果应保留该变量，不声称是严格单变量实验。

与原 Fix(1).ipa 对照，全部 Info.plist 解析内容一致，全部 27 个嵌入框架的 section 内容、
地址、文件偏移、大小和导入语义相同。objective_c 的重建 UUID 有变化，已留存新 dSYM；
其变化未涉及上述 section 或导入。Runner 的导入符号和提供库多重集合一致，但重新链接改变了
GOT 排列、相关指令、UUID 和框架加载命令。签名没有改变任何 section 或导入语义。
包内 28 个 Mach-O 格式校验、深度签名、IPA CRC、Payload 布局及实际打包的 Runner 校验通过。

本包仍使用正式应用标识和版本 1.3.0，供 TrollStore 覆盖安装，需保留原数据和安装设置。
它直接启动 Flutter，没有 Trace 界面、手动播放、逐步等待或日志分享功能。
测试说明要求复核多次冷启动、原数据、文件导入、音视频和后台返回；失败时获取新的系统报告。
交接时尚未收到真机结果；随后用户确认 iOS 14.5 已没有启动问题，详见文首最新状态。

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

随后收到 `startup-probe(2).log`：Now 运行于新进程 68534，与 Lazy 的 67995 不同。
2026-09-11 00:46:10 UTC 开始，00:46:24 UTC 完成；同为 75 个 BEGIN、69 个 OK、
6 个 OPTIONAL MISSING，27 个嵌入库 UUID 全部匹配，没有 FAILED 或 EXCEPTION。
六个可选缺失项与 Lazy 完全相同。此前另一个进程有 UIKit 键盘服务连接失效消息，
不能据此解释已完成的 Now 测试或原 Runner 崩溃。

用户确认同一台设备上的正式 Art3m1s 仍然打开即闪退。
两种模式通过显著降低了“嵌入库加载或其普通延迟绑定在该系统上必然失败”的可能性，
但正式 Runner 的初始链接、静态插件、Flutter engine、Dart 初始化及签名和权限差异尚未覆盖。

## 测试交接状态

2026-09-11 已收到 iOS 14.5 的 Now 结果，Lazy / Now 均通过，原应用仍崩溃，根因未确定。
新测试人员可按[诊断工具说明](../tool/ios_startup_probe/README.md)执行并反馈。
优先寻找 iOS 14.5、尤其是 iPhone 12 的 TrollStore 用户；其他设备的结果应作为独立样本记录。
先确认新设备上的原应用能否复现闪退，再分别测试诊断包的 Lazy 和 Now。
若原应用没有复现，诊断成功只能作为兼容性对照，不能证明原问题已解决。

下一步测试 Art3m1s Native Trace：先进入 Probe 的原生日志界面，再手动启动原 Runner 副本和 Flutter UI。
闪退后重新打开同一个诊断应用，先分享已保留的日志。必要时采集设备 Console 或 LLDB 信息。
构建和测试步骤见[诊断工具说明的第二阶段](../tool/ios_startup_probe/README.md)。
IPA、dSYM、源二进制清单和原始设备日志作为本地调查产物保留，不纳入 Git。

交接时重新构建的诊断包位于 `build/ios/startup-probe/handoff-20260911/`，包含
`CFBundleDevelopmentRegion=en` 修正，仍取自同一 Profile 应用。
IPA SHA-256 为 `cbe546cc04abad566bd95c44713f2e8704aaed13462a0e254394ff785ab7eb1e`，
探针 / dSYM UUID 为 `5C4A8800-6FF2-35A0-98BE-1A906F18C985`。
构建、签名深度校验、dSYM 校验和 IPA 完整性检查通过；28 个源二进制哈希保持不变。
该交接包尚未在 iOS 14.5 真机运行，上文设备反馈来自初版诊断包。

## 第二阶段 Native Trace 产物

当前交接包为 `build/ios/startup-probe/launcher-final-20260911/Art3m1s-native-trace.ipa`，
显示名 Art3m1s Trace，独立标识 `moe.alphaly.art3m1s.startuplauncher`。
它来自第二份报告对应的 Profile 应用，沿用已在问题设备通过的 Probe 原生流程：
先创建 `Documents/startup-trace.log` 和带分享按钮的原生界面，点击播放后执行原 75 步加载，
再加载 RunnerPayload 和 RunnerBridge，共 77 步。随后调用原 Runner AppDelegate，
创建原 Main storyboard，完成插件注册和 Flutter 启动，成功时显示真实 Flutter UI。
Flutter 页面顶部保留原生返回和分享按钮；重新打开应用不会自动运行 Flutter，可先导出旧日志。

- IPA SHA-256：`e48e8b9581d92fdf6088bd8589f7ce2b077ac1db1e1924acc3ce8d82d9ea5ea0`。
- 原生入口 / dSYM UUID：`F0392570-6E32-3A95-BB78-D8AF6603575B`。
- RunnerBridge / dSYM UUID：`8096B5D0-9F97-34AB-9DFD-A2842CCED06B`。
- RunnerPayload UUID 保持 `2F501818-B219-3B32-823A-473F11C6C223`，保留原 Runner dSYM。
- 未重新编译 Runner、Dart、Flutter 或插件。Runner 副本由可执行文件转换为可延迟加载的 dylib，
  调整 Mach-O 头部与加载信息；原 section 内容、地址、偏移、依赖顺序、rpath、
  618 项符号绑定、2538 项重定位和 52 项导出保持一致。
- 原生入口仅链接系统库，Flutter、Runner 和日志桥接模块在点击播放后才加载。
  签名深度校验、IPA CRC 和布局检查通过；28 个源二进制 SHA-256 保持不变。
- 用同一转换函数将小型模拟器可执行文件转换为 dylib，由独立宿主延迟加载，
  构造函数、Objective-C 类注册、全局指针重定位和导出函数调用均通过，原 main 未执行。
  该测试覆盖转换机制，不等于验证 Profile Runner 已能在 iOS 14.5 上运行。
- iOS 26.5 模拟器已完成原生界面、77 步加载、应用代理、createShell、插件注册、
  launchEngine、Dart 平台调用，记录到 `FLUTTER_FIRST_FRAME`，截图显示真实资料库页面。
  结束并重新启动进程后，旧日志保留，界面停在原生页，没有自动重跑 Flutter。
  本机锁屏阻止了分享和返回按钮的实际点击验证，这项尚未完成。

模拟器使用旧 Debug 产物，仍包含 flutter_file_dialog，并直接使用 Runner.debug.dylib；
只能验证工具流程，不能代替 Profile 可执行文件转换后的 iOS 14.5 真机结果。
日志和截图归档于 `build/ios/startup-probe/launcher-simulator-20260911/`。

Native Trace 使用独立数据容器和签名，默认不复制原应用的特殊权限。
它通过原生导航界面调用 Runner 代理并创建 Flutter 视图，改变了加载顺序和启动时序，
也没有复刻原应用完整的 Scene 生命周期。通过并不能证明原问题已修复。
进程级崩溃仍会关闭整个应用；已落盘日志可在下次原生启动时导出，无需依赖 Files 中的目录可见性。
日志创建失败或原生入口自身崩溃仍可能导致无日志。随后收到的真机结果见下文。

## Native Trace 真机反馈与后续静态调查

用户提供 `startup-trace.log`，系统为 iOS 14.5 (18E199)。其中进程 70730 只打开过原生页，
进程 70734、70770 分别执行了一次 Lazy，均为 77 个 BEGIN、71 个 OK、6 个 OPTIONAL MISSING。
27 个嵌入框架、RunnerPayload、RunnerBridge 和原生入口共 30 个映像 UUID 均匹配最终交接包。
没有 FAILED、EXCEPTION 或 HOOK_SKIPPED。

两轮均完成 AppDelegate、createShell、6 个实际调用的插件注册、launchEngine 和 Dart MethodChannel 调用。
分别于 06:18:02 UTC、06:18:30 UTC 记录 `FLUTTER_FIRST_FRAME`，用户确认 Flutter 页面启动成功。
这证明执行了原 Flutter 应用，而不仅是打开原生日志界面；不代表游戏、音视频、文件选择和完整后台生命周期已通过。

日志中仍需保留的现象：

- 6 个可选库缺失与此前 Probe 一致，没有阻止这两次启动。
- 最初原生进程出现 UIKit 键盘服务连接失效，不能用它解释正式 Runner 的原始闪退。
- 第一次首帧后出现 `No windows have a root view controller, cannot save application state`。
  紧接着出现新进程，日志本身无法区分手动退出、系统结束或崩溃。
  诊断壳替换应用代理并复用原生导航窗口，这条状态保存警告属于生产化前必须核对的生命周期问题。
- 第二轮的 `MAIN_QUEUE_ALIVE_15S` 实际在 06:28:59 UTC 执行，比安装计时器晚约 10 分 29 秒。
  后台挂起和主线程阻塞均可造成延迟；不能据此声称前台连续运行正常。

### platform-application 的时间线

用户指出原故障发生在最近添加该权限之前，Git 历史支持这一点：

- `git log --all -S 'platform-application' -- ios tool scripts README.md CHANGELOG.md` 没有结果。
- 故障前的 `171f362` 中，两个 entitlements 文件都不存在，`tool/build.dart` 的 iOS 路径只运行
  `flutter build ios --no-codesign`，尚无当前的补签名流程。
- 本地 entitlements 文件创建时间是 2026-09-10 20:34:44 +0800，晚于第一份报告的 15:45。
- 现存 Release / Profile 的 Runner 均在 21:29 被改写，晚于两份崩溃报告。
  当前签名携带该权限，不能反推最初安装文件也携带它。

因此，不把最近新增的 `platform-application` 当作最初崩溃的首要原因。
Git 不能还原设备上安装后全部有效权限；上述结论是时间线约束，不是对安装环境的完整证明。

### 本轮离线检查

没有重新构建或分发诊断 IPA，使用已有 Profile 应用与已通过的 Native Trace 产物进行检查：

- 27 个原框架与壳内副本逐 section 对照：内容 SHA-256、虚拟地址、文件偏移、大小全部一致。
  这比只核对 UUID 更进一步，排除了壳偷偷替换框架实现的解释。
- 28 个原二进制均通过本机 `dyld_info -validate_only`。
- 对具有经典 dyld 信息的二进制共检查 9592 项绑定、134207 项重定位：未发现写入地址超出
  可写 segment、正依赖序号超出库列表或 `@rpath` 嵌入依赖缺失。
  本机新版 dyld 校验不能替代旧系统 dyld 的执行，也未遍历验证全部旧系统导入符号。
- `Mpv` 有 14 项 flat-namespace 绑定，`objective_c` 有 72 项；Probe 显式预加载其系统依赖。
  这是对初始装载顺序敏感的具体机制，但现有 Now 成功记录不支持直接判定其中某个符号缺失。
- `SceneDelegate` 及 Scene manifest 从初始提交 `a6d6394` 已存在，当前 SceneDelegate 没有自定义逻辑。
  对本地 Flutter 3.44.2 的 Scene、AppDelegate、隐式引擎调用路径检查，未发现可确认的 iOS 14.5 错误。
  壳没有执行原 Scene 连接路径，因此也不能排除它。
- 项目的 Swift 语言模式为 5.0。公开的 Swift 6 Scene 迁移编译错误、iOS 26 ProMotion 启动崩溃、
  chained-fixups 格式错误与本次环境或故障类型不匹配，未套用它们的修复。

在取得官方 dyld 对照文件之前，优先调查的是初始 dyld 加载及初始化时序，其次是 Scene 路径。
33 ms 的原始失败和缺失回溯与早期失败相符，但没有映像基址，仍不能证明 PC 属于 dyld 或确定发生在 main 前。
本轮新增的地址交叉验证见文首，后续若要最终定因，仍应从原正式包的失败中取得映像、指令或早期设备 Console；
可以针对已有安装包收集，不必先增加一轮 Probe。

生产原生入口的可行性及边界见[生产化评估](ios-native-launcher-assessment-2026-09-11.md)。

## FileSelectorPlugin 线索复核

用户转述另一模型将故障定位到 `FileSelectorPlugin`，并指定它分析的包位于下载目录。
实际文件名为 `/Users/alphaly/Downloads/Art3m1s-1.3.0-fix.ipa`，SHA-256 为
`7fc2fb6f19a9cb347e782098e4db8800675473697ba711573274dcf79c3c2a60`。
解包到 `build/ios/startup-probe/sol-fix-analysis-20260911/`，未修改原 IPA 或正式构建。

### 分析包与崩溃报告不对应

| 来源 | Runner UUID |
| --- | --- |
| 下载目录的 `Art3m1s-1.3.0-fix.ipa` | `ED810794-F485-36CF-B19F-0B1E2C734E29` |
| 15:45 崩溃报告及本地 Release / dSYM | `D04DE598-F51A-3E33-ADB6-2096ECBCA46E` |
| 20:49 崩溃报告及本地 Profile / dSYM | `2F501818-B219-3B32-823A-473F11C6C223` |

下载包的 App.framework UUID 也不同，为 `0C7143A3-6602-9FE8-4C4F-F302847C4547`；
本地 Profile 为 `8228BCF3-A0A5-D562-A30D-B0EB438E4CED`。
二者虽然都显示版本 1.3.0，但不是同一次构建。实际代码布局也不同，例如
`FileSelectorPlugin.register(with:)` 的 specialized 函数体在下载包的首选虚拟地址为
`0x1000169f8`，在 Profile 为 `0x10000c394`。
这些是未加 ASLR slide 的二进制地址，不是报告中的运行时地址。

可用下列命令复核 UUID：

```sh
xcrun dwarfdump --uuid build/ios/startup-probe/sol-fix-analysis-20260911/Payload/Runner.app/Runner
xcrun dwarfdump --uuid build/ios/Profile-iphoneos/Runner.app/Runner build/ios/Profile-iphoneos/Runner.app.dSYM
```

因此，不能拿下载包的符号布局解释这两份报告；即便换用匹配的 Profile / dSYM，
原报告缺失映像加载基址的问题仍然存在。随后从用户提供的共享对话取得了具体推导，
复核如下；此结论不等于排除该插件参与故障。

### 找到与第二份报告匹配的原 IPA

随后收到 `/Users/alphaly/Library/Mobile Documents/com~apple~CloudDocs/Fix(1).ipa`，
SHA-256 为 `366fc556bb68060a9fcfb14007cdcf1fe162fecafbd709983f7cdbdb95a41f09`。
解包到 `build/ios/startup-probe/fix1-analysis-20260911/`。

- Runner UUID 为 `2F501818-B219-3B32-823A-473F11C6C223`，匹配 20:49 的报告和本地 Profile dSYM。
  App.framework UUID 为 `8228BCF3-A0A5-D562-A30D-B0EB438E4CED`，也匹配 Profile。
- 原 IPA 与当前 Profile 的 Runner 加 27 个 Framework，所有 section 的内容 SHA-256、
  虚拟地址、文件偏移、大小均一致；各二进制签名前的 `__LINKEDIT` 内容也一致。
  加载命令的差异限于签名命令及 `__LINKEDIT` 的文件和映射大小，其他 segment 属性未变。
  两份应用的 Info.plist 解析结果相同。
- IPA 内的 Runner 没有代码签名，未包含 `platform-application` 签名权限。
  当前本地 Runner 比它多出 `LC_CODE_SIGNATURE` 和签名数据，与此前补签名的时间线一致。
  这不能还原 TrollStore 在设备上安装时生成的有效签名和权限。
- 直接反汇编此 IPA 的 Runner，`0x100019204` 仍是下文的栈读取指令。
  因而下文对 Sol 所猜基址的反证并非使用了错误代码版本；但原报告仍缺少实际加载基址，
  找回对应 IPA 并不等于可以确定真实故障函数。

### 共享对话中的基址推导

[共享对话](https://chatgpt.com/share/6aa3a826-3c00-83ee-89c3-dc856242df4f)中，
Sol 明确注意到了 UUID 不匹配，将插件定位称为启发式线索，并未声称完成精确符号化。
它由 `x23/x27 = 0x102db8000` 及下载包的数据段布局猜测 Runner 基址为 `0x102d78000`，
再用 PC/LR/x17 相对该基址的偏移，检查下载包的代码。这一假设在匹配的 Profile 产物上不成立：

| 检查项 | 下载的 fix IPA | 报告对应的 Profile |
| --- | --- | --- |
| `__DATA_CONST` 相对 image base | `+0x40000` | `+0x28000` |
| `__DATA` 相对 image base | `+0x44000` | `+0x2c000` |
| PC 假定偏移 `+0x19204` | `FileSelectorConfig.fromList` | `__isPlatformVersionAtLeast + 284` |
| LR 假定偏移 `+0x18be8` | Sol 据此关联 FileSelector | `SetUpWAKELOCKPLUSWakelockPlusApiWithSuffix`，`messages.g.m:173` |
| x17 假定偏移 `+0x170d8` | Sol 据此关联 presenter | `LegacyUserDefaultsApiSetup.setUp` |

寄存器 x23/x27 不是系统规定的 Runner 基址或数据段起点，不能仅凭它们相等确定所属映像。
Profile 的 `+0x40000` 实际位于 `__LINKEDIT`，并非上述用于推断的数据段。

保持 Sol 假设的基址，用匹配的 dSYM 复核的命令是：

```sh
xcrun atos -arch arm64 -o build/ios/Profile-iphoneos/Runner.app.dSYM/Contents/Resources/DWARF/Runner -l 0x102d78000 0x102d91204 0x102d90be8 0x102d8f0d8
xcrun llvm-objdump -d --start-address=0x1000191d0 --stop-address=0x100019230 build/ios/Profile-iphoneos/Runner.app/Runner
```

Profile 的 `0x100019204` 是 `ldp x22, x21, [sp, #0x10]`。
按报告的 `sp = 0x16d3edbc0`，它读取 `0x16d3edbd0` 和 `0x16d3edbd8`，
不对应报告中的无效地址 `0x104531800`。这进一步反对所猜基址；
不能把此处符号输出反过来当成版本检查函数已经被确认崩溃。

下载包的同一偏移确实是 `FileSelectorConfig.fromList` 内的 `mov w4, #7`，
但这条指令本身没有内存访问；后面的 `bl` 也不能视为 PC 已经进入 `_swift_dynamicCast`。
另外，`fromList` 是接收文件选择消息时的解码路径，注册消息处理器不等于执行解码。
因此，该偏移巧合不足以支持“插件注册阶段是首要原因”的排序。

共享对话使用的是只加载库的旧 Probe 结果，尚未包含后来的 Native Trace 首帧成功记录。
下面的两次实际插件注册成功是评估该假设时必须加入的新证据。

### 插件路径与已有真机证据

- `file_selector_ios` 与此前移除的 `flutter_file_dialog` 是两个插件。
  当前锁定 `file_selector_ios 0.5.3+5`，Profile 中仍有其实现，静态链接在 Runner 内。
- 源码 `FileSelectorPlugin.register` 创建 provider 和插件实例，初始化空的
  `Set<PickerCompletionBridge>`，再注册 Pigeon `FlutterBasicMessageChannel`。
  下载包及 Profile 的注册函数反汇编都符合此流程；注册不直接创建或显示文件选择器。
- `DefaultViewPresenterProvider` 在初始化时只保存 registrar；访问 `registrar.viewController`
  和创建 `UIDocumentPickerViewController` 位于后续 `openFile` 路径。
  因而不能仅凭没有可用窗口或 Documents 目录就判定注册必然崩溃。
- 已通过的 Native Trace 保留 Profile 的该插件代码。设备日志第 1098/1099 行及
  2226/2227 行分别记录两次注册 BEGIN/END，之后第 1136、2264 行出现 Flutter 首帧。
  这反对“这份插件在 iOS 14.5 必然注册失败”的解释，但壳改变了初始化顺序和生命周期，
  尚不能排除正式入口下的 Swift metadata、运行库或 registrar 状态问题。
- Trace 当前只跟踪 MethodChannel，未跟踪 Pigeon 使用的 BasicMessageChannel；
  不能用日志没有 `openFile` 来证明文件选择接口从未被调用。

公开的 [flutter/flutter#175382](https://github.com/flutter/flutter/issues/175382)
也有 `FileSelectorPlugin.register` 栈帧，但它是 iOS 18.6.2、Flutter 3.35.3、
`file_selector_ios 0.5.3+2` 的 Debug 应用脱离调试器启动，报告明确说明 Release 正常。
其故障为 `swift_getObjectType + 40` 访问空指针；本次两份报告是 Profile / Release、
非零无效地址且无调用栈。它提供调查方向，不能视为本次已命中的已知问题。

没有找到足以删除、降级或修改该插件的依据。后续 Mpv / dyld 推导和生产链接修正见文首；
未重构生产入口或生成新的诊断 IPA。

## 工作区中另外观察到的问题

以下是现存未提交修改中的问题，本次保留原样，未将其认定为上述 SIGSEGV 的原因：

- `scripts/ios_build_rust.sh` 给 Debug 加了 Cargo 不支持的 `--debug`，模拟器分支仍会传入该参数。
- `tool/build.dart` 将 Flutter Profile 模式映射到 Rust Debug，应在发布测试前明确这一选择。
- `_iosAppCandidates` 会跨构建模式寻找包并签名多个历史产物；缺少期望模式时可能打包旧版本。
- README 中“巨魔所需的 platform-application”表述没有通用依据。
  [TrollStore 官方说明](https://github.com/opa334/TrollStore#entitlements)指出它还会收紧部分沙盒行为；
  不宜把添加该权限当作已证实的通用修复。
