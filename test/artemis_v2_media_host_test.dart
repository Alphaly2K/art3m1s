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
    final stopping = Completer<void>();
    var failNextResume = false;
    String? fadePlayer;
    final volumeSent = Completer<void>();
    final allowVolume = Completer<void>();
    final fadeStopping = Completer<void>();
    final allowFadeStop = Completer<void>();
    String? rejectedPanPlayer;
    String? rejectedReleasePlayer;

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
    final host = ArtemisV2MediaHost()
      ..configureAssetReader((_) => Uint8List.fromList('RIFF'.codeUnits));
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
      'fade_ms': replaces == null ? '0' : '4000',
      'skippable': false,
      'crossfade': replaces != null,
    };

    void play(String id, {String? replaces, String? loopKey, int? gain}) =>
        send(playCommand(id, replaces: replaces, loopKey: loopKey, gain: gain));

    try {
      play('1', loopKey: 'loop.wav');
      await waitFor(
        () => feedback.contains(('1', ArtemisPlaybackStatus.started)),
      );
      final intro = resumed.single;
      await audioEvent(intro, {'event': 'audio.onComplete'});
      await waitFor(() => resumed.length >= 2);
      expect(resumed, hasLength(2));
      final loop = resumed.last;
      expect(loop, isNot(intro));
      await audioEvent(loop, {'event': 'audio.onComplete'});
      await audioFailure(intro);
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

      for (final time in ['4000', '0']) {
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
      await host.setSuspended(false);
      await waitFor(
        () => feedback.contains(('3', ArtemisPlaybackStatus.started)),
      );
      expect(resumed.skip(beforeOpening), [active, active]);
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
        'plays': [playCommand('5')],
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
    } finally {
      if (!allowVolume.isCompleted) allowVolume.complete();
      if (!allowFadeStop.isCompleted) allowFadeStop.complete();
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
      if (!continueCopy.isCompleted) continueCopy.complete();
      if (!allowClose.isCompleted) allowClose.complete();
      await host.dispose();
      await opened.session.close();
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
}
