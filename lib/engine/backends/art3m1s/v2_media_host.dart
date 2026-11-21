part of 'media_bridge.dart';

typedef _PlaybackFeedback =
    void Function(String id, ArtemisPlaybackStatus status);

typedef ArtemisVideoAssetWriter =
    Future<File?> Function(
      String key,
      File destination,
      bool Function() isCurrent,
    );

final class ArtemisV2MediaHost extends MediaBridge {
  ArtemisV2MediaHost({this.writeVideoAsset})
    : super(onVideoFinished: (_) {}, onSoundFinished: (_) {});

  final ArtemisVideoAssetWriter? writeVideoAsset;
  int _videoAssetGeneration = 0;
  int _suspensionRevision = 0;
  final _playbacks = <String, _V2AudioPlayback>{};
  final _videos = <String, _V2VideoPlayback>{};
  final _pendingAudioAssets = <String, Future<File?>>{};
  final _videoAssets = <String, Future<File>>{};
  final _fading = <_AudioHandle, Object>{};
  final _work = <Future<void>>{};
  final _audioReleases = <Future<void>>{};
  Future<void>? _audioReset;
  int _audioGeneration = 0;
  _V2VideoPlayback? _fullscreen;
  bool _muted = false;
  double _scriptMasterVolume = 1;

  @override
  void handleEngineAudioCommand(EngineAudioCommand command) {
    if (command.kind != EngineAudioCommandKind.masterVolume) {
      super.handleEngineAudioCommand(command);
      return;
    }
    if (_disposed) return;
    _channelVolumes['master'] = command.volume.clamp(0, 1);
    _updateVolume();
  }

  void setAvoidMuted(bool muted) {
    if (_muted == muted) return;
    _muted = muted;
    _updateVolume();
  }

  double _volumeScale(String channel) =>
      _muted ? 0 : _effectiveVolume(channel, _scriptMasterVolume);

  void _updateVolume([String? channel]) {
    final handles = {
      ..._fading.keys,
      ..._playbacks.values.map((track) => track.handle).nonNulls,
    };
    for (final handle in handles) {
      if (channel == null || channel == handle.channel) {
        _run(handle.setVolumeScale(_volumeScale(handle.channel)));
      }
    }
    if (channel != null && channel != 'video') return;
    for (final session
        in _videos.values.map((track) => track.session).toSet()) {
      _run(session.setVideoVolume(_volumeScale('video')));
    }
  }

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
      case ArtemisChannelVolume(:final channel, :final level):
        final scale = level.clamp(0, 1000) / 1000;
        if (channel == ArtemisVolumeChannel.master) {
          _scriptMasterVolume = scale;
          _updateVolume();
        } else {
          _channelVolumes[channel.name] = scale;
          _updateVolume(channel.name);
        }
      case ArtemisAudioUpdate(
        :final action,
        :final ids,
        :final timeMs,
        :final value,
      ):
        for (final id in ids) {
          final track = _playbacks[id];
          if (track == null ||
              (track.stopping && action != ArtemisAudioAction.stop)) {
            continue;
          }
          switch (action) {
            case ArtemisAudioAction.stop:
              _stop(track, timeMs);
            case ArtemisAudioAction.gain:
              track.gain = _gain(value, fallback: track.gain);
              final handle = track.handle;
              if (handle != null) {
                handle.gain = track.gain;
                _runAudio(track, handle.fadeTo(track.gain, timeMs));
              }
            case ArtemisAudioAction.pan:
              track.pan = _pan(value);
              final handle = track.handle;
              if (handle != null) {
                _runAudio(track, handle.panTo(track.pan, timeMs));
              }
          }
        }
      case ArtemisMediaStopAll(:final audio, :final fadeMs):
        if (audio) {
          for (final handle in _fading.keys.toList()) {
            _run(_fadeOutRetired(handle, fadeMs));
          }
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
    final pending = _videoAssets.putIfAbsent(
      play.key,
      () => _materializeVideo(play.key),
    );
    try {
      final asset = await pending.onError<Object>((error, stack) {
        if (identical(_videoAssets[play.key], pending)) {
          _videoAssets.remove(play.key);
        }
        Error.throwWithStackTrace(error, stack);
      });
      if (!_videoIsActive(track)) return;
      await track.session.suspendVideos(_suspended);
      if (!_videoIsActive(track)) return;
      await track.session.openVideo(
        epoch: epoch,
        play: play,
        path: asset.path,
        volume: _volumeScale('video'),
      );
      if (!identical(_videos[play.id], track) && !track.closing) {
        await track.session.closeVideo(play.id);
      }
    } catch (_) {
      if (!_videoIsActive(track)) return;
      await _closeVideoThenReport(track, ArtemisPlaybackStatus.failed);
      rethrow;
    }
  }

