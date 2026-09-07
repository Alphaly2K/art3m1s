# art3m1s.json 项目清单编写指南

`art3m1s.json` 是放在游戏目录（或 PFS 归档）里的项目清单文件，用来向宿主声明
游戏信息与默认配置。补丁/移植包作者把它随游戏文件一起分发，用户导入游戏时
宿主自动读取并预填资料库条目。

## 发现规则

- 文件名固定为 `art3m1s.json`（不区分大小写）。
- 位置：游戏根目录，或一级子目录（如 `patch/art3m1s.json`）。更深的层级不读取。
- PFS 归档与解包目录都支持；规则相同（按归档内路径深度计算）。
- 多处同时存在时取第一个命中；没有清单不影响游戏运行。

## 完整示例

```json
{
  "name": "Magical Charming!",
  "vndbId": "v12851",
  "translationEnabled": true,
  "translationPatchPath": "patch/zh.json",
  "environmentPatchEnabled": true,
  "experimentalElunaEnabled": false,
  "fontOverride": "font/sourcehansans-regular.otf",
  "reportedOs": "ps4",
  "inputGate": {
    "keyboard": false,
    "wheelToKeys": false
  }
}
```

所有字段均可选；缺省字段不改变对应设置。

## 字段说明

| 字段 | 类型 | 作用 |
| --- | --- | --- |
| `name` | 字符串 | 游戏名。导入时预填资料库显示名（优先于从目录名/标题的猜测）。 |
| `vndbId` | 字符串 | VNDB 编号（如 `v23658`）。导入时按 ID 精确查询官方标题与封面；不写则用名字模糊搜索。 |
| `translationEnabled` | 布尔 | 默认是否开启文本翻译。 |
| `translationPatchPath` | 字符串 | 翻译对照文件的**游戏内相对路径**（离线译文包）。 |
| `environmentPatchEnabled` | 布尔 | 默认是否启用环境兼容补丁（屏蔽特定渠道/平台校验脚本）。 |
| `experimentalElunaEnabled` | 布尔 | 默认是否启用实验性 Eluna E-Mote 后端。 |
| `fontOverride` | 字符串 | 覆盖字体（TTF/OTF）的**游戏内相对路径**。脚本自带字体缺译文字形时用它替换全部脚本字体的字形来源。 |
| `reportedOs` | 字符串 | 上报给脚本的机种串（`var system="os"` 的返回值）。移植版游戏把存档等功能开关在机种判断上时用它伪装，见下文。 |
| `inputGate` | 对象 | 输入门控策略（结构见下）。 |

## `inputGate` 输入门控

控制宿主喂给引擎的输入类别与转发行为。全部字段可选，缺省为放行/开启。

```json
"inputGate": {
  "keyboard": false,
  "mouseButtons": true,
  "mouseMove": false,
  "touch": true,
  "wheelToKeys": false,
  "twoFingerRightClick": false,
  "twoFingerScrollWheel": true,
  "blockedKeys": [27],
  "keyRemap": { "13": 32 }
}
```

| 字段 | 缺省 | 含义 |
| --- | --- | --- |
| `keyboard` | `true` | 物理键盘输入总开关。移动端移植游戏的脚本没特判键盘时关掉，避免引擎默认按键行为覆盖脚本逻辑。 |
| `mouseButtons` | `true` | 鼠标键总开关（触屏 tap 在引擎里就是左键，一般保持开启）。 |
| `mouseMove` | `true` | 指针位置（hover/移动）上报开关。 |
| `touch` | `true` | 真实触摸点上报开关（多点/flick 等）。 |
| `wheelToKeys` | `true` | 滚轮 → 标准方向键（VK_UP 38 / VK_DOWN 40）转发。 |
| `twoFingerRightClick` | `true` | 双指触摸 → 鼠标右键转发。 |
| `twoFingerScrollWheel` | `false` | 双指拖动 → 滚轮转发（菜单/回想界面滚动）。 |
| `blockedKeys` | `[]` | 按键黑名单（Windows VK 码），键盘开启时仍拦截。 |
| `keyRemap` | `{}` | 按键重映射表（VK → VK，作用于按下与抬起）。 |

预置 profile 之外自定义了规则时，编辑对话框的「输入方式」会显示"自定义"。

## `reportedOs` 机种上报

可选值：`windows`、`iphone`、`android`、`webassembly`、`switch`、`ps4`。

典型场景：多平台移植的游戏把系统存档等关键功能开关在机种判断上。例如
某游戏只在 `getos` 上报 `switch`/`ps4` 时才执行系统保存路径，桌面运行该包时
设置 `"reportedOs": "ps4"` 即可让设置正常持久化。

注意：机种上报只改变脚本读到的机种串，不改变平台能力。若目标机种分支启用了
该分支特有的其它行为（如手柄专属 UI、平台接口调用），可能引入新问题——请按
游戏实测选择。例如上述游戏伪装 `switch` 会启用主机专属的截屏流程而无法启动，
伪装 `ps4` 则工作正常。

## 生效时机

清单在**导入/添加游戏时**读取一次，其值作为资料库条目的默认配置。之后修改
清单不会自动更新已有条目；用户需重新导入或在编辑对话框中调整。

## 排错

- 清单没被读到：确认文件名完全是 `art3m1s.json`，且在根目录或一级子目录。
- 字体没生效：确认 `fontOverride` 是单文件 TTF/OTF（不支持 TTC 合集），路径
  相对游戏根目录，且不允许 `..` 越界。
- 字段写错类型（如把布尔写成字符串）会被忽略并回退缺省，不会报错。
