import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as media_kit;
import 'package:media_kit_video/media_kit_video.dart' as media_kit_video;

import 'file_provider.dart';
import 'logger.dart';

typedef MediaFinishedCallback = void Function(String? id);
typedef VideoLayerFrameUploader =
    bool Function(
      String id,
      int width,
      int height,
      Pointer<Uint8> rgba,
      int rgbaLen,
    );

class MediaBridge {
  MediaBridge({
    required MediaFinishedCallback onVideoFinished,
    required MediaFinishedCallback onSoundFinished,
    required this.uploadVideoLayerFrame,
  }) : _videoFinishedCallback = onVideoFinished,
       _soundFinishedCallback = onSoundFinished {
    _fullscreenVideoPool.prewarm();
  }

  final MediaFinishedCallback _videoFinishedCallback;
  final MediaFinishedCallback _soundFinishedCallback;
  final VideoLayerFrameUploader uploadVideoLayerFrame;
  final ValueNotifier<VideoPlayback?> videoPlayback =
      ValueNotifier<VideoPlayback?>(null);
  final ValueNotifier<bool> fullscreenVideoBlocking = ValueNotifier<bool>(
    false,
  );
  static const Duration _fullscreenVideoStartupTimeout = Duration(seconds: 3);

  final Map<String, double> _channelVolumes = {
    'master': 1,
    'bgm': 1,
    'se': 1,
    'voice': 1,
  };
  final Map<String, _AudioHandle> _sounds = {};
  final MediaOperationGate _audioOperations = MediaOperationGate();
  final Map<String, File> _assetCache = {};
  final _MediaKitVideoPool _fullscreenVideoPool = _MediaKitVideoPool();
  final Directory _cacheDir = Directory.systemTemp.createTempSync(
    'art3m1s_media_',
  );

  _AudioHandle? _bgm;
  _VideoHandle? _video;
  final Map<String, _MpvLayerVideoHandle> _layerVideos = {};
  final Map<String, int> _layerVideoGenerations = {};
  String? _videoId;
  bool _videoSkippable = false;
  bool _fullscreenVideoBlocking = false;
  bool _disposed = false;

