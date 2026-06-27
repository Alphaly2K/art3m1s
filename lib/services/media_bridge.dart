import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import 'file_provider.dart';
import 'logger.dart';

typedef MediaFinishedCallback = void Function(String? id);

class MediaBridge {
  MediaBridge({
    required MediaFinishedCallback onVideoFinished,
    required MediaFinishedCallback onSoundFinished,
  })  : _videoFinishedCallback = onVideoFinished,
        _soundFinishedCallback = onSoundFinished;

  final MediaFinishedCallback _videoFinishedCallback;
  final MediaFinishedCallback _soundFinishedCallback;
  final ValueNotifier<VideoPlayerController?> videoController =
      ValueNotifier<VideoPlayerController?>(null);

  final Map<String, double> _channelVolumes = {
    'master': 1,
    'bgm': 1,
    'se': 1,
    'voice': 1,
  };
  final Map<String, _AudioHandle> _sounds = {};
  final Map<String, File> _assetCache = {};
  final Directory _cacheDir =
      Directory.systemTemp.createTempSync('art3m1s_media_');

  _AudioHandle? _bgm;
  _VideoHandle? _video;
  String? _videoId;
  bool _videoSkippable = false;
  bool _disposed = false;

  void handleCommand(String kind, Map<String, dynamic> payload) {
    if (_disposed) return;
    unawaited(_handleCommand(kind, payload));
  }

  Future<void> _handleCommand(String kind, Map<String, dynamic> payload) async {
    try {
      switch (kind) {
        case 'audio_set_volume':
          await _setVolume(payload);
        case 'audio_bgm_play':
          await _playBgm(payload, fadeMs: _int(payload['fade_ms']));
        case 'audio_bgm_crossfade':
          await _playBgm(payload, fadeMs: _int(payload['time_ms']));
        case 'audio_bgm_stop':
          await _stopBgm(fadeMs: _int(payload['fade_ms']));
        case 'audio_bgm_fade':
          await _fadeBgm(payload);
        case 'audio_bgm_pan':
          break;
        case 'audio_se_play':
          await _playSound(payload, channel: 'se');
        case 'audio_se_stop':
          await _stopSound(_string(payload['id']),
              fadeMs: _int(payload['fade_ms']));
        case 'audio_se_fade':
          await _fadeSound(_string(payload['id']), payload, channel: 'se');
        case 'audio_se_pan':
          break;
        case 'audio_voice_play':
          await _playSound(payload, channel: 'voice');
        case 'audio_stop_all':
          await _stopAllAudio();
        case 'video_play':
          await _playVideo(payload);
        case 'video_stop_all':
          await _stopVideo(notify: false);
        default:
          Log.debug('[MediaBridge] 未处理媒体命令: $kind');
      }
    } catch (e, st) {
      Log.error('[MediaBridge] $kind 处理失败: $e\n$st');
      _finishFailedCommand(kind, payload);
    }
  }

  Future<void> _setVolume(Map<String, dynamic> payload) async {
    final channel = _string(payload['channel']);
    if (channel == null) return;
    _channelVolumes[channel] = _double(payload['value'], 1).clamp(0, 1);
    await _bgm?.setEffectiveVolume(_effectiveVolume('bgm', _bgm!.gain));
    for (final entry in _sounds.entries) {
      await entry.value.setEffectiveVolume(
        _effectiveVolume(entry.value.channel, entry.value.gain),
      );
    }
    await _video?.setEffectiveVolume(_channelVolumes['master'] ?? 1);
  }

  Future<void> _playBgm(Map<String, dynamic> payload, {required int fadeMs}) async {
    final file = await _resolveAsset(payload);
    if (file == null) {
      _soundFinishedCallback(null);
      return;
    }
    await _bgm?.dispose();
    final gain = _gain(payload['gain']);
    final handle = await _AudioHandle.create(
      id: null,
      file: file,
      channel: 'bgm',
      gain: gain,
      pan: _pan(payload['pan']),
      loop: _bool(payload['loop']),
      onCompleted: (_) => _soundFinishedCallback(null),
    );
    _bgm = handle;
    await handle.setEffectiveVolume(fadeMs > 0 ? 0 : _effectiveVolume('bgm', gain));
    await handle.play();
    if (fadeMs > 0) {
      await handle.fadeTo(_effectiveVolume('bgm', gain), fadeMs);
    }
  }

