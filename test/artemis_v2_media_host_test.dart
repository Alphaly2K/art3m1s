import 'dart:async';
import 'dart:io';

import 'package:art3m1s/engine/backends/art3m1s/media_bridge.dart';
import 'package:art3m1s/engine/backends/art3m1s/v2_sdk/artemis_flutter_session.dart';
import 'package:art3m1s/engine/engine_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('audio stops retire replaced tracks and order save restore', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final resumed = <String>[];
    final paused = <String>[];
    final disposed = <String>[];
    final volumes = <String, List<double>>{};
    final balances = <String, List<double>>{};
    final assets = <File>[];
    final changes = StreamController<void>.broadcast();
    Completer<void>? resumeGate;
    Completer<void>? stopGate;
    final sourceFailed = Completer<void>();
    final allowFailedSource = Completer<void>();
    var failOpeningSource = false;
    Completer<String>? sourceOpening;
    final allowSource = Completer<void>();
    final stopping = Completer<void>();
    var failNextResume = false;
    String? fadePlayer;
    final volumeSent = Completer<void>();
    final allowVolume = Completer<void>();
    final fadeStopping = Completer<void>();
    final allowFadeStop = Completer<void>();
    String? rejectedPausePlayer;
    String? rejectedVolumePlayer;
    String? rejectedPanPlayer;
    String? rejectedReleasePlayer;
    String? replacingPlayer;
    final replacementStopping = Completer<void>();
    final allowReplacementStop = Completer<void>();

    Future<void> waitFor(bool Function() ready) async {
      if (!ready()) {
        await changes.stream
            .firstWhere((_) => ready())
            .timeout(const Duration(seconds: 2));
      }
    }

    Future<void> audioEvent(String id, Map<String, Object?> event) async {
      await messenger.handlePlatformMessage(
        'xyz.luan/audioplayers/events/$id',
        const StandardMethodCodec().encodeSuccessEnvelope(event),
        null,
      );
    }

    Future<void> audioFailure(String id) async {
      await messenger.handlePlatformMessage(
        'xyz.luan/audioplayers/events/$id',
        const StandardMethodCodec().encodeErrorEnvelope(
          code: 'audio_output_failed',
        ),
        null,
      );
    }

    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global/events'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        final id = call.arguments['playerId'] as String;
        switch (call.method) {
          case 'create':
            messenger.setMockMethodCallHandler(
              MethodChannel('xyz.luan/audioplayers/events/$id'),
              (_) async => null,
            );
          case 'setSourceUrl':
            assets.add(File(call.arguments['url'] as String));
            await audioEvent(id, {'event': 'audio.onPrepared', 'value': true});
            if (failOpeningSource) {
              failOpeningSource = false;
              await audioFailure(id);
              sourceFailed.complete();
              await allowFailedSource.future;
            }
            if (sourceOpening case final opening?) {
              sourceOpening = null;
              opening.complete(id);
              await allowSource.future;
            }
          case 'resume':
            resumed.add(id);
            changes.add(null);
            if (failNextResume) {
              failNextResume = false;
              throw PlatformException(code: 'audio_output_failed');
            }
            await resumeGate?.future;
          case 'pause':
            paused.add(id);
            if (id == rejectedPausePlayer) {
              throw PlatformException(code: 'pause_failed');
            }
          case 'stop' when id == replacingPlayer:
            replacementStopping.complete();
            await allowReplacementStop.future;
          case 'stop' when id == fadePlayer:
            if (!fadeStopping.isCompleted) fadeStopping.complete();
            await allowFadeStop.future;
          case 'stop' when stopGate != null && !stopping.isCompleted:
            stopping.complete();
            await stopGate.future;
          case 'release' when id == rejectedReleasePlayer:
            throw PlatformException(code: 'release_failed');
          case 'dispose':
            disposed.add(id);
            changes.add(null);
          case 'setVolume' when id == rejectedVolumePlayer:
            throw PlatformException(code: 'volume_failed');
          case 'setVolume':
            final volume = call.arguments['volume'] as double;
            (volumes[id] ??= []).add(volume);
            if (id == fadePlayer && volume == 0) {
              if (!volumeSent.isCompleted) volumeSent.complete();
              await allowVolume.future;
            }
            changes.add(null);
          case 'setBalance':
            if (id == rejectedPanPlayer) {
              throw PlatformException(code: 'pan_failed');
            }
            (balances[id] ??= []).add(call.arguments['balance'] as double);
            changes.add(null);
            changes.add(null);
        }
        return null;
      },
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('moe.alphaly.art3m1s/artemis_v2'),
      (call) async => call.method == 'open'
          ? {
              'session': '1',
              'epoch': '1',
              'width': 4,
              'height': 4,
              'phase': 0,
              'waitFlags': 0,
              'exitRequested': false,
            }
          : null,
    );

    final opened = await ArtemisFlutterSession.open(
      ini: Uint8List(0),
      platform: 'windows',
      hostCaps: 4,
    );
    final reads = <String, int>{};
    final host = ArtemisV2MediaHost()
      ..configureAssetReader((key) {
        reads.update(key, (count) => count + 1, ifAbsent: () => 1);
        return Uint8List.fromList('RIFF'.codeUnits);
      });
    final feedback = <(String, ArtemisPlaybackStatus)>[];
    void send(Map<String, Object?> data) {
      host.handle(
        opened.session,
        opened.state.epoch,
        ArtemisMediaCommand.decode(5, 1, data)!,
        (id, status) {
          feedback.add((id, status));
          changes.add(null);
        },
      );
    }

    Map<String, Object?> playCommand(
      String id, {
      String? replaces,
      String? loopKey,
      int? gain,
      int? pan,
      String channel = 'bgm',
    }) => {
      'op': 'play',
      'playback_id': id,
      'replaces': replaces,
      'channel': channel,
      'key': 'track_$id.wav',
      'loop': true,
      'loop_key': loopKey,
      'gain': gain,
      'pan': pan,
      'fade_ms': replaces == null ? '0' : '4000',
      'skippable': false,
      'crossfade': replaces != null,
    };

    void play(String id, {String? replaces, String? loopKey, int? gain}) =>
        send(playCommand(id, replaces: replaces, loopKey: loopKey, gain: gain));

    try {
      send(playCommand('1', loopKey: 'loop.wav', gain: 1, pan: -1));
      await waitFor(
        () => feedback.contains(('1', ArtemisPlaybackStatus.started)),
      );
      final intro = resumed.single;
      expect(volumes[intro]!.last, 0.001);
      expect(balances[intro]!.last, -0.001);
      await host.setSuspended(true);
      expect(paused, [intro]);
      await audioEvent(intro, {'event': 'audio.onComplete'});
      await Future<void>.delayed(Duration.zero);
      expect(resumed, [intro]);
      await host.setSuspended(false);
      await waitFor(() => resumed.length >= 2);
      expect(resumed, hasLength(2));
      final loop = resumed.last;
      expect(loop, isNot(intro));
      expect(volumes[loop]!.last, 0.001);
      expect(balances[loop]!.last, -0.001);
      await audioEvent(loop, {'event': 'audio.onComplete'});
      await audioEvent(intro, {'event': 'audio.onComplete'});
      await audioFailure(intro);
      await Future<void>.delayed(Duration.zero);
      expect(disposed, isEmpty);
      expect(feedback, [('1', ArtemisPlaybackStatus.started)]);

      play('2', replaces: '1');
      await waitFor(
        () => feedback.contains(('2', ArtemisPlaybackStatus.started)),
      );
      expect(resumed, hasLength(3));
      final next = resumed.last;

      await waitFor(() => volumes[next]!.last > 0);
      await host.setSuspended(true);
      final oldLevel = volumes[loop]!.last;
      final nextLevel = volumes[next]!.last;
      expect(oldLevel, greaterThan(0));
      send({'op': 'volume', 'channel': 'bgm', 'level': 500});
      await waitFor(
        () =>
            volumes[loop]!.last == oldLevel * 0.5 &&
            volumes[next]!.last == nextLevel * 0.5,
      );
      send({'op': 'volume', 'channel': 'master', 'level': 250});
      await waitFor(
        () =>
            volumes[loop]!.last == oldLevel * 0.125 &&
            volumes[next]!.last == nextLevel * 0.125,
      );
      await host.setSuspended(false);

      for (final time in ['4000', '132']) {
        send({
          'op': 'stop',
          'playback_ids': ['2'],
          'time_ms': time,
        });
      }
      await waitFor(
        () => feedback.contains(('2', ArtemisPlaybackStatus.cancelled)),
      );
      expect(disposed, [next]);
      expect(volumes[next]!.last, 0);

      await host.setSuspended(true);
      expect(paused, contains(loop));
      final heldVolume = volumes[loop]!.length;
      send({'op': 'stop_all', 'fade_ms': '132'});
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(disposed, [next]);
      expect(volumes[loop]!.length, heldVolume);
      await host.setSuspended(false);
      await waitFor(() => disposed.length >= 3);
      expect(disposed, unorderedEquals([next, intro, loop]));

      final opening = resumeGate = Completer<void>();
      final beforeOpening = resumed.length;
      play('3');
      await waitFor(() => resumed.length > beforeOpening);
      final active = resumed.last;
      final suspending = host.setSuspended(true);
      resumeGate = null;
      opening.complete();
      await suspending;
      expect(paused, contains(active));
      expect(feedback, isNot(contains(('3', ArtemisPlaybackStatus.started))));
      final resume = resumeGate = Completer<void>();
      final repeatedSuspend = host.setSuspended(true);
      final resuming = host.setSuspended(false);
      await waitFor(() => resumed.length >= beforeOpening + 2);
      await repeatedSuspend;
      final repeatedResume = host.setSuspended(false);
      await Future<void>.delayed(Duration.zero);
      expect(feedback, isNot(contains(('3', ArtemisPlaybackStatus.started))));
      final pausingAgain = host.setSuspended(true);
      final resumingAgain = host.setSuspended(false);
      final lastResume = resumeGate = Completer<void>();
      resume.complete();
      await Future.wait([resuming, repeatedResume, pausingAgain]);
      await waitFor(() => resumed.length >= beforeOpening + 3);
      expect(feedback, isNot(contains(('3', ArtemisPlaybackStatus.started))));
      resumeGate = null;
      lastResume.complete();
      await resumingAgain;
      expect(feedback.where((event) => event.$1 == '3'), [
        ('3', ArtemisPlaybackStatus.started),
      ]);
      expect(resumed.skip(beforeOpening), [active, active, active]);
      send({
        'op': 'pan',
        'playback_ids': ['3'],
        'value': 1,
        'time_ms': '132',
      });
      await waitFor(() => balances[active]!.last > 0);
      await host.setSuspended(true);
      final heldPan = balances[active]!.last;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(balances[active]!.last, heldPan);
      send({'op': 'stop_all', 'fade_ms': '4000'});
      host.handleEngineAudioCommand(
        EngineAudioCommand(
          kind: EngineAudioCommandKind.masterVolume,
          streamId: 0,
          id: '',
          channel: 'master',
          payload: Uint8List(0),
          volume: 0.5,
        ),
      );
      await host.resetProject().timeout(const Duration(seconds: 2));
      expect(assets.where((file) => file.existsSync()), isEmpty);
      expect(disposed, unorderedEquals([next, intro, loop, active]));
      expect(feedback, [
        ('1', ArtemisPlaybackStatus.started),
        ('2', ArtemisPlaybackStatus.started),
        ('2', ArtemisPlaybackStatus.cancelled),
        ('3', ArtemisPlaybackStatus.started),
      ]);

      await host.setSuspended(false);
      play('4', gain: 800);
      await waitFor(
        () => feedback.contains(('4', ArtemisPlaybackStatus.started)),
      );
      final fresh = resumed.last;
      expect(volumes[fresh]!.last, closeTo(0.4, 0.0001));
      send({
        'op': 'gain',
        'playback_ids': ['4'],
        'value': 1,
        'time_ms': '0',
      });
      await waitFor(() => volumes[fresh]!.last == 0.0005);
      send({
        'op': 'pan',
        'playback_ids': ['4'],
        'value': 1,
        'time_ms': '0',
      });
      await waitFor(() => balances[fresh]!.last == 0.001);
      send({
        'op': 'gain',
        'playback_ids': ['4'],
        'value': 800,
        'time_ms': '0',
      });
      host.setAvoidMuted(true);
      await waitFor(() => volumes[fresh]!.last == 0);
      send({'op': 'volume', 'channel': 'bgm', 'level': 500});
      send({'op': 'volume', 'channel': 'master', 'level': 250});
      host.setAvoidMuted(false);
      await waitFor(() => (volumes[fresh]!.last - 0.05).abs() < 0.0001);

      final beforeRestore = resumed.length;
      final previousPlayers = volumes.keys.toSet();
      stopGate = Completer<void>();
      send({
        'op': 'restore',
        'plays': [playCommand('5', gain: 1, pan: 1)],
        'stop_video': false,
      });
      send(playCommand('6', channel: 'se'));
      await stopping.future.timeout(const Duration(seconds: 2));
      await waitFor(
        () =>
            volumes.entries
                .where(
                  (entry) =>
                      !previousPlayers.contains(entry.key) &&
                      entry.value.length >= 2,
                )
                .length ==
            2,
      );
      await Future<void>.delayed(Duration.zero);
      expect(resumed.length, beforeRestore);
      stopGate.complete();
      await waitFor(
        () =>
            feedback.contains(('5', ArtemisPlaybackStatus.started)) &&
            feedback.contains(('6', ArtemisPlaybackStatus.started)),
      );
      expect(resumed.length, beforeRestore + 2);
      final restored = resumed
          .skip(beforeRestore)
          .singleWhere((id) => balances[id]!.last == 0.001);
      expect(volumes[restored]!.last, 0.0000625);
      expect(disposed, contains(fresh));

      play('7');
      await waitFor(
        () => feedback.contains(('7', ArtemisPlaybackStatus.started)),
      );
      final failedSound = resumed.last;
      await audioFailure(failedSound);
      await waitFor(
        () => feedback.contains(('7', ArtemisPlaybackStatus.failed)),
      );
      expect(disposed, contains(failedSound));
      expect(feedback.where((entry) => entry.$1 == '7'), [
        ('7', ArtemisPlaybackStatus.started),
        ('7', ArtemisPlaybackStatus.failed),
      ]);

      play('8', loopKey: 'loop.wav');
      await waitFor(
        () => feedback.contains(('8', ArtemisPlaybackStatus.started)),
      );
      final failedIntro = resumed.last;
      failNextResume = true;
      await audioEvent(failedIntro, {'event': 'audio.onComplete'});
      await waitFor(
        () => feedback.any(
          (entry) =>
              entry.$1 == '8' && entry.$2 != ArtemisPlaybackStatus.started,
        ),
      );
      expect(feedback.where((entry) => entry.$1 == '8'), [
        ('8', ArtemisPlaybackStatus.started),
        ('8', ArtemisPlaybackStatus.failed),
      ]);

      play('9');
      await waitFor(
        () => feedback.contains(('9', ArtemisPlaybackStatus.started)),
      );
      fadePlayer = resumed.last;
      send({
        'op': 'stop',
        'playback_ids': ['9'],
        'time_ms': '33',
      });
      await volumeSent.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(fadeStopping.isCompleted, isFalse);
      expect(feedback.where((entry) => entry.$1 == '9'), [
        ('9', ArtemisPlaybackStatus.started),
      ]);
      allowVolume.complete();
      await fadeStopping.future.timeout(const Duration(seconds: 2));
      expect(feedback.where((entry) => entry.$1 == '9'), [
        ('9', ArtemisPlaybackStatus.started),
      ]);
      allowFadeStop.complete();
      await waitFor(
        () => feedback.contains(('9', ArtemisPlaybackStatus.cancelled)),
      );
      expect(disposed, contains(fadePlayer));

      play('10');
      await waitFor(
        () => feedback.contains(('10', ArtemisPlaybackStatus.started)),
      );
      rejectedPanPlayer = resumed.last;
      send({
        'op': 'pan',
        'playback_ids': ['10'],
        'value': 1,
        'time_ms': '33',
      });
      await waitFor(
        () => feedback.contains(('10', ArtemisPlaybackStatus.failed)),
      );
      expect(disposed, contains(rejectedPanPlayer));
      expect(feedback.where((entry) => entry.$1 == '10'), [
        ('10', ArtemisPlaybackStatus.started),
        ('10', ArtemisPlaybackStatus.failed),
      ]);

      play('11');
      await waitFor(
        () => feedback.contains(('11', ArtemisPlaybackStatus.started)),
      );
      rejectedReleasePlayer = resumed.last;
      send({
        'op': 'stop',
        'playback_ids': ['11'],
        'time_ms': '0',
      });
      await waitFor(
        () => feedback.any(
          (entry) =>
              entry.$1 == '11' && entry.$2 != ArtemisPlaybackStatus.started,
        ),
      );
      expect(feedback.where((entry) => entry.$1 == '11'), [
        ('11', ArtemisPlaybackStatus.started),
        ('11', ArtemisPlaybackStatus.failed),
      ]);

      for (final id in ['12', '13']) {
        send(playCommand(id, channel: 'se')..['key'] = 'shared.wav');
      }
      await waitFor(
        () =>
            feedback.contains(('12', ArtemisPlaybackStatus.started)) &&
            feedback.contains(('13', ArtemisPlaybackStatus.started)),
      );
      expect(reads['shared.wav'], 1);

      final releasedBeforeOpening = disposed.length;
      failOpeningSource = true;
      send(playCommand('14', channel: 'se'));
      await sourceFailed.future.timeout(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(feedback.where((entry) => entry.$1 == '14'), isEmpty);
      expect(disposed.length, releasedBeforeOpening);
      allowFailedSource.complete();
      await waitFor(
        () => feedback.contains(('14', ArtemisPlaybackStatus.failed)),
      );
      expect(disposed.length, releasedBeforeOpening + 1);
      expect(feedback.where((entry) => entry.$1 == '14'), [
        ('14', ArtemisPlaybackStatus.failed),
      ]);

      play('15');
      await waitFor(
        () => feedback.contains(('15', ArtemisPlaybackStatus.started)),
      );
      final previous = resumed.last;
      Future<String> replaceWhilePreparing(String id, String replaces) {
        final opening = sourceOpening = Completer<String>();
        play(id, replaces: replaces);
        return opening.future.timeout(const Duration(seconds: 2));
      }

      final pending = await replaceWhilePreparing('16', '15');
      final replacement = await replaceWhilePreparing('17', '16');
      expect(disposed, isNot(contains(previous)));
      send({
        'op': 'stop',
        'playback_ids': ['17'],
        'time_ms': '0',
      });
      await waitFor(
        () => feedback.contains(('17', ArtemisPlaybackStatus.cancelled)),
      );
      expect(disposed, contains(previous));
      allowSource.complete();
      await waitFor(
        () => disposed.contains(pending) && disposed.contains(replacement),
      );
      expect(resumed, isNot(anyElement(isIn([pending, replacement]))));
      expect(feedback.where((entry) => ['16', '17'].contains(entry.$1)), [
        ('17', ArtemisPlaybackStatus.cancelled),
      ]);

      play('18');
      await waitFor(
        () => feedback.contains(('18', ArtemisPlaybackStatus.started)),
      );
      final retired = rejectedPausePlayer = resumed.last;
      send(playCommand('19', replaces: '18')..['fade_ms'] = '4000');
      await waitFor(
        () => feedback.contains(('19', ArtemisPlaybackStatus.started)),
      );
      final current = resumed.last;
      await host.setSuspended(true);
      expect(disposed, contains(retired));
      expect(disposed, isNot(contains(current)));
      await host.setSuspended(false);
      expect(resumed.last, current);
      expect(feedback.where((entry) => ['18', '19'].contains(entry.$1)), [
        ('18', ArtemisPlaybackStatus.started),
        ('19', ArtemisPlaybackStatus.started),
      ]);

      replacingPlayer = current;
      send({
        'op': 'stop',
        'playback_ids': ['19'],
        'time_ms': '0',
      });
      await replacementStopping.future.timeout(const Duration(seconds: 2));
      final openedPlayers = volumes.keys.toSet();
      play('20');
      send(playCommand('21', channel: 'se'));
      await waitFor(
        () => feedback.contains(('21', ArtemisPlaybackStatus.started)),
      );
      await waitFor(
        () =>
            volumes.entries
                .where(
                  (entry) =>
                      !openedPlayers.contains(entry.key) &&
                      entry.value.length >= 2,
                )
                .length ==
            2,
      );
      await Future<void>.delayed(Duration.zero);
      expect(feedback, isNot(contains(('20', ArtemisPlaybackStatus.started))));
      allowReplacementStop.complete();
      await waitFor(
        () => feedback.contains(('20', ArtemisPlaybackStatus.started)),
      );
      expect(disposed, contains(current));

      final outgoing = rejectedVolumePlayer = resumed.last;
      final targetVolume = volumes[outgoing]!.last;
      send(playCommand('22', replaces: '20')..['fade_ms'] = '132');
      await waitFor(
        () => feedback.contains(('22', ArtemisPlaybackStatus.started)),
      );
      final incoming = resumed.last;
      await waitFor(
        () =>
            feedback.contains(('22', ArtemisPlaybackStatus.failed)) ||
            (disposed.contains(outgoing) &&
                volumes[incoming]!.last == targetVolume),
      );
      expect(disposed, contains(outgoing));
      expect(disposed, isNot(contains(incoming)));
      expect(feedback.where((entry) => entry.$1 == '22'), [
        ('22', ArtemisPlaybackStatus.started),
      ]);
    } finally {
      if (!allowReplacementStop.isCompleted) allowReplacementStop.complete();
      if (!allowSource.isCompleted) allowSource.complete();
      if (!allowVolume.isCompleted) allowVolume.complete();
      if (!allowFadeStop.isCompleted) allowFadeStop.complete();
      if (!allowFailedSource.isCompleted) allowFailedSource.complete();
      if (stopGate?.isCompleted == false) stopGate!.complete();
      resumeGate?.complete();
      await host.dispose();
      await opened.session.close();
      await changes.close();
    }
  });

  test('video skips and project cleanup wait for native close', () async {
    const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var closing = Completer<void>();
    var allowClose = Completer<void>();
    var openedVideo = Completer<File>();
    final openVolumes = <double>[];
    final closed = <String>[];
    var videoEvents = <Map<String, Object?>>[];
    var failVideoResume = false;
    final videoPauseEntered = Completer<void>();
    final allowVideoPause = Completer<void>();
    var holdVideoPause = false;
    messenger.setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'open':
          return {
            'session': '1',
            'epoch': '1',
            'width': 4,
            'height': 4,
            'phase': 0,
            'waitFlags': 0,
            'exitRequested': false,
          };
        case 'videoOpen':
          openVolumes.add(call.arguments['volume'] as double);
          openedVideo.complete(File(call.arguments['path'] as String));
        case 'videoSuspend':
          if (holdVideoPause && call.arguments['suspended'] == true) {
            holdVideoPause = false;
            videoPauseEntered.complete();
            await allowVideoPause.future;
            throw PlatformException(code: 'video_pause_failed');
          }
          if (failVideoResume && call.arguments['suspended'] == false) {
            failVideoResume = false;
            throw PlatformException(code: 'video_resume_failed');
          }
        case 'videoPoll':
          final events = videoEvents;
          videoEvents = [];
          return events;
        case 'videoClose':
          closed.add(call.arguments['playback'] as String);
          if (!closing.isCompleted) {
            closing.complete();
            await allowClose.future;
          }
      }
      return null;
    });
    final opened = await ArtemisFlutterSession.open(
      ini: Uint8List(0),
      platform: 'windows',
      hostCaps: ArtemisMediaCommand.capability,
    );
    var copyCount = 0;
    var sourceByte = 0;
    final copyInProgress = Completer<File>();
    final continueCopy = Completer<void>();
    final host = ArtemisV2MediaHost(
      writeVideoAsset: (key, destination, isCurrent) async {
        copyCount++;
        await destination.writeAsBytes([sourceByte]);
        if (key == 'pending.wmv') {
          copyInProgress.complete(destination);
          await continueCopy.future;
          expect(isCurrent(), isFalse);
          return null;
        }
        return destination;
      },
    );
    final feedback = <(String, ArtemisPlaybackStatus)>[];
    void play(
      String id,
      int byte, {
      required int skip,
      String key = 'clip.wmv',
    }) {
      sourceByte = byte;
      host.handle(
        opened.session,
        opened.state.epoch,
        ArtemisMediaCommand.decode(5, 2, {
          'op': 'play',
          'playback_id': id,
          'key': key,
          'loop': false,
          'skip': skip,
        })!,
        (id, status) => feedback.add((id, status)),
      );
    }

    Future<void> started(String id) async {
      videoEvents = [
        {
          'playback': id,
          'status': 'started',
          'texture': 7,
          'width': 4,
          'height': 4,
        },
      ];
      await host.pollVideo(opened.session);
    }

    try {
      const timeout = Duration(seconds: 2);
      host.handle(
        opened.session,
        opened.state.epoch,
        ArtemisMediaCommand.decode(5, 1, {
          'op': 'volume',
          'channel': 'video',
          'level': 400,
        })!,
        (_, _) {},
      );
      play('1', 1, skip: 1);
      final first = await openedVideo.future.timeout(timeout);
      expect(await first.readAsBytes(), [1]);
      await started('1');
      final skipping = host.skipVideo();
      await closing.future.timeout(timeout);
      expect(feedback, [('1', ArtemisPlaybackStatus.started)]);
      expect(host.videoPlayback.value, isNotNull);
      videoEvents = [
        {'playback': '1', 'status': 'ended'},
      ];
      await host.pollVideo(opened.session);
      await host.skipVideo();
      expect(feedback, [('1', ArtemisPlaybackStatus.started)]);
      expect(closed, ['1']);
      allowClose.complete();
      await skipping.timeout(timeout);
      expect(feedback, [
        ('1', ArtemisPlaybackStatus.started),
        ('1', ArtemisPlaybackStatus.cancelled),
      ]);
      expect(host.videoPlayback.value, isNull);

      closing = Completer<void>();
      allowClose = Completer<void>();
      openedVideo = Completer<File>();
      play('2', 1, skip: 2);
      await openedVideo.future.timeout(timeout);
      await started('2');
      await host.skipVideo();
      expect(closed, ['1']);
      host.videoPlayback.value!.onMenuSkip!();
      await closing.future.timeout(timeout);
      final resetting = host.resetProject();
      try {
        await closing.future.timeout(timeout);
        expect(await first.exists(), isTrue);
      } finally {
        allowClose.complete();
        await resetting.timeout(timeout);
      }
      expect(await first.exists(), isFalse);
      expect(feedback.last, ('2', ArtemisPlaybackStatus.started));
      expect(closed, ['1', '2']);

      openedVideo = Completer<File>();
      play('3', 2, skip: 0);
      final second = await openedVideo.future.timeout(timeout);
      expect(await second.readAsBytes(), [2]);
      expect(openVolumes, [0.4, 0.4, 1.0]);
      expect(copyCount, 2);
      await started('3');
      holdVideoPause = true;
      final oldPause = host.setSuspended(true);
      await videoPauseEntered.future.timeout(timeout);
      await host.setSuspended(false);
      allowVideoPause.complete();
      await oldPause.timeout(timeout);
      expect(closed, ['1', '2']);
      expect(host.videoPlayback.value, isNotNull);

      await host.setSuspended(true);
      failVideoResume = true;
      await host.setSuspended(false);
      expect(closed, ['1', '2', '3']);
      expect(host.videoPlayback.value, isNull);
      expect(feedback.where((entry) => entry.$1 == '3'), [
        ('3', ArtemisPlaybackStatus.started),
        ('3', ArtemisPlaybackStatus.failed),
      ]);

      openedVideo = Completer<File>();
      play('4', 3, skip: 0, key: 'pending.wmv');
      final partial = await copyInProgress.future.timeout(timeout);
      final cancelling = host.resetProject();
      continueCopy.complete();
      await cancelling.timeout(timeout);
      expect(await partial.exists(), isFalse);
      expect(openedVideo.isCompleted, isFalse);
      expect(feedback.map((event) => event.$1), isNot(contains('4')));
    } finally {
      if (!allowVideoPause.isCompleted) allowVideoPause.complete();
      if (!continueCopy.isCompleted) continueCopy.complete();
      if (!allowClose.isCompleted) allowClose.complete();
      await host.dispose();
      await opened.session.close();
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
}