  bool get isFullscreenVideoBlocking => _fullscreenVideoBlocking;

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
          await _playVideo(payload);
        case 'video_stop_all':
          await _stopAllVideos();
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
    // 设置页可能在没有 BGM 的状态下修改 SE/Voice 音量。不能在
    // null-aware 调用内部强制解引用 `_bgm!`，否则整个音量命令会在
    // 更新其他通道之前抛异常。
    final bgm = _bgm;
    if (bgm != null) {
      await bgm.setEffectiveVolume(_effectiveVolume('bgm', bgm.gain));
    }
    for (final sound in _sounds.values.toList()) {
      await sound.setEffectiveVolume(
        _effectiveVolume(sound.channel, sound.gain),
      );
    }
    await _video?.setEffectiveVolume(_channelVolumes['master'] ?? 1);
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
      // Artemis 的 *_a / *_b BGM 是分段循环：A 为只播一次的引导段，
      // A 结束后切到 B 无限循环。Core 已解析命名约定并传来这两个字段。
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
    if (bgm != null) await bgm.dispose();
    for (final handle in handles) {
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

  Future<void> _playVideo(Map<String, dynamic> payload) async {
    final id = _string(payload['id']);
    Log.debug(
      '[MediaBridge] video_play command: file=${payload['file']}, '
      'resolved=${payload['resolved_file']}, id=$id',
    );
    final file = await _resolveAsset(payload);
    if (file == null) {
      _videoFinishedCallback(id);
      return;
    }
    if (id != null) {
      await _playLayerVideo(id, file, loop: _bool(payload['loop']));
      return;
    }

    await _stopVideo(notify: false);
    _videoId = id;
    _videoSkippable = _bool(payload['skippable']);
    _setFullscreenVideoBlocking(_videoId == null);

    final loop = _bool(payload['loop']);
    final isFullscreen = _videoId == null;
    final startupTimeout = isFullscreen && !loop
        ? _fullscreenVideoStartupTimeout
        : null;
    _VideoHandle? handle;
    Log.debug(
      '[MediaBridge] video_play start: file=${file.path}, '
      'id=$_videoId, loop=$loop, skippable=$_videoSkippable',
    );
    try {
      handle = await _VideoHandle.create(
        pool: _fullscreenVideoPool,
        id: _videoId,
        file: file,
        loop: loop,
        startupTimeout: startupTimeout,
        onCompleted: (id) {
          scheduleMicrotask(() {
            unawaited(_stopVideo(notify: true, completedId: id));
          });
        },
      );
      _video = handle;
      await handle.setEffectiveVolume(_channelVolumes['master'] ?? 1);
      _setVideoPlayback(
        VideoPlayback(
          id: _videoId,
          view: handle.buildView(),
          aspectRatio: handle.aspectRatio,
          skippable: _videoSkippable,
        ),
      );
      await _maybeTimeout(handle.play(), startupTimeout);
      if (isFullscreen && !loop) {
        unawaited(_finishDeadFullscreenVideoIfNeeded(handle, file.path));
      }
    } on TimeoutException {
      Log.warn(
        '[MediaBridge] fullscreen video startup timeout, skipping: ${file.path}',
      );
      if (handle != null && _video != handle) await handle.dispose();
      await _stopVideo(notify: false);
      _videoFinishedCallback(id);
    } catch (e, st) {
      Log.warn(
        '[MediaBridge] video startup failed, skipping: ${file.path}: $e\n$st',
      );
      if (handle != null && _video != handle) await handle.dispose();
      await _stopVideo(notify: false);
      _videoFinishedCallback(id);
    }
  }

  Future<void> _playLayerVideo(
    String id,
    File file, {
    required bool loop,
  }) async {
    final active = _layerVideos[id];
    if (active != null && active.matches(file.path, loop)) {
      Log.debug('[MediaBridge] layer video duplicate ignored: id=$id');
      return;
    }

    final generation = (_layerVideoGenerations[id] ?? 0) + 1;
    _layerVideoGenerations[id] = generation;
    await _stopLayerVideo(id, notify: false, invalidate: false);
    if (_layerVideoGenerations[id] != generation) return;

    Log.debug('[MediaBridge] layer video start: id=$id, file=${file.path}');
    _MpvLayerVideoHandle? handle;
    try {
      handle = await _MpvLayerVideoHandle.create(
        id: id,
        file: file,
        loop: loop,
        upload: uploadVideoLayerFrame,
        onCompleted: (finishedId) {
          scheduleMicrotask(() {
            unawaited(
              _stopLayerVideo(finishedId, notify: true, generation: generation),
            );
          });
        },
      );
      if (_layerVideoGenerations[id] != generation) {
        await handle.dispose();
        return;
      }
      _layerVideos[id] = handle;
      await handle.play();
      if (_layerVideoGenerations[id] != generation) return;
      Log.debug('[MediaBridge] layer video playing: id=$id');
    } catch (e, st) {
      Log.warn(
        '[MediaBridge] layer video startup failed: ${file.path}: $e\n$st',
      );
      if (_layerVideoGenerations[id] == generation) {
        if (_layerVideos[id] == handle) {
          _layerVideos.remove(id);
        }
        _layerVideoGenerations.remove(id);
        if (handle != null) await handle.dispose();
        _videoFinishedCallback(id);
      } else if (handle != null && _layerVideos[id] != handle) {
        await handle.dispose();
      }
    }
  }

  void pumpLayerVideoFrames() {
    if (_disposed) return;
    for (final video in _layerVideos.values.toList(growable: false)) {
      video.pumpFrame();
    }
  }

  Future<void> _stopLayerVideo(
    String id, {
    required bool notify,
    int? generation,
    bool invalidate = true,
  }) async {
    if (generation != null && _layerVideoGenerations[id] != generation) return;
    if (invalidate) {
      _layerVideoGenerations[id] = (_layerVideoGenerations[id] ?? 0) + 1;
    }
    final video = _layerVideos.remove(id);
    if (video != null) await video.dispose();
    if (notify) _videoFinishedCallback(id);
  }

  Future<void> _stopAllVideos() async {
    await _stopVideo(notify: false);
    final layers = _layerVideos.values.toList(growable: false);
    _layerVideos.clear();
    _layerVideoGenerations.clear();
    for (final layer in layers) {
      await layer.dispose();
    }
  }

  Future<void> _finishDeadFullscreenVideoIfNeeded(
    _VideoHandle handle,
    String path,
  ) async {
    await Future<void>.delayed(const Duration(seconds: 3));
    if (_disposed || _video != handle || !_fullscreenVideoBlocking) return;
    if (handle.hasPlaybackSignal) return;
    Log.warn('[MediaBridge] fullscreen video did not start, skipping: $path');
    await _stopVideo(notify: true);
  }

  Future<void> skipVideo() async {
    if (!_videoSkippable) return;
    await _stopVideo(notify: true);
  }

  Future<void> _stopVideo({required bool notify, String? completedId}) async {
    final video = _video;
    final id = completedId ?? _videoId;
    final wasFullscreen = _fullscreenVideoBlocking;
    _video = null;
    _videoId = null;
    _videoSkippable = false;
    _setVideoPlayback(null);
    if (wasFullscreen) {
      await _afterNextFrame();
    }
    if (video != null) await video.dispose();
    if (wasFullscreen) {
      await _afterNextFrame();
    }
    _setFullscreenVideoBlocking(false);
    if (notify) _videoFinishedCallback(id);
  }

  void _setFullscreenVideoBlocking(bool blocking) {
    if (_fullscreenVideoBlocking == blocking) return;
    _fullscreenVideoBlocking = blocking;
    scheduleMicrotask(() {
      if (_disposed) return;
      fullscreenVideoBlocking.value = blocking;
    });
  }

  void _setVideoPlayback(VideoPlayback? playback) {
    if (_disposed) return;
    scheduleMicrotask(() {
      if (_disposed) return;
      videoPlayback.value = playback;
    });
  }

  Future<void> _afterNextFrame() {
    final completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    WidgetsBinding.instance.scheduleFrame();
    return completer.future;
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
        if (!_hasExtension(normalized)) '$normalized.mp4',
        if (!_hasExtension(normalized)) '$normalized.m4v',
        if (!_hasExtension(normalized)) '$normalized.mov',
        if (!_hasExtension(normalized)) '$normalized.mpg',
        if (!_hasExtension(normalized)) '$normalized.mpeg',
        if (!_hasExtension(normalized)) '$normalized.wmv',
        if (!_hasExtension(normalized)) '$normalized.asf',
        if (!_hasExtension(normalized)) '$normalized.avi',
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
      final id = _string(payload['id']);
      if (id == null) {
        unawaited(_stopVideo(notify: false));
      } else {
        unawaited(_stopLayerVideo(id, notify: false));
      }
      _videoFinishedCallback(id);
    } else if (kind == 'audio_bgm_play' || kind == 'audio_bgm_crossfade') {
      _soundFinishedCallback(null);
    } else if (kind == 'audio_se_play') {
      _soundFinishedCallback(_string(payload['id']));
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stopAllVideos();
    await _fullscreenVideoPool.dispose();
    await _stopAllAudio();
    videoPlayback.dispose();
    fullscreenVideoBlocking.dispose();
    try {
      if (_cacheDir.existsSync()) _cacheDir.deleteSync(recursive: true);
    } catch (_) {}
  }
}

class VideoPlayback {
  const VideoPlayback({
    required this.id,
    required this.view,
    required this.aspectRatio,
    required this.skippable,
  });

  final String? id;
  final Widget view;
  final double aspectRatio;
  final bool skippable;