  Future<void> _stopBgm({required int fadeMs}) async {
    final bgm = _bgm;
    _bgm = null;
    if (bgm == null) return;
    if (fadeMs > 0) await bgm.fadeTo(0, fadeMs);
    await bgm.dispose();
  }

  Future<void> _fadeBgm(Map<String, dynamic> payload) async {
    final bgm = _bgm;
    if (bgm == null) return;
    bgm.gain = _gain(payload['gain'], fallback: bgm.gain);
    await bgm.fadeTo(_effectiveVolume('bgm', bgm.gain), _int(payload['time_ms']));
  }

  Future<void> _playSound(
    Map<String, dynamic> payload, {
    required String channel,
  }) async {
    final file = await _resolveAsset(payload);
    if (file == null) {
      _soundFinishedCallback(_string(payload['id']));
      return;
    }
    final id = _string(payload['id']) ?? '';
    final key = _soundKey(channel, id);
    await _sounds.remove(key)?.dispose();
    final gain = _gain(payload['gain']);
    final handle = await _AudioHandle.create(
      id: id,
      file: file,
      channel: channel,
      gain: gain,
      pan: _pan(payload['pan']),
      loop: _bool(payload['loop']),
      onCompleted: (finishedId) {
        _sounds.remove(key);
        _soundFinishedCallback(finishedId);
      },
    );
    _sounds[key] = handle;
    final fadeMs = _int(payload['fade_ms']);
    await handle.setEffectiveVolume(fadeMs > 0 ? 0 : _effectiveVolume(channel, gain));
    await handle.play();
    if (fadeMs > 0) {
      await handle.fadeTo(_effectiveVolume(channel, gain), fadeMs);
    }
  }

  Future<void> _stopSound(String? id, {required int fadeMs}) async {
    if (id == null) return;
    final keys = _sounds.keys.where((key) => key.endsWith(':$id')).toList();
    for (final key in keys) {
      final handle = _sounds.remove(key);
      if (handle == null) continue;
      if (fadeMs > 0) await handle.fadeTo(0, fadeMs);
      await handle.dispose();
    }
  }

  Future<void> _fadeSound(
    String? id,
    Map<String, dynamic> payload, {
    required String channel,
  }) async {
    if (id == null) return;
    final handle = _sounds[_soundKey(channel, id)];
    if (handle == null) return;
    handle.gain = _gain(payload['gain'], fallback: handle.gain);
    await handle.fadeTo(_effectiveVolume(channel, handle.gain), _int(payload['time_ms']));
  }

  Future<void> _stopAllAudio() async {
    await _stopBgm(fadeMs: 0);
    final handles = _sounds.values.toList();
    _sounds.clear();
    for (final handle in handles) {
      await handle.dispose();
    }
  }

  Future<void> _playVideo(Map<String, dynamic> payload) async {
    final file = await _resolveAsset(payload);
    if (file == null) {
      _videoFinishedCallback(_string(payload['id']));
      return;
    }
    await _stopVideo(notify: false);
    _videoId = _string(payload['id']);
    _videoSkippable = _bool(payload['skippable']);
    if (_string(payload['id']) != null) {
      Log.warn('[MediaBridge] 图层视频暂按全屏视频播放: id=${payload['id']}');
    }
    final handle = await _VideoHandle.create(
      id: _videoId,
      file: file,
      loop: _bool(payload['loop']),
      onCompleted: (id) {
        unawaited(_stopVideo(notify: true, completedId: id));
      },
    );
    _video = handle;
    await handle.setEffectiveVolume(_channelVolumes['master'] ?? 1);
    videoController.value = handle.controller;
    await handle.play();
  }

