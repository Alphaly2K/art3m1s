import 'dart:ffi';
import 'dart:io';

import 'package:art3m1s/engine/backends/katze_engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime_factory.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:art3m1s/services/game_importer.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Player factory runs a discovered CatSystem2 project', () async {
    final directory = Platform.environment['KATZE_GAME'];
    final library = Platform.environment['KATZE_GAME_HOST'];
    if (directory == null || library == null) {
      throw StateError('Set KATZE_GAME and KATZE_GAME_HOST');
    }
    final device = Platform.environment['KATZE_OFFSCREEN_AUDIO'] != '1';
    if (device && Platform.environment['SDL_AUDIODRIVER'] != 'dummy') {
      throw StateError('Use KATZE_OFFSCREEN_AUDIO=1 or SDL_AUDIODRIVER=dummy');
    }
    final storage = Directory.systemTemp.createTempSync('katze-player-');
    addTearDown(() => storage.deleteSync(recursive: true));
    expect(GameImporter.discoverUnpackedProjects(directory), [directory]);
    final engine = GameImporter.detectDirectoryEngine(directory);
    expect(engine, GameEngineKind.katze);
    final runtime = EngineRuntimeFactory.create(engine: engine);
    addTearDown(runtime.shutdown);
    await runtime.initialize();
    expect(runtime.isInitialized, isTrue);
    final project = await runtime.prepareProject(
      projectPath: directory,
      isArchive: false,
      environmentPatchEnabled: false,
      platform: 'WINDOWS',
    );
    expect(project, isNotNull);
    runtime.setSaveDir(storage.path);
    runtime.createRuntime(0, 0);
    expect(await runtime.loadProjectBytes(project!), isTrue);
    expect(runtime.stageWidth, greaterThan(0));
    expect(runtime.stageHeight, greaterThan(0));

    runtime.notifyLifecycle(1);
    expect(
      await runtime.setSessionState(EngineSessionState.frozen),
      EngineSessionState.frozen,
    );
    expect(runtime.advanceWithoutRender(17), isFalse);
    runtime.notifyLifecycle(2);
    expect(
      await runtime.setSessionState(EngineSessionState.active),
      EngineSessionState.active,
    );
    var pcmFrames = 0;
    using((arena) {
      final pcm = arena<Float>(1600);
      if (device) {
        expect(
          () => (runtime as KatzeEngineRuntime).mixStereo(48000, pcm, 800),
          throwsStateError,
        );
      }
      for (var tick = 1; tick < 1200; tick++) {
        final delta = tick * 1000 ~/ 60 - (tick - 1) * 1000 ~/ 60;
        expect(runtime.advanceWithoutRender(delta), isTrue);
        if (device) continue;
        (runtime as KatzeEngineRuntime).mixStereo(48000, pcm, 800);
        final samples = pcm.asTypedList(1600);
        for (var i = 0; i < samples.length; i += 2) {
          if (samples[i].abs() > 0.00001 || samples[i + 1].abs() > 0.00001) {
            pcmFrames++;
          }
        }
      }
    });
    if (!device) expect(pcmFrames, greaterThan(0));
    final frame = runtime is AsyncPixelRuntime && runtime.supportsAsyncPixels
        ? await runtime.advancePixelBatch(const [17])
        : runtime.advanceAndRender(17);
    expect(frame, hasLength(runtime.stageWidth * runtime.stageHeight * 4));
    final colors = <int>{};
    for (var pixel = 0; pixel < frame!.length; pixel += 4 * 257) {
      colors.add(frame[pixel] << 16 | frame[pixel + 1] << 8 | frame[pixel + 2]);
    }
    expect(colors.length, greaterThan(1));

    if (runtime is AsyncPixelRuntime && runtime.supportsAsyncPixels) {
      var consumed = 0;
      Iterable<int> pendingDeltas() sync* {
        for (final delta in [16, 17, 17]) {
          consumed++;
          yield delta;
        }
      }

      final pending = runtime.advancePixelBatch(pendingDeltas());
      final frozen = runtime.setSessionState(EngineSessionState.frozen);
      final resumed = runtime.setSessionState(EngineSessionState.active);
      await frozen;
      expect(await resumed, EngineSessionState.active);
      expect(await pending, isNull);
      expect(consumed, 1);
      expect(await runtime.advancePixelBatch(const [16]), isNotNull);
    }
  });
}
