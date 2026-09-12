import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:flutter/widgets.dart';

import '../engine/engine_runtime.dart';
import 'file_provider.dart';
import 'logger.dart';
import 'rfvp_api.dart';

typedef MediaFinishedCallback = void Function(String? id);

/// Host-owned audio output and runtime video presentation adapter.
///
/// Video decoding and composition live in `art3m1s-core`; this class only
/// forwards legacy host video commands as completion failures. Audio playback
/// is host-owned and intentionally uses platform channels rather than FFI
/// callback trampolines.
class MediaBridge implements EngineMediaHost {
  MediaBridge({
    required MediaFinishedCallback onVideoFinished,
    required MediaFinishedCallback onSoundFinished,
  }) : _videoFinishedCallback = onVideoFinished,
       _soundFinishedCallback = onSoundFinished;

  final MediaFinishedCallback _videoFinishedCallback;
  final MediaFinishedCallback _soundFinishedCallback;

  @override
  final ValueNotifier<EngineVideoPlayback?> videoPlayback =
      ValueNotifier<EngineVideoPlayback?>(null);

  @override
  final ValueNotifier<bool> fullscreenVideoBlocking = ValueNotifier<bool>(
    false,
  );

  final Map<String, double> _channelVolumes = {
    'master': 1,
    'bgm': 1,
    'se': 1,
    'voice': 1,
  };
  final Map<String, _AudioHandle> _sounds = {};
  final MediaOperationGate _audioOperations = MediaOperationGate();
  final Map<String, File> _assetCache = {};
  final Directory _cacheDir = Directory.systemTemp.createTempSync(
    'art3m1s_media_',
  );

  _AudioHandle? _bgm;
  final Map<int, Uint8List> _rfvpEncoded = {};
  final Map<int, _AudioHandle> _rfvpHandles = {};
  bool _disposed = false;

  @override
  bool get isFullscreenVideoBlocking => false;

