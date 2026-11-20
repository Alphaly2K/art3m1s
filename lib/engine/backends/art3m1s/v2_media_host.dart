part of 'media_bridge.dart';

typedef _PlaybackFeedback =
    void Function(String id, ArtemisPlaybackStatus status);

final class ArtemisV2MediaHost extends MediaBridge {
  ArtemisV2MediaHost()
    : super(onVideoFinished: (_) {}, onSoundFinished: (_) {});

  final _playbacks = <String, _V2AudioPlayback>{};
  final _videos = <String, _V2VideoPlayback>{};
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
          for (final track in _playbacks.values.toList()) {
            _stop(track, fadeMs);
          }
          for (final handle in _fading.keys.toList()) {
            _run(_fadeOutRetired(handle, fadeMs));
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
      final directory = await _projectCacheDir.create(recursive: true);
      final file = File(
        '${directory.path}/video_${_stableId(play.key)}${_extension(play.key)}',
      );
      return file.writeAsBytes(bytes);
    });
    try {
      final asset = await pending;
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
      if (identical(_videoAssets[play.key], pending)) {
        _videoAssets.remove(play.key);
      }
      await _closeVideoThenReport(track, ArtemisPlaybackStatus.failed);
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
    if (previousHandle != null) {
      _fading[previousHandle] = Object();
    }
    _playbacks[play.id] = track;
    _run(_open(track, previousHandle));
  }

  Future<void> _open(_V2AudioPlayback track, _AudioHandle? previous) async {
    final play = track.play;
    final previousTicket = _fading[previous];
    Future<void> retirePrevious(int fadeMs) async {
      final handle = previous;
      previous = null;
      if (handle == null || !identical(_fading[handle], previousTicket)) return;
      await _fadeOutRetired(handle, fadeMs);
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
        suspendWithSession: true,
        onFailed: () => _finish(track, ArtemisPlaybackStatus.failed),
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
      await handle.setVolumeScale(_volumeScale(handle.channel));
      await handle.setPan(track.pan);
      await handle.setHostSuspended(_suspended);
      await handle.setEffectiveVolume(play.fadeMs > 0 ? 0 : track.gain);
      await _audioReset;
      if (!_current(track) || track.stopping) return;
      await handle.play();
      if (!_current(track) || track.stopping) return;
      track.ready = true;
      if (!_suspended) _started(track);
      if (play.fadeMs > 0) {
        _runAudio(track, handle.fadeTo(track.gain, play.fadeMs));
      }
      await retirePrevious(play.crossfade ? play.fadeMs : 0);
    } catch (_) {
      _finish(track, ArtemisPlaybackStatus.failed);
      rethrow;
    } finally {
      await retirePrevious(0);
    }
  }

  Future<void> _fadeOutRetired(_AudioHandle handle, int fadeMs) async {
    // Replacing a fade settles its old future before the new fade finishes.
    final ticket = _fading[handle] = Object();
    try {
      if (fadeMs > 0) await handle.fadeTo(0, fadeMs);
    } finally {
      if (identical(_fading[handle], ticket)) {
        _fading.remove(handle);
        await _releaseAudio(handle);
      }
    }
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
    if (handle == null) {
      track.feedback(track.play.id, status);
      return;
    }
    final generation = _audioGeneration;
    _run(
      _releaseAudio(handle).then((released) {
        if (generation == _audioGeneration) {
          track.feedback(
            track.play.id,
            released ? status : ArtemisPlaybackStatus.failed,
          );
        }
      }),
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
    Future<void> suspendTrack(_V2AudioPlayback track) async {
      try {
        await track.handle?.setHostSuspended(suspended);
        if (!_suspended && track.ready && !track.stopping && _current(track)) {
          _started(track);
        }
      } catch (_) {
        _finish(track, ArtemisPlaybackStatus.failed);
      }
    }

    await Future.wait([
      super.setSuspended(suspended),
      for (final track in _playbacks.values) suspendTrack(track),
      for (final handle in _fading.keys) handle.setHostSuspended(suspended),
      for (final session
          in _videos.values.map((track) => track.session).toSet())
        session.suspendVideos(suspended),
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
  double gain, pan;
  bool ready = false, started = false, stopping = false;
}