  bool get isFullscreen => id == null;
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
    required this.subscriptions,
  });

  final String? id;
  final media_kit.Player player;
  final String channel;
  final bool loop;
  final void Function(String? id) onCompleted;
  double gain;
  double pan;
  Timer? _fadeTimer;
  Completer<void>? _fadeCompleter;
  Timer? _panTimer;
  Completer<void>? _panCompleter;
  Timer? _loopSegmentPollTimer;
  bool _loopSegmentPollInFlight = false;
  int _loopSegmentPollFailures = 0;
  bool _completed = false;
  bool _loopSegmentStarted = false;
  bool _disposed = false;
  double _effectiveVolume = 1;
  final List<StreamSubscription<dynamic>> subscriptions;

  static Future<_AudioHandle> create({
    required String? id,
    required File file,
    required File? loopFile,
    required String channel,
    required double gain,
    required double pan,
    required bool loop,
    required void Function(String? id) onCompleted,
  }) async {
    if (loopFile != null) {
      return _createGaplessPlaylist(
        id: id,
        file: file,
        loopFile: loopFile,
        channel: channel,
        gain: gain,
        pan: pan,
        onCompleted: onCompleted,
      );
    }
    // Every native target already bundles libmpv for video. Keeping audio on
    // the same decoder avoids target-specific codec support and completion
    // semantics from leaking into Artemis' audio model.
    return _createMediaKitSingle(
      id: id,
      file: file,
      channel: channel,
      gain: gain,
      pan: pan,
      loop: loop,
      onCompleted: onCompleted,
    );
  }

  static Future<_AudioHandle> _createMediaKitSingle({
    required String? id,
    required File file,
    required String channel,
    required double gain,
    required double pan,
    required bool loop,
    required void Function(String? id) onCompleted,
  }) async {
    final player = media_kit.Player();
    final subscriptions = <StreamSubscription<dynamic>>[];
    late final _AudioHandle handle;
    handle = _AudioHandle(
      id: id,
      player: player,
      channel: channel,
      gain: gain,
      pan: pan,
      loop: loop,
      onCompleted: onCompleted,
      subscriptions: subscriptions,
    );
    subscriptions.add(
      player.stream.completed.listen((completed) {
        if (!completed || handle._disposed || handle._completed || loop) return;
        handle._completed = true;
        onCompleted(id);
      }),
    );
    subscriptions.add(
      player.stream.error.listen((error) {
        Log.warn(
          '[MediaBridge] libmpv 音频解码失败: '
          'channel=$channel id=${id ?? "bgm"} file=${file.path}: $error',
        );
        if (handle._disposed || handle._completed) return;
        handle._completed = true;
        onCompleted(id);
      }),
    );
    try {
      await player.setPlaylistMode(
        loop ? media_kit.PlaylistMode.single : media_kit.PlaylistMode.none,
      );
      await player.open(media_kit.Media(file.uri.toString()), play: false);
      await handle.setPan(pan);
      Log.debug(
        '[MediaBridge] libmpv 音频已准备: '
        'channel=$channel id=${id ?? "bgm"} file=${file.path}',
      );
      return handle;
    } catch (_) {
      await Future.wait(subscriptions.map((sub) => sub.cancel()));
      await player.dispose();
      rethrow;
    }
  }

  static Future<_AudioHandle> _createGaplessPlaylist({
    required String? id,
    required File file,
    required File loopFile,
    required String channel,
    required double gain,
    required double pan,
    required void Function(String? id) onCompleted,
  }) async {
    final player = media_kit.Player();
    final subscriptions = <StreamSubscription<dynamic>>[];
    late final _AudioHandle handle;
    handle = _AudioHandle(
      id: id,
      player: player,
      channel: channel,
      gain: gain,
      pan: pan,
      loop: true,
      onCompleted: onCompleted,
      subscriptions: subscriptions,
    );
    // media_kit 的 completed 表示“当前 Media 播放结束”，而不是整个
    // Playlist 播放结束。A 段结束时 completed 会先于 playlist.index=1
    // 到达；这里若把它当作整个 BGM 完成，会立即 dispose player，导致
    // B 段还没开始就被停止。A-B BGM 在语义上是无限循环，因此完成状态
    // 只由显式 stop/dispose 管理，不订阅 completed。
    subscriptions.add(
      player.stream.error.listen((error) {
        Log.warn('[MediaBridge] BGM A-B playlist decode error: $error');
      }),
    );
    try {
      // 由 MPV 在同一原生播放队列内完成 A -> B，避免 Dart completion
      // 回调往返造成静音；B 开始后再把 playlist 模式切为单曲循环。
      final platform = player.platform;
      if (platform != null) {
        await (platform as dynamic).setProperty('gapless-audio', 'yes');
      }
      await player.setPlaylistMode(media_kit.PlaylistMode.none);
      await player.open(
        media_kit.Playlist([
          media_kit.Media(file.uri.toString()),
          media_kit.Media(loopFile.uri.toString()),
        ]),
        play: false,
      );
      await handle.setPan(pan);
      handle._monitorGaplessLoop(loopFile);
      Log.debug(
        '[MediaBridge] BGM A-B 无缝播放列表已准备: '
        '${file.path} -> ${loopFile.path}',
      );
      return handle;
    } catch (_) {
      await Future.wait(subscriptions.map((sub) => sub.cancel()));
      await player.dispose();
      rethrow;
    }
  }

  Future<void> play() {
    return player.play();
  }

  void _monitorGaplessLoop(File loopFile) {
    _loopSegmentPollTimer?.cancel();
    _loopSegmentPollTimer = Timer.periodic(
      const Duration(milliseconds: 50),
      (_) => unawaited(_pollGaplessLoop(loopFile)),
    );
  }

  Future<void> _pollGaplessLoop(File loopFile) async {
    if (_disposed || _loopSegmentStarted || _loopSegmentPollInFlight) return;
    _loopSegmentPollInFlight = true;
    try {
      final platform = player.platform;
      if (platform == null) return;
      final index = await (platform as dynamic).getProperty(
        'playlist-playing-pos',
      );
      if (index.toString().trim() != '1' || _loopSegmentStarted) return;
      // media_kit 1.2.6 leaves playlist state notifications disabled after
      // open(), so Player.stream.playlist never reports the A -> B edge. Set
      // libmpv's property directly once B is active.
      await (platform as dynamic).setProperty('loop-file', 'inf');
      _loopSegmentStarted = true;
      _loopSegmentPollTimer?.cancel();
      _loopSegmentPollTimer = null;
      Log.debug('[MediaBridge] BGM 已无缝进入 B 段循环: ${loopFile.path}');
    } catch (error, stackTrace) {
      _loopSegmentPollFailures += 1;
      if (_loopSegmentPollFailures == 1 || _loopSegmentPollFailures % 50 == 0) {
        Log.warn(
          '[MediaBridge] BGM B 段检测暂时失败 '
          '(attempt=$_loopSegmentPollFailures): ${loopFile.path}: '
          '$error\n$stackTrace',
        );
      }
    } finally {
      _loopSegmentPollInFlight = false;
    }
  }

  Future<void> setEffectiveVolume(double volume) async {
    _effectiveVolume = volume.clamp(0, 1);
    await player.setVolume(_effectiveVolume * 100);
  }

  Future<void> setPan(double value) async {
    pan = value.clamp(-1, 1);
    final platform = player.platform;
    if (platform == null) return;
    if (pan.abs() <= 0.001) {
      await (platform as dynamic).setProperty('af', '');
      return;
    }
    final left = pan > 0 ? 1 - pan : 1.0;
    final right = pan < 0 ? 1 + pan : 1.0;
    final filter =
        'lavfi=[pan=stereo|c0=${left.toStringAsFixed(4)}*c0|'
        'c1=${right.toStringAsFixed(4)}*c1]';
    await (platform as dynamic).setProperty('af', filter);
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
    _loopSegmentPollTimer?.cancel();
    _loopSegmentPollTimer = null;
    await Future.wait(subscriptions.map((sub) => sub.cancel()));
    await player.dispose();
  }
}

