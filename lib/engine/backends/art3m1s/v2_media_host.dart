part of 'media_bridge.dart';

typedef _PlaybackFeedback =
    void Function(String id, ArtemisPlaybackStatus status);

final class ArtemisV2MediaHost extends MediaBridge {
  ArtemisV2MediaHost()
    : super(onVideoFinished: (_) {}, onSoundFinished: (_) {});

  final _playbacks = <String, _V2AudioPlayback>{};
  final _videos = <String, _V2VideoPlayback>{};
  final _videoAssets = <String, Future<File>>{};
  final _fading = <_AudioHandle>{};
  final _work = <Future<void>>{};
  _V2VideoPlayback? _fullscreen;

  void handle(
    ArtemisFlutterSession session,
    String epoch,
    ArtemisMediaCommand command,
    void Function(String, ArtemisPlaybackStatus) feedback,
  ) {
    if (_disposed) return;
    switch (command) {
      case ArtemisAudioPlay():
        _start(command, feedback);
      case ArtemisAudioUpdate(
        :final action,
        :final ids,
        :final timeMs,
        :final value,
      ):
        for (final id in ids) {
          final track = _playbacks[id];
          if (track == null || track.stopping) continue;
          switch (action) {
            case ArtemisAudioAction.stop:
              _stop(track, timeMs);
            case ArtemisAudioAction.gain:
              track.gain = _gain(value, fallback: track.gain);
              final handle = track.handle;
              if (handle != null) {
                handle.gain = track.gain;
                _run(
                  handle.fadeTo(
                    _effectiveVolume(handle.channel, track.gain),
                    timeMs,
                  ),
                );
              }
            case ArtemisAudioAction.pan:
              track.pan = _pan(value);
              final handle = track.handle;
              if (handle != null) _run(handle.panTo(track.pan, timeMs));
          }
        }
      case ArtemisMediaStopAll(:final audio, :final fadeMs):
        if (audio) {
          for (final track in _playbacks.values.toList()) {
            _stop(track, fadeMs);
          }
        } else {
          _stopVideos();
        }
      case ArtemisAudioRestore(:final plays, :final stopVideo):
        _resetAudio();
        if (stopVideo) _stopVideos();
        for (final play in plays) {
          _start(play, feedback);
        }
      case ArtemisVideoPlay():
        final previous = _videos[command.replaces];
        if (previous != null) _closeVideo(previous);
        final track = _V2VideoPlayback(session, command, feedback);
        _videos[command.id] = track;
        _run(_openVideo(track, epoch));
    }
  }

  Future<void> _openVideo(_V2VideoPlayback track, String epoch) async {
    final play = track.play;
    final pending = _videoAssets.putIfAbsent(play.key, () async {
      final bytes = _assetReader?.call(play.key);
      if (bytes == null) throw StateError('Missing video asset');
      final file = File(
        '${_cacheDir.path}/video_${_stableId(play.key)}${_extension(play.key)}',
      );
      return file.writeAsBytes(bytes);
    });
    try {
      final asset = await pending;
      if (!identical(_videos[play.id], track)) return;
      await track.session.suspendVideos(_suspended);
      if (!identical(_videos[play.id], track)) return;
      await track.session.openVideo(epoch: epoch, play: play, path: asset.path);
      if (!identical(_videos[play.id], track)) {
        await track.session.closeVideo(play.id);
      }
    } catch (_) {
      if (identical(_videoAssets[play.key], pending)) {
        _videoAssets.remove(play.key);
      }
      if (identical(_videos[play.id], track)) {
        _closeVideo(track, status: ArtemisPlaybackStatus.failed);
      }
      rethrow;
    }
  }

  Future<void> pollVideo(ArtemisFlutterSession session) async {
    if (_videos.isEmpty) return;
    for (final event in await session.pollVideos()) {
      final track = _videos[event.id];
      if (track == null || !identical(track.session, session)) continue;
      if (event.status != ArtemisPlaybackStatus.started) {
        _closeVideo(track, status: event.status, notifyRunner: false);
        continue;
      }
      if (event.texture case final texture?) {
        _fullscreen = track;
        videoPlayback.value = EngineVideoPlayback(
          id: null,
          view: Texture(textureId: texture),
          aspectRatio: event.width! / event.height!,
          skippable: track.play.skip == 1,
          onMenuSkip: track.play.skip == 2 ? () => _skip(track) : null,
        );
      }
      track.feedback(track.play.id, event.status);
    }
  }

  @override
  Future<void> skipVideo() async {
    final track = _fullscreen;
    if (track != null && track.play.skip == 1) {
      _skip(track);
    }
  }

  void _skip(_V2VideoPlayback track) {
    if (identical(_fullscreen, track)) {
      _closeVideo(track, status: ArtemisPlaybackStatus.cancelled);
    }
  }

  void _closeVideo(
    _V2VideoPlayback track, {
    ArtemisPlaybackStatus? status,
    bool notifyRunner = true,
  }) {
    _videos.remove(track.play.id);
    if (identical(_fullscreen, track)) {
      _fullscreen = null;
      videoPlayback.value = null;
    }
    if (notifyRunner) _run(track.session.closeVideo(track.play.id));
    if (status != null) track.feedback(track.play.id, status);
  }

  void _stopVideos() {
    for (final track in _videos.values.toList()) {
      _closeVideo(track);
    }
  }

  void _start(ArtemisAudioPlay play, _PlaybackFeedback feedback) {
    final previous = _playbacks.remove(play.replaces);
    final track = _V2AudioPlayback(play, feedback);
    final previousHandle = previous?.handle;
    if (previousHandle != null) {
      _fading.add(previousHandle);
    }
    _playbacks[play.id] = track;
    _run(_open(track, previousHandle));
  }