  Future<File> _materializeVideo(String key) async {
    final generation = _videoAssetGeneration;
    bool isCurrent() => generation == _videoAssetGeneration;
    final cache = await _projectCacheDir.create(recursive: true);
    final directory = await cache.createTemp('video-');
    try {
      if (!isCurrent()) throw StateError('Video preparation cancelled');
      final file = File('${directory.path}/clip${_extension(key)}');
      final writer = writeVideoAsset;
      if (writer != null) {
        if (await writer(key, file, isCurrent) == null) {
          throw StateError('Could not copy video asset');
        }
      } else {
        final bytes = _assetReader?.call(key);
        if (bytes == null) throw StateError('Missing video asset');
        await file.writeAsBytes(bytes);
      }
      if (!isCurrent()) throw StateError('Video preparation cancelled');
      return file;
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  bool _videoIsActive(_V2VideoPlayback track) =>
      !track.closing && identical(_videos[track.play.id], track);

  Future<void> pollVideo(ArtemisFlutterSession session) async {
    final polling = {
      for (final track in _videos.values)
        if (identical(track.session, session) && !track.closing)
          track.play.id: track,
    };
    if (polling.isEmpty) return;
    final events = await session.pollVideos().onError<Exception>((error, _) {
      Log.warn('[ArtemisV2] video poll: $error');
      for (final track in polling.values) {
        _run(_closeVideoThenReport(track, ArtemisPlaybackStatus.failed));
      }
      return const [];
    });
    for (final event in events) {
      final track = polling[event.id];
      if (track == null || !_videoIsActive(track)) continue;
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
          onMenuSkip: track.play.skip == 2
              ? () => unawaited(_skip(track))
              : null,
        );
      }
      track.feedback(track.play.id, event.status);
    }
  }

  @override
  Future<void> skipVideo() async {
    final track = _fullscreen;
    if (track != null && track.play.skip == 1) {
      await _skip(track);
    }
  }

  Future<void> _skip(_V2VideoPlayback track) async {
    if (!identical(_fullscreen, track)) return;
    await _run(_closeVideoThenReport(track, ArtemisPlaybackStatus.cancelled));
  }

  Future<void> _closeVideoThenReport(
    _V2VideoPlayback track,
    ArtemisPlaybackStatus status,
  ) async {
    if (!_videoIsActive(track)) return;
    track.closing = true;
    var reportedStatus = ArtemisPlaybackStatus.failed;
    try {
      await track.session.closeVideo(track.play.id);
      reportedStatus = status;
    } finally {
      _closeVideo(track, status: reportedStatus, notifyRunner: false);
    }
  }

  void _closeVideo(
    _V2VideoPlayback track, {
    ArtemisPlaybackStatus? status,
    bool notifyRunner = true,
  }) {
    if (!identical(_videos[track.play.id], track)) return;
    _videos.remove(track.play.id);
    if (identical(_fullscreen, track)) {
      _fullscreen = null;
      videoPlayback.value = null;
    }
    if (notifyRunner && !track.closing) {
      _run(track.session.closeVideo(track.play.id));
    }
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
    final inherited = previous == null ? null : _takePrevious(previous);
    if (inherited != null) {
      track.previous = inherited;
      if (previousHandle != null) _releaseAudio(previousHandle);
    } else if (previousHandle != null) {
      final ticket = _fading[previousHandle] = Object();
      track.previous = (handle: previousHandle, ticket: ticket);
    }
    _playbacks[play.id] = track;
    _run(_open(track));
  }

  Future<File?> _audioAsset(String key) =>
      _pendingAudioAssets.putIfAbsent(key, () async {
        try {
          return await _resolveAsset({'file': key}, projectOnly: true);
        } finally {
          _pendingAudioAssets.remove(key);
        }
      });

  ({_AudioHandle handle, Object ticket})? _takePrevious(
    _V2AudioPlayback track,
  ) {
    final previous = track.previous;
    track.previous = null;
    if (previous == null ||
        !identical(_fading[previous.handle], previous.ticket)) {
      return null;
    }
    return previous;
  }

