/// 输入门控策略：所有喂给 core 的输入（键盘/鼠标键/指针位置/触摸与各类转发）
/// 在 CoreBridge 的出口统一过这层过滤与重映射。
///
/// 默认 [InputGatePolicy.full] 全放行，等价于没有门控、不改变任何现有行为；
/// 项目补丁按环境/平台选择收窄的 profile 或自定义规则。典型场景：移动端移植
/// 游戏的脚本没有特判键盘操作，引擎的默认按键行为（回车推进、Esc 菜单等）会
/// 覆盖脚本逻辑，此时用 [InputGatePolicy.touchOnly] 把键盘整类关掉。
///
/// core 侧无需改动：输入本来就全部经由宿主喂入，过滤在宿主出口完成即可。
/// 策略可 JSON 序列化，供项目补丁清单与资料库条目携带。
library;

/// 预置的输入环境 profile。
enum InputGateProfile {
  /// 全放行（桌面/默认）。
  full('默认'),

  /// 触屏移植：脚本只轮询触摸/点击。关闭键盘与滚轮转发，避免引擎默认按键
  /// 行为覆盖脚本；鼠标键保留（触屏 tap 在 core 里就是左键），触摸保留。
  touchOnly('触屏移植');

  const InputGateProfile(this.label);

  final String label;
}

class InputGatePolicy {
  /// 键盘主开关：false 时丢弃一切 feedKey。
  final bool keyboard;

  /// 鼠标键主开关：false 时丢弃一切 feedMouseButton / feedClick。
  final bool mouseButtons;

  /// 指针位置主开关：false 时丢弃 feedMouse（hover/移动）。
  final bool mouseMove;

  /// 触摸主开关：false 时丢弃 feedTouch。
  final bool touch;

  /// 滚轮 → 方向键（VK 136/137）的转发开关（在播放页判定，属转发而非类别）。
  final bool wheelToKeys;

  /// 双指触摸 → 鼠标右键的转发开关（在播放页判定，属转发而非类别）。
  final bool twoFingerRightClick;

  /// 键盘开启时仍要拦截的 VK 黑名单。
  final Set<int> blockedKeys;

  /// VK → VK 重映射，在黑名单判定之后应用；按下/抬起经同一映射保持一致。
  final Map<int, int> keyRemap;

  const InputGatePolicy({
    this.keyboard = true,
    this.mouseButtons = true,
    this.mouseMove = true,
    this.touch = true,
    this.wheelToKeys = true,
    this.twoFingerRightClick = true,
    this.blockedKeys = const {},
    this.keyRemap = const {},
  });

  /// 默认策略：全部放行。
  static const full = InputGatePolicy();

  /// 触屏移植环境：关键盘、滚轮转发与双指右键；hover 位置不上报
  /// （触屏没有悬停概念，持续的位置流只会让不处理它的脚本见到噪声）。
  static const touchOnly = InputGatePolicy(
    keyboard: false,
    mouseMove: false,
    wheelToKeys: false,
    twoFingerRightClick: false,
  );

  /// 键盘事件过滤：返回 null 表示丢弃，否则返回（可能重映射后的）VK。
  int? filterKey(int vk) {
    if (!keyboard || blockedKeys.contains(vk)) return null;
    return keyRemap[vk] ?? vk;
  }

  /// 命中的预置 profile；自定义规则返回 null。
  InputGateProfile? get knownProfile {
    if (_sameRulesAs(full)) return InputGateProfile.full;
    if (_sameRulesAs(touchOnly)) return InputGateProfile.touchOnly;
    return null;
  }

  bool get isFull => _sameRulesAs(full);

  bool _sameRulesAs(InputGatePolicy other) {
    return keyboard == other.keyboard &&
        mouseButtons == other.mouseButtons &&
        mouseMove == other.mouseMove &&
        touch == other.touch &&
        wheelToKeys == other.wheelToKeys &&
        twoFingerRightClick == other.twoFingerRightClick &&
        _setEquals(blockedKeys, other.blockedKeys) &&
        _mapEquals(keyRemap, other.keyRemap);
  }

  InputGatePolicy copyWith({
    bool? keyboard,
    bool? mouseButtons,
    bool? mouseMove,
    bool? touch,
    bool? wheelToKeys,
    bool? twoFingerRightClick,
    Set<int>? blockedKeys,
    Map<int, int>? keyRemap,
  }) {
    return InputGatePolicy(
      keyboard: keyboard ?? this.keyboard,
      mouseButtons: mouseButtons ?? this.mouseButtons,
      mouseMove: mouseMove ?? this.mouseMove,
      touch: touch ?? this.touch,
      wheelToKeys: wheelToKeys ?? this.wheelToKeys,
      twoFingerRightClick: twoFingerRightClick ?? this.twoFingerRightClick,
      blockedKeys: blockedKeys ?? this.blockedKeys,
      keyRemap: keyRemap ?? this.keyRemap,
    );
  }

  Map<String, dynamic> toJson() => {
    'keyboard': keyboard,
    'mouseButtons': mouseButtons,
    'mouseMove': mouseMove,
    'touch': touch,
    'wheelToKeys': wheelToKeys,
    'twoFingerRightClick': twoFingerRightClick,
    'blockedKeys': blockedKeys.toList()..sort(),
    'keyRemap': {
      for (final entry in keyRemap.entries) entry.key.toString(): entry.value,
    },
  };

  /// null/缺字段一律回到全放行默认，保证旧存档与无补丁项目的零行为变化。
  factory InputGatePolicy.fromJson(Map<String, dynamic>? json) {
    if (json == null) return full;
    return InputGatePolicy(
      keyboard: json['keyboard'] != false,
      mouseButtons: json['mouseButtons'] != false,
      mouseMove: json['mouseMove'] != false,
      touch: json['touch'] != false,
      wheelToKeys: json['wheelToKeys'] != false,
      twoFingerRightClick: json['twoFingerRightClick'] != false,
      blockedKeys: {
        for (final vk in (json['blockedKeys'] as List? ?? const []))
          if (vk is num) vk.toInt(),
      },
      keyRemap: {
        for (final entry
            in (json['keyRemap'] as Map? ?? const {}).entries)
          if (int.tryParse(entry.key.toString()) case int from?
              when entry.value is num)
            from: (entry.value as num).toInt(),
      },
    );
  }

  static bool _setEquals(Set<int> left, Set<int> right) {
    return left.length == right.length && left.containsAll(right);
  }

  static bool _mapEquals(Map<int, int> left, Map<int, int> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }
}