  Future<void> skipVideo() async {
    if (!_videoSkippable) return;
    await _stopVideo(notify: true);
  }

  Future<void> _stopVideo({required bool notify, String? completedId}) async {
    final video = _video;
    final id = completedId ?? _videoId;
    _video = null;
    _videoId = null;
    _videoSkippable = false;
    if (videoController.value != null) {
      videoController.value = null;
    }
    if (video != null) await video.dispose();
    if (notify) _videoFinishedCallback(id);
  }

  Future<File?> _resolveAsset(Map<String, dynamic> payload) async {
    final path = _string(payload['file']);
    final resolved = _string(payload['resolved_file']);
    final candidates = <String>[
      if (resolved != null && resolved.isNotEmpty) resolved,
      if (path != null && path.isNotEmpty && path != resolved) path,
    ];
    if (candidates.isEmpty) return null;

    for (final candidate in _expandCandidates(candidates)) {
      final cached = _assetCache[candidate];
      if (cached != null && cached.existsSync()) return cached;
      final bytes = FileProvider.readFile(candidate);
      if (bytes == null) continue;
      final file = File('${_cacheDir.path}${Platform.pathSeparator}'
          '${_stableId(candidate)}${_extension(candidate)}');
      file.writeAsBytesSync(bytes, flush: true);
      _assetCache[candidate] = file;
      return file;
    }

    Log.warn('[MediaBridge] 媒体资源不存在: ${candidates.join(' -> ')}');
    return null;
  }

  Iterable<String> _expandCandidates(List<String> paths) sync* {
    final seen = <String>{};
    for (final path in paths) {
      final normalized = path.replaceAll('\\', '/');
      for (final candidate in [
        normalized,
        if (!_hasExtension(normalized)) '$normalized.ogg',
        if (!_hasExtension(normalized)) '$normalized.oga',
        if (!_hasExtension(normalized)) '$normalized.wav',
        if (!_hasExtension(normalized)) '$normalized.mp3',
        if (!_hasExtension(normalized)) '$normalized.m4a',
        if (!_hasExtension(normalized)) '$normalized.mp4',
        if (!_hasExtension(normalized)) '$normalized.mpg',
        if (!_hasExtension(normalized)) '$normalized.mpeg',
        if (!_hasExtension(normalized)) '$normalized.webm',
        if (!_hasExtension(normalized)) '$normalized.ogv',
      ]) {
        if (seen.add(candidate)) yield candidate;
      }
    }
  }

  bool _hasExtension(String path) {
    final name = path.split('/').last;
    final dot = name.lastIndexOf('.');
    return dot > 0 && dot < name.length - 1;
  }

  double _effectiveVolume(String channel, double gain) {
    final master = _channelVolumes['master'] ?? 1;
    final channelVolume = _channelVolumes[channel] ?? 1;
    return (master * channelVolume * gain).clamp(0, 1);
  }