abstract class _VideoHandle {
  static Future<_VideoHandle> create({
    required _MediaKitVideoPool pool,
    required String? id,
    required File file,
    required bool loop,
    required Duration? startupTimeout,
    required void Function(String? id) onCompleted,
  }) async {
    return _MediaKitVideoHandle.create(
      pool: pool,
      id: id,
      file: file,
      loop: loop,
      startupTimeout: startupTimeout,
      onCompleted: onCompleted,
    );
  }

  String? get id;
  double get aspectRatio;
  bool get hasPlaybackSignal;

  Widget buildView();

  Future<void> play();

  Future<void> setEffectiveVolume(double volume);

  Future<void> dispose();
}

final class _MediaKitVideoLease {
  const _MediaKitVideoLease(this.player, this.controller);

  final media_kit.Player player;
  final media_kit_video.VideoController controller;
}

final class _MediaKitVideoPool {
  _MediaKitVideoLease? _idle;
  Future<void>? _warming;
  bool _disposed = false;

  void prewarm() {
    unawaited(
      _warm().then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {
          Log.warn('[MediaBridge] fullscreen mpv prewarm failed: $error');
        },
      ),
    );
  }

  Future<_MediaKitVideoLease> acquire() async {
    while (true) {
      final idle = _idle;
      if (idle != null) {
        _idle = null;
        return idle;
      }
      await _warm();
    }
  }

  Future<void> _warm() async {
    if (_disposed) throw StateError('video player pool is disposed');
    if (_idle != null) return;
    final warming = _warming;
    if (warming != null) {
      await warming;
      return;
    }

    final future = _createAndStoreLease();
    _warming = future;
    try {
      await future;
    } finally {
      if (identical(_warming, future)) _warming = null;
    }
  }

  Future<void> _createAndStoreLease() async {
    final lease = await _createLease();
    if (_disposed) {
      await lease.player.dispose();
      throw StateError('video player pool is disposed');
    }
    _idle = lease;
  }

  Future<_MediaKitVideoLease> _createLease() async {
    final started = Stopwatch()..start();
    final player = media_kit.Player();
    try {
      final controller = media_kit_video.VideoController(
        player,
        configuration: media_kit_video.VideoControllerConfiguration(
          enableHardwareAcceleration: false,
        ),
      );
      await player.setPlaylistMode(media_kit.PlaylistMode.none);
      Log.debug(
        '[MediaBridge] fullscreen mpv prewarmed: '
        '${started.elapsedMilliseconds}ms',
      );
      return _MediaKitVideoLease(player, controller);
    } catch (_) {
      await player.dispose();
      rethrow;
    }
  }

  Future<void> release(_MediaKitVideoLease lease) async {
    try {
      await lease.player.stop();
      await lease.player.setPlaylistMode(media_kit.PlaylistMode.none);
    } catch (error) {
      Log.warn('[MediaBridge] fullscreen mpv reset failed: $error');
      await lease.player.dispose();
      return;
    }
    if (_disposed || _idle != null) {
      await lease.player.dispose();
      return;
    }
    _idle = lease;
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final idle = _idle;
    _idle = null;
    if (idle != null) await idle.player.dispose();
  }
}

class _MediaKitVideoHandle implements _VideoHandle {
  _MediaKitVideoHandle({
    required this.id,
    required this.lease,
    required this.pool,
    required this.subscriptions,
    required this.startup,
  });

  @override
  final String? id;
  final _MediaKitVideoLease lease;
  final _MediaKitVideoPool pool;
  final List<StreamSubscription<dynamic>> subscriptions;
  final Stopwatch startup;
  bool _hasPlaybackSignal = false;
  bool _disposed = false;

  media_kit.Player get player => lease.player;
  media_kit_video.VideoController get controller => lease.controller;

  static Future<_MediaKitVideoHandle> create({
    required _MediaKitVideoPool pool,
    required String? id,
    required File file,
    required bool loop,
    required Duration? startupTimeout,
    required void Function(String? id) onCompleted,
  }) async {
    final startup = Stopwatch()..start();
    final lease = await pool.acquire();
    final player = lease.player;
    var completed = false;
    void finish() {
      if (completed) return;
      completed = true;
      onCompleted(id);
    }

    final handle = _MediaKitVideoHandle(
      id: id,
      lease: lease,
      pool: pool,
      subscriptions: <StreamSubscription<dynamic>>[],
      startup: startup,
    );
    handle.subscriptions.add(
      player.stream.completed.listen((isCompleted) {
        if (!isCompleted || loop || completed) return;
        finish();
      }),
    );
    handle.subscriptions.add(
      player.stream.error.listen((error) {
        Log.warn('[MediaBridge] video decode error: $error');
        if (!loop) finish();
      }),
    );
    handle.subscriptions.add(
      player.stream.width.listen((value) {
        if ((value ?? 0) > 0) handle._markPlaybackSignal();
      }),
    );
    handle.subscriptions.add(
      player.stream.height.listen((value) {
        if ((value ?? 0) > 0) handle._markPlaybackSignal();
      }),
    );
    handle.subscriptions.add(
      player.stream.duration.listen((value) {
        if (value > Duration.zero) handle._markPlaybackSignal();
      }),
    );
    handle.subscriptions.add(
      player.stream.position.listen((value) {
        if (value > Duration.zero) handle._markPlaybackSignal();
      }),
    );
    try {
      await _maybeTimeout(
        player.setPlaylistMode(
          loop ? media_kit.PlaylistMode.single : media_kit.PlaylistMode.none,
        ),
        startupTimeout,
      );
      await _maybeTimeout(
        player.open(media_kit.Media(file.uri.toString()), play: false),
        startupTimeout,
      );
      Log.debug(
        '[MediaBridge] fullscreen mpv opened: '
        '${startup.elapsedMilliseconds}ms, file=${file.path}',
      );
      return handle;
    } catch (_) {
      await handle.dispose();
      rethrow;
    }
  }

