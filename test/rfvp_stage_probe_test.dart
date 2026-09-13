import 'dart:io';
import 'dart:typed_data';

import 'package:art3m1s/engine/backends/rfvp_engine_runtime.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final gameRoot = Platform.environment['RFVP_SMOKE_GAME'];
  final library = Platform.environment['ART3M1S_CORE_LIBRARY'];

  test(
    'probe RFVP stage dimensions',
    () async {
      final runtime = RfvpEngineRuntime();
      try {
        await runtime.initialize();
        final saveRoot = Directory.systemTemp.createTempSync('rfvp-stage-');
        final ini = await runtime.prepareProject(
          projectPath: gameRoot!,
          isArchive: false,
          environmentPatchEnabled: false,
          platform: 'WINDOWS',
        );
        expect(ini, isNotNull);
        runtime.setSaveDir(saveRoot.path);
        runtime.createRuntime(1280, 720);
        stdout.writeln(
          'after_create=${runtime.stageWidth}x${runtime.stageHeight}',
        );
        expect(runtime.loadProjectBytes(Uint8List(0)), isTrue);
        stdout.writeln(
          'after_load=${runtime.stageWidth}x${runtime.stageHeight}',
        );
        runtime.shutdown();
        saveRoot.deleteSync(recursive: true);
      } finally {
        runtime.shutdown();
      }
    },
    skip: gameRoot == null || library == null
        ? 'RFVP_SMOKE_GAME or ART3M1S_CORE_LIBRARY is not set'
        : false,
  );
}
