import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:art3m1s/engine/backends/rfvp_engine_runtime.dart';
import 'package:art3m1s/engine/backends/rfvp/core_rfvp_api.dart';
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
  test(
    'Art3m1s core RFVP ABI mounts the project root',
    () {
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
    },
    skip: gameRoot == null || library == null
        ? 'RFVP_SMOKE_GAME or ART3M1S_CORE_LIBRARY is not set'
        : false,
  );

  test(
    'loads and renders a real RFVP project',
    () async {
      final saveRoot = Directory.systemTemp.createTempSync(
        'art3m1s-rfvp-smoke-',
      );
      final runtime = RfvpEngineRuntime();
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
        expect(pixels, contains(anyOf(isNot(0), isNot(0), isNot(0), isNot(0))));
      } finally {
        runtime.shutdown();
        if (saveRoot.existsSync()) saveRoot.deleteSync(recursive: true);
      }
    },
    skip: gameRoot == null || library == null
        ? 'RFVP_SMOKE_GAME or ART3M1S_CORE_LIBRARY is not set'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'logic-only catch-up ticks preserve texture commands',
    () async {
      final saveRoot = Directory.systemTemp.createTempSync(
        'art3m1s-rfvp-catchup-',
      );
      final runtime = RfvpEngineRuntime();
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
      } finally {
        runtime.shutdown();
        if (saveRoot.existsSync()) saveRoot.deleteSync(recursive: true);
      }
    },
    skip: gameRoot == null || library == null
        ? 'RFVP_SMOKE_GAME or ART3M1S_CORE_LIBRARY is not set'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