  @override
  double get aspectRatio {
    final width = player.state.width;
    final height = player.state.height;
    if (width != null && height != null && width > 0 && height > 0) {
      return width / height;
    }
    return 16 / 9;
  }

  @override
  bool get hasPlaybackSignal => _hasPlaybackSignal;

  void _markPlaybackSignal() {
    if (_hasPlaybackSignal) return;
    _hasPlaybackSignal = true;
    Log.debug(
      '[MediaBridge] fullscreen mpv first signal: '
      '${startup.elapsedMilliseconds}ms',
    );
  }

  @override
  Widget buildView() => media_kit_video.Video(
    controller: controller,
    controls: media_kit_video.NoVideoControls,
    fit: BoxFit.contain,
    fill: const Color(0x00000000),
  );

  @override
  Future<void> play() => player.play();

  @override
  Future<void> setEffectiveVolume(double volume) {
    return player.setVolume(volume.clamp(0, 1) * 100);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await Future.wait(subscriptions.map((sub) => sub.cancel()));
    await pool.release(lease);
  }
}

class _MpvLayerVideoHandle {
  _MpvLayerVideoHandle({
    required this.id,
    required this.sourcePath,
    required this.loop,
    required this.upload,
    required this.onCompleted,
    required this.receivePort,
    required this.isolate,
  });

  final String id;
  final String sourcePath;
  final bool loop;
  final VideoLayerFrameUploader upload;
  final void Function(String id) onCompleted;
  final ReceivePort receivePort;
  final Isolate isolate;
  StreamSubscription<dynamic>? _subscription;
  SendPort? _worker;
  _LayerVideoFrame? _pendingFrame;
  Completer<void>? _stopped;
  bool _disposed = false;
  bool _loggedFirstFrame = false;

  static Future<_MpvLayerVideoHandle> create({
    required String id,
    required File file,
    required bool loop,
    required VideoLayerFrameUploader upload,
    required void Function(String id) onCompleted,
  }) async {
    Log.debug('[MediaBridge] layer video creating mpv context: id=$id');
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(_mpvLayerVideoWorker, [
      receivePort.sendPort,
      id,
      file.path,
      loop,
    ], debugName: 'art3m1s-layer-video-$id');
    final handle = _MpvLayerVideoHandle(
      id: id,
      sourcePath: file.path,
      loop: loop,
      upload: upload,
      onCompleted: onCompleted,
      receivePort: receivePort,
      isolate: isolate,
    );
    try {
      await handle._initialize();
      Log.debug('[MediaBridge] layer video opened: id=$id');
      return handle;
    } catch (_) {
      await handle.dispose();
      rethrow;
    }
  }

  Future<void> _initialize() async {
    final ready = Completer<void>();
    _subscription = receivePort.listen((message) {
      if (message is! List || message.isEmpty) return;
      switch (message[0]) {
        case 'ready':
          _worker = message[1] as SendPort;
          if (!ready.isCompleted) ready.complete();
        case 'frame':
          final previous = _pendingFrame;
          if (previous != null) {
            _worker?.send(['release', previous.sequence]);
          }
          _pendingFrame = _LayerVideoFrame(
            sequence: message[1] as int,
            address: message[2] as int,
            width: message[3] as int,
            height: message[4] as int,
          );
        case 'completed':
          if (!_disposed) onCompleted(id);
        case 'error':
          final error = StateError(message[1] as String);
          if (!ready.isCompleted) {
            ready.completeError(error);
          } else {
            Log.warn('[MediaBridge] layer video worker error: $error');
            if (!_disposed) onCompleted(id);
          }
        case 'stopped':
          _stopped?.complete();
      }
    });
    await ready.future.timeout(const Duration(seconds: 5));
  }

  Future<void> play() async => _worker?.send(const ['play']);

  void pumpFrame() {
    final frame = _pendingFrame;
    if (_disposed || frame == null) return;
    _pendingFrame = null;
    final uploaded = upload(
      id,
      frame.width,
      frame.height,
      Pointer<Uint8>.fromAddress(frame.address),
      frame.width * frame.height * 4,
    );
    _worker?.send(['release', frame.sequence]);
    if (!_loggedFirstFrame) {
      _loggedFirstFrame = true;
      Log.debug(
        '[MediaBridge] layer video first frame: '
        'id=$id, size=${frame.width}x${frame.height}, uploaded=$uploaded',
      );
    }
  }

  bool matches(String path, bool shouldLoop) =>
      sourcePath == path && loop == shouldLoop;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final pending = _pendingFrame;
    _pendingFrame = null;
    if (pending != null) _worker?.send(['release', pending.sequence]);
    final worker = _worker;
    if (worker != null) {
      _stopped = Completer<void>();
      worker.send(const ['stop']);
      try {
        await _stopped!.future.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        isolate.kill(priority: Isolate.immediate);
      }
    } else {
      isolate.kill(priority: Isolate.immediate);
    }
    await _subscription?.cancel();
    receivePort.close();
  }
}

class _LayerVideoFrame {
  _LayerVideoFrame({
    required this.sequence,
    required this.address,
    required this.width,
    required this.height,
  });

  final int sequence;
  final int address;
  final int width;
  final int height;
}

