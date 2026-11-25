import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:art3m1s/engine/backends/rfvp_engine_runtime.dart';
import 'package:art3m1s/engine/backends/rfvp/core_rfvp_api.dart';
import 'package:art3m1s/engine/engine_runtime_factory.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:art3m1s/services/logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final gameRoot = Platform.environment['RFVP_SMOKE_GAME'];
  final library = Platform.environment['ART3M1S_CORE_LIBRARY'];
  final width =
      int.tryParse(Platform.environment['RFVP_SMOKE_WIDTH'] ?? '') ?? 1024;
  final height =
      int.tryParse(Platform.environment['RFVP_SMOKE_HEIGHT'] ?? '') ?? 640;
  final backend =
      int.tryParse(Platform.environment['RFVP_SMOKE_BACKEND'] ?? '') ?? 0;
  final tile = Platform.environment['RFVP_SMOKE_TILE'] == '1';
  final expectedVersion = Platform.environment['RFVP_SMOKE_EXPECT_VERSION'];

  RfvpEngineRuntime createPlayerRuntime() {
    final runtime =
        EngineRuntimeFactory.create(engine: GameEngineKind.rfvp)
            as RfvpEngineRuntime;
    if (expectedVersion != null) {
      expect(runtime.useReplayFrames ? '2' : '1', expectedVersion);
    }
    return runtime;
  }

  final skipProject = gameRoot == null || library == null
      ? 'RFVP_SMOKE_GAME or ART3M1S_CORE_LIBRARY is not set'
      : false;
  final services = Platform.environment['RFVP_SMOKE_SERVICES'] == '1';

  test('Art3m1s core RFVP ABI mounts the project root', () {
    final api = CoreRfvpApiV1.tryLoad(DynamicLibrary.open(library!))!;
    final runtime = api.createRuntime(
      gameRoot: gameRoot!,
      width: width,
      height: height,
      backend: backend,
    );
    try {
      expect(runtime, greaterThan(0), reason: '${api.lastStatus}');
    } finally {
      api.destroyRuntime(runtime);
    }
  }, skip: skipProject);

  test(
    'loads and renders an RFVP project through the player factory',
    () async {
      final saveRoot = Directory.systemTemp.createTempSync(
        'art3m1s-rfvp-smoke-',
      );
      final runtime = createPlayerRuntime();
      try {
        Log.clear();
        await runtime.initialize();
        expect(runtime.isInitialized, isTrue);

        final ini = await runtime.prepareProject(
          projectPath: gameRoot!,
          isArchive: false,
          environmentPatchEnabled: false,
          platform: 'WINDOWS',
        );
        expect(ini, isNotNull);
        runtime.setSaveDir(saveRoot.path);
        runtime.registerFileReader();
        runtime.createRuntime(width, height, backend: backend);
        expect(
          runtime.loadProjectBytes(Uint8List(0)),
          isTrue,
          reason: runtime.lastError,
        );
        expect(
          Log.entries.any(
            (entry) => entry.message.contains('rfvp no_std boot'),
          ),
          isTrue,
          reason: 'RFVP logs did not reach art3m1s-log',
        );

        Uint8List? pixels;
        for (var frame = 0; frame < 3 && pixels == null; frame++) {
          pixels = runtime.advanceAndRender(16);
        }
        expect(pixels, isNotNull);
        expect(pixels!.length, greaterThan(0));
        expect(pixels, contains(isNot(0)));
      } finally {
        runtime.shutdown();
        if (saveRoot.existsSync()) saveRoot.deleteSync(recursive: true);
      }
    },
    skip: skipProject,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'logic-only catch-up ticks preserve texture commands',
    () async {
      final saveRoot = Directory.systemTemp.createTempSync(
        'art3m1s-rfvp-catchup-',
      );
      final runtime = createPlayerRuntime();
      try {
        await runtime.initialize();
        expect(runtime.isInitialized, isTrue);

        final ini = await runtime.prepareProject(
          projectPath: gameRoot!,
          isArchive: false,
          environmentPatchEnabled: false,
          platform: 'WINDOWS',
        );
        expect(ini, isNotNull);
        runtime.setSaveDir(saveRoot.path);
        runtime.registerFileReader();
        runtime.createRuntime(width, height, backend: backend);
        expect(runtime.loadProjectBytes(Uint8List(0)), isTrue);

        // Simulate a render-skipping logic tick before the first presented
        // frame. The next frame must still contain all texture create/update
        // commands from the skipped frame.
        runtime.advanceWithoutRender(16);
        Uint8List? pixels;
        for (var frame = 0; frame < 8 && pixels == null; frame++) {
          pixels = runtime.advanceAndRender(16);
        }
        expect(pixels, isNotNull);
        expect(pixels!.length, greaterThan(0));
        if (tile) {
          expect(pixels.length, width * height * 4);
          List<int> rgb(int x, int y) {
            final offset = (y * width + x) * 4;
            return pixels!.sublist(offset, offset + 3);
          }

          expect(rgb(8, 12), [255, 255, 255]);
          expect(rgb(23, 31), [255, 255, 255]);
          expect(rgb(7, 12), [0, 0, 0]);
          expect(rgb(24, 31), [0, 0, 0]);
        }
      } finally {
        runtime.shutdown();
        if (saveRoot.existsSync()) saveRoot.deleteSync(recursive: true);
      }
    },
    skip: skipProject,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('routes script audio and translation through the player session', () {
    final api = CoreRfvpApiV1.tryLoad(
      DynamicLibrary.open(library!),
      replayHost: createPlayerRuntime().useReplayFrames,
    )!;
    final runtime = api.createRuntime(
      gameRoot: gameRoot!,
      width: width,
      height: height,
      backend: backend,
    );
    try {
      expect(runtime, greaterThan(0), reason: '${api.lastStatus}');
      expect(api.setTextTranslationEnabled(runtime, true), art3m1sRfvpStatusOk);
      expect(api.step(runtime, 16), art3m1sRfvpStatusOk);

      final audio = <RfvpCoreAudioCommand>[];
      for (
        var command = api.pollAudioCommand(runtime);
        command != null;
        command = api.pollAudioCommand(runtime)
      ) {
        audio.add(command);
      }
      expect(
        audio
            .where((command) => command.kind == art3m1sRfvpAudioMasterVolume)
            .map((command) => command.volume),
        contains(closeTo(0.37, 0.0001)),
      );
      final requests = api.pollTextEvents(runtime);
      final request = requests.singleWhere(
        (event) => event.source == 'RFVP smoke text',
      );
      expect(
        api.submitTextTranslation(runtime, request.serial, 'Translated text'),
        art3m1sRfvpStatusOk,
      );
      expect(api.step(runtime, 16), art3m1sRfvpStatusOk);
      expect(api.pollTextEvents(runtime), isEmpty);
    } finally {
      api.destroyRuntime(runtime);
    }
  }, skip: services ? skipProject : 'RFVP_SMOKE_SERVICES is not enabled');
}