  void _finishFailedCommand(String kind, Map<String, dynamic> payload) {
    if (kind == 'video_play') {
      _videoFinishedCallback(_string(payload['id']));
    } else if (kind == 'audio_bgm_play') {
      _soundFinishedCallback(null);
    } else if (kind == 'audio_se_play') {
      _soundFinishedCallback(_string(payload['id']));
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stopVideo(notify: false);
    await _stopAllAudio();
    videoController.dispose();
    try {
      if (_cacheDir.existsSync()) _cacheDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

class _AudioHandle {
  _AudioHandle({
    required this.id,
    required this.player,
    required this.channel,
    required this.gain,
    required this.pan,
    required this.loop,
    required this.onCompleted,
    required this.completionSub,
  });

  final String? id;
  final AudioPlayer player;
  final String channel;
  final bool loop;
  final void Function(String? id) onCompleted;
  double gain;
  double pan;
  Timer? _fadeTimer;
  bool _completed = false;
  final StreamSubscription<void> completionSub;

  static Future<_AudioHandle> create({
    required String? id,
    required File file,
    required String channel,
    required double gain,
    required double pan,
    required bool loop,
    required void Function(String? id) onCompleted,
  }) async {
    final player = AudioPlayer();
    late final _AudioHandle handle;
    final completionSub = player.onPlayerComplete.listen((_) {
      if (handle.loop || handle._completed) return;
      handle._completed = true;
      onCompleted(id);
    });
    handle = _AudioHandle(
      id: id,
      player: player,
      channel: channel,
      gain: gain,
      pan: pan,
      loop: loop,
      onCompleted: onCompleted,
      completionSub: completionSub,
    );
    await player.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.release);
    await player.setBalance(pan);
    await player.setSource(DeviceFileSource(file.path));
    return handle;
  }

  Future<void> play() => player.resume();

  Future<void> setEffectiveVolume(double volume) {
    return player.setVolume(volume.clamp(0, 1));
  }

  Future<void> fadeTo(double target, int durationMs) async {
    _fadeTimer?.cancel();
    if (durationMs <= 0) {
      await setEffectiveVolume(target);
      return;
    }
    final start = player.volume;
    final steps = math.max(1, durationMs ~/ 33);
    var step = 0;
    final completer = Completer<void>();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      step += 1;
      final t = (step / steps).clamp(0, 1).toDouble();
      unawaited(setEffectiveVolume(start + (target - start) * t));
      if (step >= steps) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  Future<void> dispose() async {
    _fadeTimer?.cancel();
    await completionSub.cancel();
    await player.stop();
    await player.dispose();
  }
}

class _VideoHandle {
  _VideoHandle({
    required this.id,
    required this.controller,
    required this.onCompleted,
  });

  final String? id;
  final VideoPlayerController controller;
  final void Function(String? id) onCompleted;
  Timer? _fadeTimer;
  bool _completed = false;

  static Future<_VideoHandle> create({
    required String? id,
    required File file,
    required bool loop,
    required void Function(String? id) onCompleted,
  }) async {
    final controller = VideoPlayerController.file(file);
    final handle = _VideoHandle(
      id: id,
      controller: controller,
      onCompleted: onCompleted,
    );
    controller.addListener(handle._onTick);
    await controller.initialize();
    await controller.setLooping(loop);
    return handle;
  }

  Future<void> play() => controller.play();

  Future<void> setEffectiveVolume(double volume) {
    return controller.setVolume(volume.clamp(0, 1));
  }

  Future<void> fadeTo(double target, int durationMs) async {
    _fadeTimer?.cancel();
    if (durationMs <= 0) {
      await setEffectiveVolume(target);
      return;
    }
    final start = controller.value.volume;
    final steps = math.max(1, durationMs ~/ 33);
    var step = 0;
    final completer = Completer<void>();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      step += 1;
      final t = (step / steps).clamp(0, 1).toDouble();
      unawaited(setEffectiveVolume(start + (target - start) * t));
      if (step >= steps) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    return completer.future;
  }

  Future<void> dispose() async {
    _fadeTimer?.cancel();
    controller.removeListener(_onTick);
    await controller.dispose();
  }

  void _onTick() {
    if (_completed || controller.value.isLooping || !controller.value.isCompleted) {
      return;
    }
    _completed = true;
    onCompleted(id);
  }
}

String? _string(Object? value) => value is String ? value : null;

int _int(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}

double _double(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  return fallback;
}

double _gain(Object? value, {double fallback = 1}) {
  if (value is num) {
    final raw = value.toDouble();
    return raw > 1 ? raw / 1000.0 : raw;
  }
  return fallback;
}

double _pan(Object? value) {
  if (value is num) {
    final raw = value.toDouble();
    return (raw.abs() > 1 ? raw / 1000.0 : raw).clamp(-1, 1);
  }
  return 0;
}

bool _bool(Object? value) => value == true;

String _soundKey(String channel, String id) => '$channel:$id';

String _stableId(String value) {
  var hash = 2166136261;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _extension(String path) {
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '.bin';
  final ext = name.substring(dot);
  return RegExp(r'^\.[A-Za-z0-9]{1,8}$').hasMatch(ext) ? ext : '.bin';
}