  Future<bool>? _retirePrevious(_V2AudioPlayback track, int fadeMs) {
    final previous = _takePrevious(track);
    return previous == null ? null : _fadeOutRetired(previous.handle, fadeMs);
  }

  Future<void> _open(_V2AudioPlayback track) async {
    final play = track.play;
    try {
      if (!play.crossfade) await _retirePrevious(track, 0);
      final file = await _audioAsset(play.key);
      if (!_current(track)) return;
      if (file == null) {
        _finish(track, ArtemisPlaybackStatus.failed);
        return;
      }
      final loopKey = play.loopKey;
      final loopFile = loopKey == null ? null : await _audioAsset(loopKey);
      if (!_current(track)) return;

      var preparationFailed = false;
      final handle = await _AudioHandle.create(
        id: play.scriptId,
        file: file,
        loopFile: loopFile,
        channel: play.channel.name,
        gain: track.gain,
        pan: track.pan,
        loop: play.loop,
        suspendWithSession: true,
        onFailed: () {
          if (track.handle == null) {
            preparationFailed = true;
          } else {
            _finish(track, ArtemisPlaybackStatus.failed);
          }
        },
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
      if (preparationFailed) {
        _finish(track, ArtemisPlaybackStatus.failed);
        return;
      }
      handle.gain = track.gain;
      await handle.setVolumeScale(_volumeScale(handle.channel));
      await handle.setPan(track.pan);
      await handle.setHostSuspended(_suspended);
      await handle.setEffectiveVolume(play.fadeMs > 0 ? 0 : track.gain);
      await _audioReset;
      if (!_current(track) || track.stopping) return;
      await handle.play();
      if (!_current(track) || track.stopping) return;
      track.ready = true;
      _reportStartedIfReady(track);
      if (play.fadeMs > 0) {
        _runAudio(track, handle.fadeTo(track.gain, play.fadeMs));
      }
      await _retirePrevious(track, play.fadeMs);
    } catch (_) {
      _finish(track, ArtemisPlaybackStatus.failed);
      rethrow;
    } finally {
      await _retirePrevious(track, 0);
    }
  }

  Future<bool> _fadeOutRetired(_AudioHandle handle, int fadeMs) async {
    // Replacing a fade settles its old future before the new fade finishes.
    final ticket = _fading[handle] = Object();
    var released = true;
    try {
      if (fadeMs > 0) await handle.fadeTo(0, fadeMs);
    } finally {
      if (identical(_fading[handle], ticket)) {
        _fading.remove(handle);
        released = await _releaseAudio(handle);
      }
    }
    return released;
  }

  void _stop(_V2AudioPlayback track, int fadeMs) {
    if (track.stopping && fadeMs > 0) return;
    track.stopping = true;
    final handle = track.handle;
    if (!track.ready || handle == null || fadeMs <= 0) {
      _finish(track, ArtemisPlaybackStatus.cancelled);
    } else {
      _runAudio(
        track,
        handle.fadeTo(0, fadeMs),
        onSuccess: ArtemisPlaybackStatus.cancelled,
      );
    }
  }

  bool _current(_V2AudioPlayback track) =>
      identical(_playbacks[track.play.id], track);

  void _reportStartedIfReady(_V2AudioPlayback track) {
    if (!_suspended &&
        track.ready &&
        !track.stopping &&
        _current(track) &&
        track.handle?.canReportStarted == true) {
      _started(track);
    }
  }

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
    final retirement = _retirePrevious(track, 0);
    if (handle == null && retirement == null) {
      track.feedback(track.play.id, status);
      return;
    }
    final generation = _audioGeneration;
    void report(bool released) {
      if (generation == _audioGeneration) {
        track.feedback(
          track.play.id,
          released ? status : ArtemisPlaybackStatus.failed,
        );
      }
    }

    _run(
      Future.wait([
        if (handle != null) _releaseAudio(handle),
        ?retirement,
      ]).then<void>(
        (released) => report(released.every((success) => success)),
        onError: (Object error, StackTrace stack) {
          report(false);
          Error.throwWithStackTrace(error, stack);
        },
      ),
    );
  }

  void _runAudio(
    _V2AudioPlayback track,
    Future<void> operation, {
    ArtemisPlaybackStatus? onSuccess,
  }) {
    _run(
      operation.then(
        (_) {
          if (onSuccess != null) _finish(track, onSuccess);
        },
        onError: (Object error, StackTrace stack) {
          _finish(track, ArtemisPlaybackStatus.failed);
          Error.throwWithStackTrace(error, stack);
        },
      ),
    );
  }

