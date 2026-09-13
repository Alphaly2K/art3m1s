import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';

enum Ps5UiSound { tick, confirm, back }

/// PS5 壳的界面音效：切换选中 / 确认点击 / 返回上一级。
///
/// 用小池轮换播放器避免快速连续操作时互相截断。测试环境（无插件）下静音。
abstract final class Ps5UiSounds {
  static const _tickAsset = 'audio/ui_tick.wav';
  static const _confirmAsset = 'audio/ui_confirm.wav';
  static const _backAsset = 'audio/ui_back.wav';

  static final List<AudioPlayer> _pool = List.generate(4, (_) => AudioPlayer());
  static var _next = 0;

  static bool get _muted =>
      Platform.environment.containsKey('FLUTTER_TEST') ||
      Platform.environment.containsKey('INTEGRATION_TEST');

  /// 选中项移动 / 悬停切换。
  static void tick() => _play(_tickAsset, 0.32);

  /// 确认、点击、打开。
  static void confirm() => _play(_confirmAsset, 0.42);

  /// 取消、返回、关闭、退出。
  static void back() => _play(_backAsset, 0.4);

  static void play(Ps5UiSound sound) {
    switch (sound) {
      case Ps5UiSound.tick:
        tick();
      case Ps5UiSound.confirm:
        confirm();
      case Ps5UiSound.back:
        back();
    }
  }

  static void _play(String asset, double volume) {
    if (_muted) return;
    final player = _pool[_next % _pool.length];
    _next++;
    unawaited(
      player.play(AssetSource(asset), volume: volume).catchError((_) {}),
    );
  }
}