Future<void> _mpvLayerVideoWorker(List<Object?> arguments) async {
  final mainPort = arguments[0] as SendPort;
  final id = arguments[1] as String;
  final path = arguments[2] as String;
  final loop = arguments[3] as bool;
  final commands = ReceivePort();
  _MpvSoftwareRenderer? renderer;
  Timer? pumpTimer;
  var frameLeased = false;
  var sequence = 0;

  Future<void> stop() async {
    pumpTimer?.cancel();
    renderer?.dispose();
    renderer = null;
    mainPort.send(const ['stopped']);
    commands.close();
  }

  commands.listen((message) {
    if (message is! List || message.isEmpty) return;
    switch (message[0]) {
      case 'play':
        renderer?.play();
      case 'release':
        frameLeased = false;
      case 'stop':
        unawaited(stop());
    }
  });

  try {
    renderer = _MpvSoftwareRenderer.create(
      id: id,
      file: File(path),
      loop: loop,
      upload: (_, width, height, pixels, _) {
        if (frameLeased) return false;
        frameLeased = true;
        sequence++;
        mainPort.send(['frame', sequence, pixels.address, width, height]);
        return true;
      },
      onCompleted: (_) => mainPort.send(const ['completed']),
    );
    mainPort.send(['ready', commands.sendPort]);
    pumpTimer = Timer.periodic(const Duration(milliseconds: 2), (_) {
      if (!frameLeased) renderer?.pumpFrame();
    });
  } catch (error, stackTrace) {
    mainPort.send(['error', '$error\n$stackTrace']);
    await stop();
  }
}

final class _MpvRenderParam extends Struct {
  @Int32()
  external int type;

  external Pointer<Void> data;
}

typedef _MpvRenderContextCreateNative =
    Int32 Function(
      Pointer<Pointer<Void>> context,
      Pointer<Void> player,
      Pointer<_MpvRenderParam> params,
    );
typedef _MpvRenderContextCreate =
    int Function(
      Pointer<Pointer<Void>>,
      Pointer<Void>,
      Pointer<_MpvRenderParam>,
    );
typedef _MpvRenderContextRenderNative =
    Void Function(Pointer<Void> context, Pointer<_MpvRenderParam> params);
typedef _MpvRenderContextRender =
    void Function(Pointer<Void>, Pointer<_MpvRenderParam>);
typedef _MpvRenderContextFreeNative = Void Function(Pointer<Void> context);
typedef _MpvRenderContextFree = void Function(Pointer<Void>);
typedef _MpvRenderUpdateNative = Void Function(Pointer<Void> context);
typedef _MpvRenderContextSetUpdateCallbackNative =
    Void Function(
      Pointer<Void> context,
      Pointer<NativeFunction<_MpvRenderUpdateNative>> callback,
      Pointer<Void> callbackContext,
    );
typedef _MpvRenderContextSetUpdateCallback =
    void Function(
      Pointer<Void>,
      Pointer<NativeFunction<_MpvRenderUpdateNative>>,
      Pointer<Void>,
    );
typedef _MpvCreateNative = Pointer<Void> Function();
typedef _MpvCreate = Pointer<Void> Function();
typedef _MpvInitializeNative = Int32 Function(Pointer<Void> handle);
typedef _MpvInitialize = int Function(Pointer<Void>);
typedef _MpvSetStringNative =
    Int32 Function(
      Pointer<Void> handle,
      Pointer<Int8> name,
      Pointer<Int8> value,
    );
typedef _MpvSetString =
    int Function(Pointer<Void>, Pointer<Int8>, Pointer<Int8>);
typedef _MpvCommandNative =
    Int32 Function(Pointer<Void> handle, Pointer<Pointer<Int8>> args);
typedef _MpvCommand = int Function(Pointer<Void>, Pointer<Pointer<Int8>>);
typedef _MpvGetPropertyStringNative =
    Pointer<Int8> Function(Pointer<Void> handle, Pointer<Int8> name);
typedef _MpvGetPropertyString =
    Pointer<Int8> Function(Pointer<Void>, Pointer<Int8>);
typedef _MpvFreeNative = Void Function(Pointer<Void> data);
typedef _MpvFree = void Function(Pointer<Void>);
typedef _MpvTerminateDestroyNative = Void Function(Pointer<Void> handle);
typedef _MpvTerminateDestroy = void Function(Pointer<Void>);
typedef _MpvErrorStringNative = Pointer<Int8> Function(Int32 error);
typedef _MpvErrorString = Pointer<Int8> Function(int);

class _MpvApi {
  _MpvApi(DynamicLibrary library)
    : create = library.lookupFunction<_MpvCreateNative, _MpvCreate>(
        'mpv_create',
      ),
      initialize = library.lookupFunction<_MpvInitializeNative, _MpvInitialize>(
        'mpv_initialize',
      ),
      setOptionString = library
          .lookupFunction<_MpvSetStringNative, _MpvSetString>(
            'mpv_set_option_string',
          ),
      setPropertyString = library
          .lookupFunction<_MpvSetStringNative, _MpvSetString>(
            'mpv_set_property_string',
          ),
      command = library.lookupFunction<_MpvCommandNative, _MpvCommand>(
        'mpv_command',
      ),
      getPropertyString = library
          .lookupFunction<_MpvGetPropertyStringNative, _MpvGetPropertyString>(
            'mpv_get_property_string',
          ),
      free = library.lookupFunction<_MpvFreeNative, _MpvFree>('mpv_free'),
      terminateDestroy = library
          .lookupFunction<_MpvTerminateDestroyNative, _MpvTerminateDestroy>(
            'mpv_terminate_destroy',
          ),
      errorString = library
          .lookupFunction<_MpvErrorStringNative, _MpvErrorString>(
            'mpv_error_string',
          ),
      renderContextCreate = library
          .lookupFunction<
            _MpvRenderContextCreateNative,
            _MpvRenderContextCreate
          >('mpv_render_context_create'),
      renderContextRender = library
          .lookupFunction<
            _MpvRenderContextRenderNative,
            _MpvRenderContextRender
          >('mpv_render_context_render'),
      renderContextFree = library
          .lookupFunction<_MpvRenderContextFreeNative, _MpvRenderContextFree>(
            'mpv_render_context_free',
          ),
      renderContextSetUpdateCallback = library
          .lookupFunction<
            _MpvRenderContextSetUpdateCallbackNative,
            _MpvRenderContextSetUpdateCallback
          >('mpv_render_context_set_update_callback');