  void handleRfvpAudioCommand(RfvpAudioCommand command) {
    if (_disposed) return;
    unawaited(_handleRfvpAudioCommand(command));
  }

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
          await _crossfadeBgm(payload, durationMs: _int(payload['time_ms']));
        case 'audio_bgm_stop':
          await _stopBgm(fadeMs: _int(payload['fade_ms']));
        case 'audio_bgm_fade':
          await _fadeBgm(payload);
        case 'audio_bgm_pan':
          await _panBgm(payload);
        case 'audio_se_play':
          await _playSound(payload, channel: 'se');
        case 'audio_se_stop':
          await _stopSound(
            _string(payload['id']),
            fadeMs: _int(payload['fade_ms']),
          );
        case 'audio_se_fade':
          await _fadeSound(_string(payload['id']), payload, channel: 'se');
        case 'audio_se_pan':
          await _panSound(_string(payload['id']), payload, channel: 'se');
        case 'audio_voice_play':
          await _playSound(payload, channel: 'voice');
        case 'audio_stop_all':
          await _stopAllAudio();
        case 'video_play':
          _failHostVideoCommand(payload);
        case 'video_stop_all':
          break;
        default:
          Log.debug('[MediaBridge] 未处理媒体命令: $kind');
      }
    } catch (e, st) {
      Log.error('[MediaBridge] $kind 处理失败: $e\n$st');
      _finishFailedCommand(kind, payload);
    }
  }

  Future<void> _handleRfvpAudioCommand(RfvpAudioCommand command) async {
    final streamId = command.streamId;
    final channel = streamId < 0x1000 ? 'bgm' : 'se';
    final id = 'rfvp:$streamId';

    switch (command.kind) {
      case rfvpAudioLoadEncoded:
        _rfvpEncoded[streamId] = command.payload;
        final old = _rfvpHandles.remove(streamId);
        if (old != null) await old.dispose();
      case rfvpAudioCreateStream:
      case rfvpAudioSubmitI16:
      case rfvpAudioSubmitF32:
        Log.warn(
          '[MediaBridge] RFVP PCM stream $streamId 由引擎侧提交，Host 暂不做二次混音',
        );
      case rfvpAudioPlay:
        final bytes = _rfvpEncoded[streamId];
        if (bytes == null) {
          Log.warn('[MediaBridge] RFVP stream $streamId 尚未加载，忽略播放');
          return;
        }
        final old = _rfvpHandles.remove(streamId);
        if (old != null) await old.dispose();
        _AudioHandle? handle;
        final created = await _AudioHandle.create(
          id: id,
          file: null,
          bytes: bytes,
          loopFile: null,
          channel: channel,
          gain: command.volume,
          pan: command.pan,
          loop: command.repeat,
          onCompleted: (_) {
            if (identical(_rfvpHandles[streamId], handle)) {
              _rfvpHandles.remove(streamId);
            }
          },
        );
        handle = created;
        _rfvpHandles[streamId] = handle;
        await handle.setEffectiveVolume(
          command.fadeMs > 0 ? 0 : _effectiveVolume(channel, handle.gain),
        );
        await handle.play();
        if (command.fadeMs > 0) {
          await handle.fadeTo(
            _effectiveVolume(channel, handle.gain),
            command.fadeMs,
          );
        }
      case rfvpAudioStop:
        final handle = _rfvpHandles.remove(streamId);
        if (handle == null) return;
        if (command.fadeMs > 0) await handle.fadeTo(0, command.fadeMs);
        await handle.dispose();
      case rfvpAudioPause:
        await _rfvpHandles[streamId]?.player.pause();
      case rfvpAudioResume:
        await _rfvpHandles[streamId]?.player.resume();
      case rfvpAudioSetParams:
        final handle = _rfvpHandles[streamId];
        if (handle == null) return;
        handle.gain = command.volume;
        await handle.setEffectiveVolume(
          _effectiveVolume(channel, command.volume),
        );
        await handle.setPan(command.pan);
      case rfvpAudioDestroyStream:
        _rfvpEncoded.remove(streamId);
        final handle = _rfvpHandles.remove(streamId);
        if (handle != null) await handle.dispose();
      case rfvpAudioMasterVolume:
        _channelVolumes['master'] = command.volume.clamp(0, 1);
        final handles = <_AudioHandle>[
          ?_bgm,
          ..._sounds.values,
          ..._rfvpHandles.values,
        ];
        for (final handle in handles) {
          await handle.setEffectiveVolume(
            _effectiveVolume(handle.channel, handle.gain),
          );
        }
    }
  }

  void _failHostVideoCommand(Map<String, dynamic> payload) {
    final id = _string(payload['id']);
    Log.warn(
      '[MediaBridge] 当前 core 未启用 runtime 视频解码，宿主视频后端已移除，'
      '跳过视频命令: id=${id ?? "fullscreen"}',
    );
    _videoFinishedCallback(id);
  }

  Future<void> _setVolume(Map<String, dynamic> payload) async {
    final channel = _string(payload['channel']);
    if (channel == null) return;
    _channelVolumes[channel] = _double(payload['value'], 1).clamp(0, 1);
    final bgm = _bgm;
    if (bgm != null) {
      await bgm.setEffectiveVolume(_effectiveVolume('bgm', bgm.gain));
    }
    for (final sound in _sounds.values.toList()) {
      await sound.setEffectiveVolume(
        _effectiveVolume(sound.channel, sound.gain),
      );
    }
  }

  Future<void> _playBgm(
    Map<String, dynamic> payload, {
    required int fadeMs,
  }) async {
    final ticket = _audioOperations.begin(_bgmOperationKey);
    try {
      final file = await _resolveAsset(payload);
      if (!_isCurrentAudioOperation(ticket)) return;
      if (file == null) {
        _soundFinishedCallback(null);
        return;
      }

      final loopFile = await _resolveAsset(
        payload,
        fileKey: 'loop_file',
        resolvedFileKey: 'resolved_loop_file',
      );
      if (!_isCurrentAudioOperation(ticket)) return;

      final previous = _bgm;
      _bgm = null;
      if (previous != null) await previous.dispose();
      if (!_isCurrentAudioOperation(ticket)) return;

      final gain = _gain(payload['gain']);
      _AudioHandle? handle;
      final created = await _AudioHandle.create(
        id: null,
        file: file,
        loopFile: loopFile,
        channel: 'bgm',
        gain: gain,
        pan: _pan(payload['pan']),
        loop: _bool(payload['loop']),
        onCompleted: (_) {
          final completed = handle;
          if (completed == null) return;
          if (!_isCurrentAudioOperation(ticket) ||
              !identical(_bgm, completed)) {
            unawaited(completed.dispose());
            return;
          }
          _bgm = null;
          unawaited(completed.dispose());
          _soundFinishedCallback(null);
        },
      );
      handle = created;
      if (!_isCurrentAudioOperation(ticket)) {
        await created.dispose();
        return;
      }

      _bgm = created;
      await created.setEffectiveVolume(
        fadeMs > 0 ? 0 : _effectiveVolume('bgm', gain),
      );
      if (!_isCurrentAudioOperation(ticket) || !identical(_bgm, created)) {
        return;
      }
      await created.play();
      if (fadeMs > 0 && _isCurrentAudioOperation(ticket)) {
        await created.fadeTo(_effectiveVolume('bgm', gain), fadeMs);
      }
    } catch (_) {
      if (!_isCurrentAudioOperation(ticket)) return;
      rethrow;
    }
  }

  Future<void> _crossfadeBgm(
    Map<String, dynamic> payload, {
    required int durationMs,
  }) async {
    final ticket = _audioOperations.begin(_bgmOperationKey);
    _AudioHandle? created;
    try {
      final file = await _resolveAsset(payload);
      if (!_isCurrentAudioOperation(ticket)) return;
      if (file == null) {
        _soundFinishedCallback(null);
        return;
      }

      final loopFile = await _resolveAsset(
        payload,
        fileKey: 'loop_file',
        resolvedFileKey: 'resolved_loop_file',
      );
      if (!_isCurrentAudioOperation(ticket)) return;

      final gain = _gain(payload['gain']);
      _AudioHandle? callbackHandle;
      created = await _AudioHandle.create(
        id: null,
        file: file,
        loopFile: loopFile,
        channel: 'bgm',
        gain: gain,
        pan: _pan(payload['pan']),
        loop: _bool(payload['loop']),
        onCompleted: (_) {
          final completed = callbackHandle;
          if (completed == null) return;
          if (!_isCurrentAudioOperation(ticket) ||
              !identical(_bgm, completed)) {
            unawaited(completed.dispose());
            return;
          }
          _bgm = null;
          unawaited(completed.dispose());
          _soundFinishedCallback(null);
        },
      );
      callbackHandle = created;
      if (!_isCurrentAudioOperation(ticket)) {
        await created.dispose();
        return;
      }

      final previous = _bgm;
      _bgm = created;
      await created.setEffectiveVolume(
        durationMs > 0 ? 0 : _effectiveVolume('bgm', gain),
      );
      if (!_isCurrentAudioOperation(ticket) || !identical(_bgm, created)) {
        return;
      }
      await created.play();

      if (durationMs > 0) {
        await Future.wait([
          created.fadeTo(_effectiveVolume('bgm', gain), durationMs),
          if (previous != null) previous.fadeTo(0, durationMs),
        ]);
      }
      if (previous != null) await previous.dispose();
    } catch (_) {
      if (created != null && !identical(_bgm, created)) {
        await created.dispose();
      }
      if (!_isCurrentAudioOperation(ticket)) return;
      rethrow;
    }
  }

  Future<void> _stopBgm({required int fadeMs}) async {
    _audioOperations.invalidate(_bgmOperationKey);
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
    await bgm.fadeTo(
      _effectiveVolume('bgm', bgm.gain),
      _int(payload['time_ms']),
    );
  }

  Future<void> _panBgm(Map<String, dynamic> payload) async {
    final bgm = _bgm;
    if (bgm == null) return;
    await bgm.panTo(_pan(payload['pan']), _int(payload['time_ms']));
  }

  Future<void> _playSound(
    Map<String, dynamic> payload, {
    required String channel,
  }) async {
    final id = _string(payload['id']) ?? '';
    final key = _soundKey(channel, id);
    final ticket = _audioOperations.begin(key);
    try {
      final file = await _resolveAsset(payload);
      if (!_isCurrentAudioOperation(ticket)) return;
      if (file == null) {
        _soundFinishedCallback(id);
        return;
      }

      final previous = _sounds.remove(key);
      if (previous != null) await previous.dispose();
      if (!_isCurrentAudioOperation(ticket)) return;

      final gain = _gain(payload['gain']);
      _AudioHandle? handle;
      final created = await _AudioHandle.create(
        id: id,
        file: file,
        loopFile: null,
        channel: channel,
        gain: gain,
        pan: _pan(payload['pan']),
        loop: _bool(payload['loop']),
        onCompleted: (finishedId) {
          final completed = handle;
          if (completed == null) return;
          if (!_isCurrentAudioOperation(ticket) ||
              !identical(_sounds[key], completed)) {
            unawaited(completed.dispose());
            return;
          }
          _sounds.remove(key);
          unawaited(completed.dispose());
          _soundFinishedCallback(finishedId);
        },
      );
      handle = created;
      if (!_isCurrentAudioOperation(ticket)) {
        await created.dispose();
        return;
      }

      _sounds[key] = created;
      final fadeMs = _int(payload['fade_ms']);
      await created.setEffectiveVolume(
        fadeMs > 0 ? 0 : _effectiveVolume(channel, gain),
      );
      if (!_isCurrentAudioOperation(ticket) ||
          !identical(_sounds[key], created)) {
        return;
      }
      await created.play();
      if (fadeMs > 0 && _isCurrentAudioOperation(ticket)) {
        await created.fadeTo(_effectiveVolume(channel, gain), fadeMs);
      }
    } catch (_) {
      if (!_isCurrentAudioOperation(ticket)) return;
      rethrow;
    }
  }

  Future<void> _stopSound(String? id, {required int fadeMs}) async {
    if (id == null) return;
    final keys = {_soundKey('se', id), _soundKey('voice', id)};
    for (final key in keys) {
      _audioOperations.invalidate(key);
    }
    final handles = <_AudioHandle>[];
    for (final key in keys) {
      final handle = _sounds.remove(key);
      if (handle != null) handles.add(handle);
    }
    for (final handle in handles) {
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
    final handle = _controlledSound(id, preferredChannel: channel);
    if (handle == null) return;
    handle.gain = _gain(payload['gain'], fallback: handle.gain);
    await handle.fadeTo(
      _effectiveVolume(channel, handle.gain),
      _int(payload['time_ms']),
    );
  }

  Future<void> _panSound(
    String? id,
    Map<String, dynamic> payload, {
    required String channel,
  }) async {
    if (id == null) return;
    final handle = _controlledSound(id, preferredChannel: channel);
    if (handle == null) return;
    await handle.panTo(_pan(payload['pan']), _int(payload['time_ms']));
  }

  Future<void> _stopAllAudio() async {
    _audioOperations.invalidateAll();
    final bgm = _bgm;
    _bgm = null;
    final handles = _sounds.values.toList();
    _sounds.clear();
    final rfvpHandles = _rfvpHandles.values.toList();
    _rfvpHandles.clear();
    _rfvpEncoded.clear();
    if (bgm != null) await bgm.dispose();
    for (final handle in handles) {
      await handle.dispose();
    }
    for (final handle in rfvpHandles) {
      await handle.dispose();
    }
  }

  bool _isCurrentAudioOperation(MediaOperationTicket ticket) {
    return !_disposed && _audioOperations.isCurrent(ticket);
  }

  _AudioHandle? _controlledSound(
    String id, {
    required String preferredChannel,
  }) {
    final preferred = _sounds[_soundKey(preferredChannel, id)];
    if (preferred != null) return preferred;
    return _sounds[_soundKey(preferredChannel == 'voice' ? 'se' : 'voice', id)];
  }

  @override
  Future<void> skipVideo() async {
    // Runtime video is submitted as part of the normal core frame. A host
    // skip button is therefore only a completion notification.
    _videoFinishedCallback(null);
  }

  Future<File?> _resolveAsset(
    Map<String, dynamic> payload, {
    String fileKey = 'file',
    String resolvedFileKey = 'resolved_file',
  }) async {
    final path = _string(payload[fileKey]);
    final resolved = _string(payload[resolvedFileKey]);
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
      final file = File(
        '${_cacheDir.path}${Platform.pathSeparator}'
        '${_stableId(candidate)}${_extension(candidate)}',
      );
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
    } else if (kind == 'audio_bgm_play' || kind == 'audio_bgm_crossfade') {
      _soundFinishedCallback(null);
    } else if (kind == 'audio_se_play') {
      _soundFinishedCallback(_string(payload['id']));
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stopAllAudio();
    videoPlayback.dispose();
    fullscreenVideoBlocking.dispose();
    try {
      if (_cacheDir.existsSync()) _cacheDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

typedef VideoPlayback = EngineVideoPlayback;

class _AudioHandle {
  _AudioHandle({
    required this.id,
    required this.player,
    required this.channel,
    required this.loop,
    required this.loopFile,
    required this.gain,
    required this.pan,
    required this.onCompleted,
  });

  final String? id;
  final audio.AudioPlayer player;
  final String channel;
  final bool loop;
  final File? loopFile;
  final void Function(String? id) onCompleted;
  double gain;
  double pan;
  Timer? _fadeTimer;
  Completer<void>? _fadeCompleter;
  Timer? _panTimer;
  Completer<void>? _panCompleter;
  StreamSubscription<void>? _completionSubscription;
  bool _completed = false;
  bool _loopSegmentStarted = false;
  bool _disposed = false;
  double _effectiveVolume = 1;

  static Future<_AudioHandle> create({
    required String? id,
    required File? file,
    Uint8List? bytes,
    required File? loopFile,
    required String channel,
    required double gain,
    required double pan,
    required bool loop,
    required void Function(String? id) onCompleted,
  }) async {
    assert(file != null || bytes != null);
    final player = audio.AudioPlayer();
    final handle = _AudioHandle(
      id: id,
      player: player,
      channel: channel,
      loop: loop,
      loopFile: loopFile,
      gain: gain,
      pan: pan,
      onCompleted: onCompleted,
    );
    handle._completionSubscription = player.onPlayerComplete.listen((_) {
      unawaited(handle._handleCompletion());
    });
    try {
      await player.setReleaseMode(
        loop && loopFile == null
            ? audio.ReleaseMode.loop
            : audio.ReleaseMode.stop,
      );
      await player.setSource(
        bytes != null
            ? audio.BytesSource(bytes)
            : audio.DeviceFileSource(file!.path),
      );
      await handle.setPan(pan);
      return handle;
    } catch (_) {
      await handle.dispose();
      rethrow;
    }
  }

  Future<void> _handleCompletion() async {
    if (_disposed || _completed) return;
    if (loop && loopFile == null) return;
    if (loop && !_loopSegmentStarted) {
      final next = loopFile;
      if (next == null) return;
      _loopSegmentStarted = true;
      try {
        await player.setReleaseMode(audio.ReleaseMode.loop);
        await player.setSource(audio.DeviceFileSource(next.path));
        await setPan(pan);
        await setEffectiveVolume(_effectiveVolume);
        await player.resume();
        Log.debug('[MediaBridge] BGM 已进入 B 段循环: ${next.path}');
      } catch (error, stackTrace) {
        Log.warn(
          '[MediaBridge] BGM B 段播放失败: ${next.path}: '
          '$error\n$stackTrace',
        );
        await _complete();
      }
      return;
    }
    await _complete();
  }

  Future<void> _complete() async {
    if (_disposed || _completed) return;
    _completed = true;
    onCompleted(id);
  }

  Future<void> play() => player.resume();

  Future<void> setEffectiveVolume(double volume) async {
    _effectiveVolume = volume.clamp(0, 1);
    await player.setVolume(_effectiveVolume);
  }

  Future<void> setPan(double value) async {
    pan = value.clamp(-1, 1);
    await player.setBalance(pan);
  }

  Future<void> panTo(double target, int durationMs) async {
    _cancelPan();
    target = target.clamp(-1, 1);
    if (durationMs <= 0) {
      await setPan(target);
      return;
    }
    final start = pan;
    final steps = math.max(1, durationMs ~/ 33);
    var step = 0;
    final completer = _panCompleter = Completer<void>();
    _panTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      step += 1;
      final t = (step / steps).clamp(0, 1).toDouble();
      unawaited(setPan(start + (target - start) * t));
      if (step >= steps) {
        timer.cancel();
        _panTimer = null;
        if (!completer.isCompleted) completer.complete();
        if (identical(_panCompleter, completer)) _panCompleter = null;
      }
    });
    return completer.future;
  }

  Future<void> fadeTo(double target, int durationMs) async {
    _cancelFade();
    if (durationMs <= 0) {
      await setEffectiveVolume(target);
      return;
    }
    final start = _effectiveVolume;
    final steps = math.max(1, durationMs ~/ 33);
    var step = 0;
    final completer = _fadeCompleter = Completer<void>();
    _fadeTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      step += 1;
      final t = (step / steps).clamp(0, 1).toDouble();
      unawaited(setEffectiveVolume(start + (target - start) * t));
      if (step >= steps) {
        timer.cancel();
        _fadeTimer = null;
        if (!completer.isCompleted) completer.complete();
        if (identical(_fadeCompleter, completer)) _fadeCompleter = null;
      }
    });
    return completer.future;
  }

  void _cancelFade() {
    _fadeTimer?.cancel();
    _fadeTimer = null;
    final completer = _fadeCompleter;
    _fadeCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  void _cancelPan() {
    _panTimer?.cancel();
    _panTimer = null;
    final completer = _panCompleter;
    _panCompleter = null;
    if (completer != null && !completer.isCompleted) completer.complete();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _cancelFade();
    _cancelPan();
    await _completionSubscription?.cancel();
    _completionSubscription = null;
    await player.dispose();
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

const String _bgmOperationKey = 'bgm';

final class MediaOperationTicket {
  const MediaOperationTicket(this.key, this.epoch, this.generation);

  final String key;
  final int epoch;
  final int generation;
}

/// 为异步媒体命令分配代次，只允许同一 key 的最新命令继续生效。
///
/// 不同 key（例如不同 SE id）仍可并行；[invalidateAll] 用于 stop-all 与销毁。
final class MediaOperationGate {
  int _epoch = 0;
  final Map<String, int> _generations = {};

  MediaOperationTicket begin(String key) {
    final generation = (_generations[key] ?? 0) + 1;
    _generations[key] = generation;
    return MediaOperationTicket(key, _epoch, generation);
  }

  void invalidate(String key) {
    _generations[key] = (_generations[key] ?? 0) + 1;
  }

  void invalidateAll() {
    _epoch += 1;
    _generations.clear();
  }

  bool isCurrent(MediaOperationTicket ticket) {
    return ticket.epoch == _epoch &&
        _generations[ticket.key] == ticket.generation;
  }
}

String _stableId(String value) {
  var hash = 2166136261;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 16777619) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

String _extension(String path) {
  final slash = path.lastIndexOf('/');
  final dot = path.lastIndexOf('.');
  if (dot <= slash || dot == path.length - 1) return '';
  return path.substring(dot).toLowerCase();
}
