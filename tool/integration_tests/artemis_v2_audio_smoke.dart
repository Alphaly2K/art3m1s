import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data' show Endian;
import 'dart:ui' as ui;

import 'package:art3m1s/engine/backends/artemis_v2_engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime_factory.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  final binding = _AudioProbeBinding();
  runApp(const SizedBox());
  final root = await Directory.systemTemp.createTemp('artemis-v2-audio-');
  try {
    await _run(root, binding.probe);
    stdout.writeln('Artemis v2 macOS audio smoke passed');
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exitCode = 1;
  } finally {
    await root.delete(recursive: true);
  }
  exit(exitCode);
}

Future<void> _run(Directory root, _AudioProbe probe) async {
  final game = Directory('${root.path}/game')..createSync();
  final saves = Directory('${root.path}/saves')..createSync();
  File(
    '${game.path}/system.ini',
  ).writeAsStringSync('[WINDOWS]\nWIDTH=4\nHEIGHT=4\nBOOT=boot.iet\n');
  for (final (name, frequency, duration) in [
    ('intro_a.wav', 220, 300),
    ('intro_b.wav', 330, 400),
    ('next.wav', 440, 500),
  ]) {
    File('${game.path}/$name').writeAsBytesSync(_tone(frequency, duration));
  }
  File('${game.path}/boot.iet').writeAsStringSync('''
*top
[keyconfig role=0 keys=70]
[splay file=intro_a.wav loop=1 gain=900]
[caption data=intro]
[wt0]
[sxfade file=next.wav loop=1 gain=600 time=3000]
[caption data=crossfade]
[wt0]
[sstop time=3000]
[sstop time=132]
[caption data=single_stop]
[wt0]
[allsoundstop time=132]
[caption data=all_stop]
[stop]
''');

  final runtime = EngineRuntimeFactory.create(engine: GameEngineKind.art3m1s);
  if (runtime is! ArtemisV2EngineRuntime) {
    throw StateError('Build with ARTEMIS_V2 enabled.');
  }

  Future<void> until(
    String phase,
    bool Function() ready, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final timer = Stopwatch()..start();
    while (timer.elapsed < timeout) {
      if (ready()) return;
      await runtime.advanceTexture(16);
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    throw StateError('Timed out during $phase (${runtime.windowTitle.value}).');
  }

  Future<void> decide() async {
    runtime.feedKey(70, true);
    await runtime.advanceTexture(16);
    runtime.feedKey(70, false);
    await runtime.advanceTexture(16);
  }

  try {
    await runtime.initialize();
    final ini = await runtime.prepareProject(
      projectPath: game.path,
      isArchive: false,
      environmentPatchEnabled: false,
      platform: 'WINDOWS',
    );
    runtime.setSaveDir(saves.path);
    runtime.createRuntime(4, 4);
    if (ini == null || !await runtime.loadProjectBytes(ini)) {
      throw StateError('Could not load the audio project.');
    }

    await until('A/B playback', () => probe.resumed.length == 2);
    final [intro, loop] = probe.resumed;
    await until('B segment loop', () => probe.wrapped(loop));

    final beforeCrossfade = probe.calls.length;
    await decide();
    await until('crossfade start', () => probe.resumed.length == 3);
    final next = probe.resumed.last;
    await until('crossfade gain ramps', () {
      final changes = probe.calls.skip(beforeCrossfade);
      bool faded(String player, double target) => changes.any(
        (call) =>
            call.method == 'setVolume' &&
            call.player == player &&
            call.value != null &&
            call.value! > 0 &&
            call.value! < target,
      );
      return faded(loop, 0.9) && faded(next, 0.6);
    });

    final players = [loop, next];
    Future<void> checkPaused(String phase) async {
      final frozenPositions = await Future.wait(players.map(probe.position));
      final frozenCalls = probe.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      for (final (index, player) in players.indexed) {
        final position = await probe.position(player);
        if ((position - frozenPositions[index]).abs() > 30) {
          throw StateError('A player advanced during $phase.');
        }
      }
      if (probe.calls
          .skip(frozenCalls)
          .any((call) => call.method == 'setVolume')) {
        throw StateError('The crossfade advanced during $phase.');
      }
    }

    runtime.notifyLifecycle(1);
    await until('background pauses both players', () {
      return players.every(probe.paused.contains);
    });
    await runtime.setSessionState(EngineSessionState.frozen);
    await runtime.setSessionState(EngineSessionState.active);
    await checkPaused('background with an active session');

    await runtime.setSessionState(EngineSessionState.frozen);
    runtime.notifyLifecycle(2);
    await checkPaused('foreground with a frozen session');

    final beforeResume = probe.calls.length;
    await runtime.setSessionState(EngineSessionState.active);
    await until('crossfade resumes', () {
      final changes = probe.calls.skip(beforeResume);
      return players.every(
        (player) => changes.any(
          (call) => call.method == 'setVolume' && call.player == player,
        ),
      );
    });

    final beforeStop = probe.calls.length;
    await decide();
    await until(
      'replacement BGM stop',
      () => probe.disposed.contains(next),
      timeout: const Duration(milliseconds: 1500),
    );
    if (!probe.calls.skip(beforeStop).any(
      (call) =>
          call.player == next && call.method == 'setVolume' && call.value == 0,
    )) {
      throw StateError('The replacement BGM fade did not reach zero volume.');
    }
    if (probe.disposed.contains(loop) || probe.disposed.contains(intro)) {
      throw StateError('The outgoing BGM was retired before allsoundstop.');
    }
    await decide();
    await until('stop all', () => probe.disposed.length == 3);
    if (probe.disposed.toSet().length != 3 ||
        runtime.windowTitle.value != 'all_stop') {
      throw StateError('The script or the outgoing players did not finish.');
    }
  } finally {
    await runtime.close();
  }
}

class _AudioProbeBinding extends WidgetsFlutterBinding {
  late final _AudioProbe probe;

  @override
  BinaryMessenger createBinaryMessenger() =>
      probe = _AudioProbe(super.createBinaryMessenger());
}

class _AudioProbe extends BinaryMessenger {
  _AudioProbe(this.delegate);

  final BinaryMessenger delegate;
  final calls = <({String method, String player, num? value})>[];
  final resumed = <String>[];
  final paused = <String>[];
  final disposed = <String>[];

  Future<int> position(String player) async {
    final position = await const MethodChannel(
      'xyz.luan/audioplayers',
    ).invokeMethod<int>('getCurrentPosition', {'playerId': player});
    if (position == null) throw StateError('Player position unavailable.');
    return position;
  }

  bool wrapped(String player) {
    var previous = 0;
    for (final call in calls) {
      if (call.player != player || call.method != 'getCurrentPosition') {
        continue;
      }
      final position = call.value!.toInt();
      if (previous - position > 150) return true;
      previous = position;
    }
    return false;
  }

  @override
  Future<ByteData?>? send(String channel, ByteData? message) {
    final result = delegate.send(channel, message);
    if (channel != 'xyz.luan/audioplayers' ||
        result == null ||
        message == null) {
      return result;
    }
    const codec = StandardMethodCodec();
    final call = codec.decodeMethodCall(message);
    final player = (call.arguments as Map)['playerId'] as String;
    return result.then((reply) {
      if (reply == null) return reply;
      try {
        final value = codec.decodeEnvelope(reply);
        switch (call.method) {
          case 'resume':
            resumed.add(player);
          case 'pause':
            paused.add(player);
          case 'dispose':
            disposed.add(player);
          case 'setVolume':
            calls.add((
              method: call.method,
              player: player,
              value: call.arguments['volume'] as num,
            ));
          case 'getCurrentPosition' when value is num:
            calls.add((method: call.method, player: player, value: value));
        }
      } on PlatformException {
        // The original error is still delivered to the player.
      }
      return reply;
    });
  }

  @override
  void setMessageHandler(String channel, MessageHandler? handler) =>
      delegate.setMessageHandler(channel, handler);

  @override
  Future<void> handlePlatformMessage(
    String channel,
    ByteData? data,
    ui.PlatformMessageResponseCallback? callback,
  ) async {
    ServicesBinding.instance.channelBuffers.push(
      channel,
      data,
      callback ?? (_) {},
    );
  }
}

Uint8List _tone(int frequency, int durationMs) {
  const rate = 16000;
  final samples = rate * durationMs ~/ 1000;
  final data = ByteData(44 + samples * 2)
    ..setUint32(0, 0x52494646)
    ..setUint32(4, 36 + samples * 2, Endian.little)
    ..setUint32(8, 0x57415645)
    ..setUint32(12, 0x666d7420)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x64617461)
    ..setUint32(40, samples * 2, Endian.little);
  for (var i = 0; i < samples; i++) {
    data.setInt16(
      44 + 2 * i,
      (600 * math.sin(i * 2 * math.pi * frequency / rate)).round(),
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}