  final _MpvCreate create;
  final _MpvInitialize initialize;
  final _MpvSetString setOptionString;
  final _MpvSetString setPropertyString;
  final _MpvCommand command;
  final _MpvGetPropertyString getPropertyString;
  final _MpvFree free;
  final _MpvTerminateDestroy terminateDestroy;
  final _MpvErrorString errorString;
  final _MpvRenderContextCreate renderContextCreate;
  final _MpvRenderContextRender renderContextRender;
  final _MpvRenderContextFree renderContextFree;
  final _MpvRenderContextSetUpdateCallback renderContextSetUpdateCallback;

  String error(int code) {
    final value = errorString(code);
    return value == nullptr
        ? 'mpv error $code'
        : value.cast<Utf8>().toDartString();
  }

  void check(int result, String operation) {
    if (result < 0) throw StateError('$operation failed: ${error(result)}');
  }

  void setOption(Pointer<Void> handle, String name, String value) {
    final nativeName = name.toNativeUtf8();
    final nativeValue = value.toNativeUtf8();
    try {
      check(
        setOptionString(
          handle,
          nativeName.cast<Int8>(),
          nativeValue.cast<Int8>(),
        ),
        'mpv_set_option_string($name)',
      );
    } finally {
      malloc.free(nativeName);
      malloc.free(nativeValue);
    }
  }

  void setOptionalOption(Pointer<Void> handle, String name, String value) {
    final nativeName = name.toNativeUtf8();
    final nativeValue = value.toNativeUtf8();
    try {
      final result = setOptionString(
        handle,
        nativeName.cast<Int8>(),
        nativeValue.cast<Int8>(),
      );
      if (result < 0) {
        Log.debug(
          '[MediaBridge] mpv optional option ignored: '
          '$name=$value (${error(result)})',
        );
      }
    } finally {
      malloc.free(nativeName);
      malloc.free(nativeValue);
    }
  }

  void setProperty(Pointer<Void> handle, String name, String value) {
    final nativeName = name.toNativeUtf8();
    final nativeValue = value.toNativeUtf8();
    try {
      check(
        setPropertyString(
          handle,
          nativeName.cast<Int8>(),
          nativeValue.cast<Int8>(),
        ),
        'mpv_set_property_string($name)',
      );
    } finally {
      malloc.free(nativeName);
      malloc.free(nativeValue);
    }
  }

  void runCommand(Pointer<Void> handle, List<String> arguments) {
    final values = arguments.map((value) => value.toNativeUtf8()).toList();
    final nativeArguments = calloc<Pointer<Int8>>(values.length + 1);
    try {
      for (var index = 0; index < values.length; index++) {
        nativeArguments[index] = values[index].cast<Int8>();
      }
      nativeArguments[values.length] = nullptr;
      check(
        command(handle, nativeArguments),
        'mpv_command(${arguments.first})',
      );
    } finally {
      for (final value in values) {
        malloc.free(value);
      }
      calloc.free(nativeArguments);
    }
  }

  String? property(Pointer<Void> handle, String name) {
    final nativeName = name.toNativeUtf8();
    try {
      final value = getPropertyString(handle, nativeName.cast<Int8>());
      if (value == nullptr) return null;
      try {
        return value.cast<Utf8>().toDartString();
      } finally {
        free(value.cast<Void>());
      }
    } finally {
      malloc.free(nativeName);
    }
  }
}

class _MpvSoftwareRenderer {
  _MpvSoftwareRenderer._(
    this.api, {
    required this.id,
    required this.upload,
    required this.onCompleted,
    required this.loop,
    required this.handle,
    required this.context,
  }) : _params = calloc<_MpvRenderParam>(5),
       _size = calloc<Int32>(2),
       _stride = calloc<IntPtr>(),
       _format = 'rgb0'.toNativeUtf8();

  static const int _paramInvalid = 0;
  static const int _paramApiType = 1;
  static const int _paramSwSize = 17;
  static const int _paramSwFormat = 18;
  static const int _paramSwStride = 19;
  static const int _paramSwPointer = 20;

  final _MpvApi api;
  final String id;
  final VideoLayerFrameUploader upload;
  final void Function(String id) onCompleted;
  final bool loop;
  final Pointer<Void> handle;
  final Pointer<Void> context;
  final Pointer<_MpvRenderParam> _params;
  final Pointer<Int32> _size;
  final Pointer<IntPtr> _stride;
  final Pointer<Utf8> _format;
  Pointer<Uint8>? _pixels;
  int _width = 0;
  int _height = 0;
  bool _disposed = false;
  bool _loggedSizeUnavailable = false;
  bool _completed = false;
  bool _framePending = true;
  int _sizeAttempts = 0;
  late final NativeCallable<_MpvRenderUpdateNative> _updateCallable;

  static _MpvSoftwareRenderer create({
    required String id,
    required File file,
    required bool loop,
    required VideoLayerFrameUploader upload,
    required void Function(String id) onCompleted,
  }) {
    final api = _MpvApi(_openMpvLibrary());
    final handle = api.create();
    if (handle == nullptr) throw StateError('mpv_create failed');

    Pointer<Void> context = nullptr;
    final output = calloc<Pointer<Void>>();
    final params = calloc<_MpvRenderParam>(2);
    final renderApi = 'sw'.toNativeUtf8();
    try {
      api.setOptionalOption(handle, 'config', 'no');
      api.setOptionalOption(handle, 'terminal', 'no');
      api.setOptionalOption(handle, 'aid', 'no');
      api.setOptionalOption(handle, 'audio-display', 'no');
      api.setOption(handle, 'vid', 'auto');
      api.setOption(handle, 'vo', 'libmpv');
      api.setOptionalOption(handle, 'hwdec', 'no');
      api.setOptionalOption(handle, 'video-timing-offset', '0');
      if (loop) api.setOptionalOption(handle, 'loop-file', 'inf');
      api.check(api.initialize(handle), 'mpv_initialize');

      params[0]
        ..type = _paramApiType
        ..data = renderApi.cast<Void>();
      params[1]
        ..type = _paramInvalid
        ..data = nullptr;
      final result = api.renderContextCreate(output, handle, params);
      if (result < 0 || output.value == nullptr) {
        throw StateError(
          'mpv_render_context_create failed: ${api.error(result)}',
        );
      }
      context = output.value;
      final renderer = _MpvSoftwareRenderer._(
        api,
        id: id,
        upload: upload,
        onCompleted: onCompleted,
        loop: loop,
        handle: handle,
        context: context,
      );
      renderer._installUpdateCallback();
      api.runCommand(handle, ['loadfile', file.path, 'replace']);
      api.setProperty(handle, 'pause', 'no');
      Log.debug('[MediaBridge] mpv software context ready: id=$id');
      return renderer;
    } catch (_) {
      if (context != nullptr) api.renderContextFree(context);
      api.terminateDestroy(handle);
      rethrow;
    } finally {
      malloc.free(renderApi);
      calloc.free(params);
      calloc.free(output);
    }
  }