  @override
  Future<void> setSuspended(bool suspended) async {
    final revision = ++_suspensionRevision;
    final videos = <ArtemisFlutterSession, List<_V2VideoPlayback>>{};
    for (final track in _videos.values) {
      if (!track.closing) (videos[track.session] ??= []).add(track);
    }

    Future<void> suspendTrack(_V2AudioPlayback track) async {
      try {
        await track.handle?.setHostSuspended(suspended);
        if (!suspended) _reportStartedIfReady(track);
      } catch (_) {
        _finish(track, ArtemisPlaybackStatus.failed);
      }
    }

    Future<void> suspendRetiredAudio(_AudioHandle handle) async {
      try {
        await handle.setHostSuspended(suspended);
      } catch (error) {
        Log.warn('[ArtemisV2] retired audio suspension: $error');
        if (_fading.remove(handle) != null) await _releaseAudio(handle);
      }
    }

    Future<void> suspendVideos(
      ArtemisFlutterSession session,
      List<_V2VideoPlayback> tracks,
    ) async {
      try {
        await session.suspendVideos(suspended);
      } catch (error) {
        if (revision != _suspensionRevision) return;
        Log.warn('[ArtemisV2] video suspension: $error');
        await Future.wait([
          for (final track in tracks)
            _run(_closeVideoThenReport(track, ArtemisPlaybackStatus.failed)),
        ]);
      }
    }

    await Future.wait([
      _run(super.setSuspended(suspended)),
      for (final track in _playbacks.values) suspendTrack(track),
      for (final handle in _fading.keys) suspendRetiredAudio(handle),
      for (final entry in videos.entries) suspendVideos(entry.key, entry.value),
    ]);
  }

  void reset() {
    _resetAudio();
    _stopVideos();
    _scriptMasterVolume = 1;
    for (final channel in ArtemisVolumeChannel.values) {
      if (channel != ArtemisVolumeChannel.master) {
        _channelVolumes.remove(channel.name);
      }
    }
  }

  Future<void> resetProject() async {
    _videoAssetGeneration++;
    reset();
    _muted = false;
    await _drainWork();
    _assetCache.clear();
    _videoAssets.clear();
    final directory = _projectCacheDir;
    try {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    } on FileSystemException catch (error) {
      Log.warn('[ArtemisV2] could not clear the project media cache: $error');
    }
  }

  void _resetAudio() {
    _audioGeneration++;
    final handles = {
      ..._fading.keys,
      ..._playbacks.values.map((track) => track.handle).nonNulls,
    };
    _playbacks.clear();
    _fading.clear();
    for (final handle in handles) {
      _releaseAudio(handle);
    }
    if (_audioReleases.isEmpty) return;
    final reset = _audioReset = Future.wait(_audioReleases).then<void>((_) {});
    unawaited(
      reset.whenComplete(() {
        if (identical(_audioReset, reset)) _audioReset = null;
      }),
    );
  }

  Future<bool> _releaseAudio(_AudioHandle handle) {
    var released = false;
    final work = _run(
      handle.dispose().then<void>((_) {
        released = true;
      }),
    );
    _audioReleases.add(work);
    unawaited(work.whenComplete(() => _audioReleases.remove(work)));
    return work.then((_) => released);
  }

  Future<void> _run(Future<void> operation) {
    final work = operation.catchError((Object error) {
      Log.warn('[ArtemisV2] media: $error');
    });
    _work.add(work);
    unawaited(work.whenComplete(() => _work.remove(work)));
    return work;
  }

  Future<void> _drainWork() async {
    while (_work.isNotEmpty) {
      await Future.wait(_work.toList());
    }
  }

  @override
  Future<void> dispose() async {
    _videoAssetGeneration++;
    reset();
    await _drainWork();
    await super.dispose();
  }
}

final class _V2VideoPlayback {
  _V2VideoPlayback(this.session, this.play, this.feedback);

  final ArtemisFlutterSession session;
  final ArtemisVideoPlay play;
  final _PlaybackFeedback feedback;
  bool closing = false;
}

final class _V2AudioPlayback {
  _V2AudioPlayback(this.play, this.feedback)
    : gain = _gain(play.gain),
      pan = _pan(play.pan);

  final ArtemisAudioPlay play;
  final _PlaybackFeedback feedback;
  _AudioHandle? handle;
  ({_AudioHandle handle, Object ticket})? previous;
  double gain, pan;
  bool ready = false, started = false, stopping = false;
}