  Future<void> _open(_V2AudioPlayback track, _AudioHandle? previous) async {
    final play = track.play;
    Future<void> retirePrevious(int fadeMs) async {
      final handle = previous;
      previous = null;
      if (handle == null || !_fading.contains(handle)) return;
      try {
        if (fadeMs > 0) await handle.fadeTo(0, fadeMs);
      } finally {
        _fading.remove(handle);
        await handle.dispose();
      }
    }

    try {
      if (!play.crossfade) await retirePrevious(0);
      final file = await _resolveAsset({'file': play.key}, projectOnly: true);
      if (!_current(track)) return;
      if (file == null) {
        _finish(track, ArtemisPlaybackStatus.failed);
        return;
      }
      final loopKey = play.loopKey;
      final loopFile = loopKey == null
          ? null
          : await _resolveAsset({'file': loopKey}, projectOnly: true);
      if (!_current(track)) return;

      final handle = await _AudioHandle.create(
        id: play.scriptId,
        file: file,
        loopFile: loopFile,
        channel: play.channel.name,
        gain: track.gain,
        pan: track.pan,
        loop: play.loop,
        onCompleted: (_) {
          if (!_current(track)) return;
          if (!track.stopping) _started(track);
          _finish(
            track,
            track.stopping
                ? ArtemisPlaybackStatus.cancelled
                : ArtemisPlaybackStatus.ended,
          );
        },
      );
      if (!_current(track)) {
        await handle.dispose();
        return;
      }
      // Commands may arrive while the asset or player is opening.
      track.handle = handle;
      handle.gain = track.gain;
      await handle.setPan(track.pan);
      await handle.setHostSuspended(_suspended);
      await handle.setEffectiveVolume(play.fadeMs > 0 ? 0 : _volume(track));
      if (!_current(track) || track.stopping) return;
      await handle.play();
      if (!_current(track) || track.stopping) return;
      track.ready = true;
      if (!_suspended) _started(track);
      if (play.fadeMs > 0) _run(handle.fadeTo(_volume(track), play.fadeMs));
      await retirePrevious(play.crossfade ? play.fadeMs : 0);
    } catch (_) {
      _finish(track, ArtemisPlaybackStatus.failed);
      rethrow;
    } finally {
      await retirePrevious(0);
    }
  }

  double _volume(_V2AudioPlayback track) =>
      _effectiveVolume(track.play.channel.name, track.gain);

  void _stop(_V2AudioPlayback track, int fadeMs) {
    if (track.stopping && fadeMs > 0) return;
    track.stopping = true;
    final handle = track.handle;
    if (!track.ready || handle == null || fadeMs <= 0) {
      _finish(track, ArtemisPlaybackStatus.cancelled);
    } else {
      _run(
        handle.fadeTo(0, fadeMs).whenComplete(() {
          _finish(track, ArtemisPlaybackStatus.cancelled);
        }),
      );
    }
  }

  bool _current(_V2AudioPlayback track) =>
      identical(_playbacks[track.play.id], track);

  void _started(_V2AudioPlayback track) {
    if (!track.started) {
      track.started = true;
      track.feedback(track.play.id, ArtemisPlaybackStatus.started);
    }
  }

  void _finish(_V2AudioPlayback track, ArtemisPlaybackStatus status) {
    if (!_current(track)) return;
    _playbacks.remove(track.play.id);
    final handle = track.handle;
    if (handle != null) _run(handle.dispose());
    track.feedback(track.play.id, status);
  }

  @override
  Future<void> setSuspended(bool suspended) async {
    await super.setSuspended(suspended);
    for (final session
        in _videos.values.map((track) => track.session).toSet()) {
      await session.suspendVideos(suspended);
    }
    for (final track in _playbacks.values.toList()) {
      try {
        await track.handle?.setHostSuspended(suspended);
        if (!suspended && track.ready && !track.stopping && _current(track)) {
          _started(track);
        }
      } catch (_) {
        _finish(track, ArtemisPlaybackStatus.failed);
      }
    }
    for (final handle in _fading.toList()) {
      await handle.setHostSuspended(suspended);
    }
  }

  void reset() {
    _resetAudio();
    _stopVideos();
  }

  Future<void> resetProject() async {
    reset();
    await _drainWork();
    _assetCache.clear();
    _videoAssets.clear();
  }

  void _resetAudio() {
    final handles = {
      ..._fading,
      ..._playbacks.values.map((track) => track.handle).nonNulls,
    };
    _playbacks.clear();
    _fading.clear();
    for (final handle in handles) {
      _run(handle.dispose());
    }
  }

  void _run(Future<void> operation) {
    final work = operation.catchError((Object error) {
      Log.warn('[ArtemisV2] media: $error');
    });
    _work.add(work);
    unawaited(work.whenComplete(() => _work.remove(work)));
  }

  Future<void> _drainWork() async {
    while (_work.isNotEmpty) {
      await Future.wait(_work.toList());
    }
  }

  @override
  Future<void> dispose() async {
    reset();
    await _drainWork();
    await super.dispose();
  }
}

final class _V2VideoPlayback {
  const _V2VideoPlayback(this.session, this.play, this.feedback);

  final ArtemisFlutterSession session;
  final ArtemisVideoPlay play;
  final _PlaybackFeedback feedback;
}

final class _V2AudioPlayback {
  _V2AudioPlayback(this.play, this.feedback)
    : gain = _gain(play.gain),
      pan = _pan(play.pan);

  final ArtemisAudioPlay play;
  final _PlaybackFeedback feedback;
  _AudioHandle? handle;
  double gain, pan;
  bool ready = false, started = false, stopping = false;
}
