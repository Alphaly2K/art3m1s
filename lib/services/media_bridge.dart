import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
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
       _soundFinishedCallback = onSoundFinished;

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
  final Map<String, File> _assetCache = {};
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
          await _stopSound(
            _string(payload['id']),
            fadeMs: _int(payload['fade_ms']),
          );
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
    await _bgm?.setEffectiveVolume(_effectiveVolume('bgm', _bgm!.gain));
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
    await handle.setEffectiveVolume(
      fadeMs > 0 ? 0 : _effectiveVolume('bgm', gain),
    );
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
    await bgm.fadeTo(
      _effectiveVolume('bgm', bgm.gain),
      _int(payload['time_ms']),
    );
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
    await handle.setEffectiveVolume(
      fadeMs > 0 ? 0 : _effectiveVolume(channel, gain),
    );
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
    await handle.fadeTo(
      _effectiveVolume(channel, handle.gain),
      _int(payload['time_ms']),
    );
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
    } else if (kind == 'audio_bgm_play') {
      _soundFinishedCallback(null);
    } else if (kind == 'audio_se_play') {
      _soundFinishedCallback(_string(payload['id']));
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _stopAllVideos();
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

abstract class _VideoHandle {
  static Future<_VideoHandle> create({
    required String? id,
    required File file,
    required bool loop,
    required Duration? startupTimeout,
    required void Function(String? id) onCompleted,
  }) async {
    return _MediaKitVideoHandle.create(
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

class _MediaKitVideoHandle implements _VideoHandle {
  _MediaKitVideoHandle({
    required this.id,
    required this.player,
    required this.controller,
    required this.subscriptions,
  });

  @override
  final String? id;
  final media_kit.Player player;
  final media_kit_video.VideoController controller;
  final List<StreamSubscription<dynamic>> subscriptions;
  bool _hasPlaybackSignal = false;

  static Future<_MediaKitVideoHandle> create({
    required String? id,
    required File file,
    required bool loop,
    required Duration? startupTimeout,
    required void Function(String? id) onCompleted,
  }) async {
    final player = media_kit.Player();
    var completed = false;
    void finish() {
      if (completed) return;
      completed = true;
      onCompleted(id);
    }

    final controller = media_kit_video.VideoController(
      player,
      configuration: media_kit_video.VideoControllerConfiguration(
        enableHardwareAcceleration: false,
      ),
    );
    final handle = _MediaKitVideoHandle(
      id: id,
      player: player,
      controller: controller,
      subscriptions: <StreamSubscription<dynamic>>[],
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
        if ((value ?? 0) > 0) handle._hasPlaybackSignal = true;
      }),
    );
    handle.subscriptions.add(
      player.stream.height.listen((value) {
        if ((value ?? 0) > 0) handle._hasPlaybackSignal = true;
      }),
    );
    handle.subscriptions.add(
      player.stream.duration.listen((value) {
        if (value > Duration.zero) handle._hasPlaybackSignal = true;
      }),
    );
    handle.subscriptions.add(
      player.stream.position.listen((value) {
        if (value > Duration.zero) handle._hasPlaybackSignal = true;
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
    await Future.wait(subscriptions.map((sub) => sub.cancel()));
    await player.dispose();
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