  void play() {
    if (_disposed) return;
    api.setProperty(handle, 'pause', 'no');
  }

  void _installUpdateCallback() {
    void onUpdate(Pointer<Void> _) {
      _framePending = true;
    }

    _updateCallable = NativeCallable<_MpvRenderUpdateNative>.listener(onUpdate);
    _updateCallable.keepIsolateAlive = false;
    api.renderContextSetUpdateCallback(
      context,
      _updateCallable.nativeFunction,
      nullptr,
    );
  }

  void pumpFrame() {
    if (_disposed) return;
    if (!loop && !_completed && api.property(handle, 'eof-reached') == 'yes') {
      _completed = true;
      onCompleted(id);
      return;
    }
    if (!_framePending) return;
    _framePending = false;

    if (_width <= 0 || _height <= 0) {
      final size = _readVideoSize();
      if (size == null) {
        _framePending = true;
        _sizeAttempts++;
        if (_sizeAttempts >= 120 && !_loggedSizeUnavailable) {
          _loggedSizeUnavailable = true;
          Log.warn('[MediaBridge] layer video size unavailable: id=$id');
        }
        return;
      }
      _width = size.$1;
      _height = size.$2;
      Log.debug(
        '[MediaBridge] layer video size: id=$id, '
        'size=${_width}x$_height',
      );
    }

    _render(_width, _height);
  }

  (int, int)? _readVideoSize() {
    final width = _readDimension(const [
      'video-out-params/dw',
      'video-params/dw',
      'video-params/w',
      'dwidth',
      'width',
    ]);
    final height = _readDimension(const [
      'video-out-params/dh',
      'video-params/dh',
      'video-params/h',
      'dheight',
      'height',
    ]);
    if (width > 0 && height > 0) return (width, height);

    for (var index = 0; index < 16; index++) {
      final prefix = 'track-list/$index';
      if (api.property(handle, '$prefix/type') != 'video') continue;
      final trackWidth = _readDimension(['$prefix/demux-w', '$prefix/w']);
      final trackHeight = _readDimension(['$prefix/demux-h', '$prefix/h']);
      if (trackWidth > 0 && trackHeight > 0) {
        return (trackWidth, trackHeight);
      }
    }
    return null;
  }

  int _readDimension(List<String> properties) {
    for (final property in properties) {
      final value = int.tryParse(api.property(handle, property) ?? '');
      if (value != null && value > 0) return value;
    }
    return 0;
  }

  void _render(int width, int height) {
    if (_pixels == null || width != _width || height != _height) {
      if (_pixels != null) malloc.free(_pixels!);
      final length = width * height * 4;
      _pixels = malloc<Uint8>(length);
      _width = width;
      _height = height;
      _size[0] = width;
      _size[1] = height;
      _stride.value = width * 4;
      _params[0]
        ..type = _paramSwSize
        ..data = _size.cast<Void>();
      _params[1]
        ..type = _paramSwFormat
        ..data = _format.cast<Void>();
      _params[2]
        ..type = _paramSwStride
        ..data = _stride.cast<Void>();
      _params[3]
        ..type = _paramSwPointer
        ..data = _pixels!.cast<Void>();
      _params[4]
        ..type = _paramInvalid
        ..data = nullptr;
    }
    api.renderContextRender(context, _params);
    upload(id, width, height, _pixels!, width * height * 4);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    api.renderContextSetUpdateCallback(
      context,
      nullptr.cast<NativeFunction<_MpvRenderUpdateNative>>(),
      nullptr,
    );
    _updateCallable.close();
    api.renderContextFree(context);
    api.terminateDestroy(handle);
    if (_pixels != null) malloc.free(_pixels!);
    malloc.free(_format);
    calloc.free(_stride);
    calloc.free(_size);
    calloc.free(_params);
  }
}

DynamicLibrary _openMpvLibrary() {
  if (Platform.isMacOS || Platform.isIOS) {
    final process = DynamicLibrary.process();
    process.lookup<NativeFunction<_MpvCreateNative>>('mpv_create');
    return process;
  }

  final names = switch (Platform.operatingSystem) {
    'windows' => const ['libmpv-2.dll', 'mpv-2.dll', 'mpv-1.dll'],
    'linux' => const ['libmpv.so', 'libmpv.so.2', 'libmpv.so.1'],
    'android' => const ['libmpv.so'],
    _ => const <String>[],
  };
  Object? lastError;
  for (final name in names) {
    try {
      return DynamicLibrary.open(name);
    } catch (error) {
      lastError = error;
    }
  }
  throw StateError('Unable to open libmpv: $lastError');
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

Future<T> _maybeTimeout<T>(Future<T> future, Duration? timeout) {
  if (timeout == null) return future;
  return future.timeout(timeout);
}

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
  final normalized = path.replaceAll('\\', '/');
  final name = normalized.split('/').last;
  final dot = name.lastIndexOf('.');
  if (dot <= 0 || dot == name.length - 1) return '.bin';
  final ext = name.substring(dot);
  return RegExp(r'^\.[A-Za-z0-9]{1,8}$').hasMatch(ext) ? ext : '.bin';
}
