import 'dart:async';
import 'dart:io';

import 'package:art3m1s/engine/backends/art3m1s/media_bridge.dart';
import 'package:art3m1s/engine/backends/art3m1s/v2_sdk/artemis_flutter_session.dart';
import 'package:art3m1s/engine/engine_runtime.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stop commands retire active and replaced BGM once', () async {
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
            await resumeGate?.future;
          case 'pause':
            paused.add(id);
          case 'dispose':
            disposed.add(id);
            changes.add(null);
          case 'setVolume':
            (volumes[id] ??= []).add(call.arguments['volume'] as double);
            changes.add(null);
          case 'setBalance':
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

    void play(String id, {String? replaces, String? loopKey, int? gain}) =>
        send({
          'op': 'play',
          'playback_id': id,
          'replaces': replaces,
          'channel': 'bgm',
          'key': 'track_$id.wav',
          'loop': true,
          'loop_key': loopKey,
          'gain': gain,
          'fade_ms': replaces == null ? '0' : '4000',
          'skippable': false,
          'crossfade': replaces != null,
        });

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
        () => volumes[loop]!.last == oldLevel * 0.5 &&
            volumes[next]!.last == nextLevel * 0.5,
      );
      await host.setSuspended(false);

      for (final time in ['4000', '0']) {
        send({
          'op': 'stop',
          'playback_ids': ['2'],
          'time_ms': time,
        });
      }
      expect(feedback.last, ('2', ArtemisPlaybackStatus.cancelled));
      await waitFor(() => disposed.isNotEmpty);
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
      host.setAvoidMuted(false);
      await waitFor(() => (volumes[fresh]!.last - 0.2).abs() < 0.0001);
    } finally {
      resumeGate?.complete();
      await host.dispose();
      await opened.session.close();
      await changes.close();
    }
  });

  test('project switch removes extracted video after native close', () async {
    const channel = MethodChannel('moe.alphaly.art3m1s/artemis_v2');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final closing = Completer<void>();
    final allowClose = Completer<void>();
    var openedVideo = Completer<File>();
    final openVolumes = <double>[];
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
        case 'videoClose' when !closing.isCompleted:
          closing.complete();
          await allowClose.future;
      }
      return null;
    });
    final opened = await ArtemisFlutterSession.open(
      ini: Uint8List(0),
      platform: 'windows',
      hostCaps: ArtemisMediaCommand.capability,
    );
    final host = ArtemisV2MediaHost();
    void play(String id, int byte) {
      host.configureAssetReader((_) => Uint8List.fromList([byte]));
      host.handle(
        opened.session,
        opened.state.epoch,
        ArtemisMediaCommand.decode(5, 2, {
          'op': 'play',
          'playback_id': id,
          'key': 'clip.wmv',
          'loop': false,
          'skip': 0,
        })!,
        (_, _) {},
      );
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
      play('1', 1);
      final first = await openedVideo.future.timeout(timeout);
      expect(await first.readAsBytes(), [1]);
      final resetting = host.resetProject();
      try {
        await closing.future.timeout(timeout);
        expect(await first.exists(), isTrue);
      } finally {
        allowClose.complete();
        await resetting.timeout(timeout);
      }
      expect(await first.exists(), isFalse);

      openedVideo = Completer<File>();
      play('2', 2);
      final second = await openedVideo.future.timeout(timeout);
      expect(await second.readAsBytes(), [2]);
      expect(openVolumes, [0.4, 1.0]);
    } finally {
      await host.dispose();
      await opened.session.close();
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
}
