import 'package:flutter/material.dart';

/// 游戏运行页专用路由。
///
/// 路由级返回手势很容易和游戏内横向操作冲突，因此在所有平台上禁用
/// PlayerScreen 的交互式返回；[Navigator.pop] 等正常退出路径不受影响。
class PlayerPageRoute<T> extends MaterialPageRoute<T> {
  PlayerPageRoute({required super.builder, super.settings});

  @override
  bool get popGestureEnabled => false;
}
