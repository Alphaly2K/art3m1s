import 'dart:io';

import 'package:art3m1s/engine/engine_runtime_factory.dart';
import 'package:art3m1s/engine/backends/art3m1s_engine_runtime.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:art3m1s/services/logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('optional Siglus native host bridge renders a real game', () async {
    final game = Platform.environment['ART3M1S_SIGLUS_TEST_GAME'];
    if (!Platform.isMacOS || game == null) return;
    final runtime = EngineRuntimeFactory.create(engine: GameEngineKind.siglus);
    try {
      await runtime.initialize();
      expect(
        runtime.isInitialized,
        isTrue,
        reason: Log.entries.map((entry) => entry.message).join('\n'),
      );
      final prepared = await runtime.prepareProject(
        projectPath: game,
        isArchive: false,
        environmentPatchEnabled: false,
        platform: 'WINDOWS',
      );
      expect(prepared, isNotNull);
      runtime.createRuntime(1280, 720);
      expect(runtime.loadProjectBytes(prepared!), isTrue);
      // A merely non-black frame misses UCI/MARK failures: the lower strip of
      // Rewrite's title background still renders while its portraits vanish.
      for (var index = 0; index < 850; index++) {
        expect(runtime.advanceWithoutRender(16), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      final frame = runtime.advanceAndRender(16);
      expect(frame, isNotNull);
      expect(frame!.length, runtime.stageWidth * runtime.stageHeight * 4);
      final visiblePixels = frame.buffer
          .asUint32List()
          .where((pixel) => pixel & 0x00ffffff != 0)
          .length;
      expect(visiblePixels, greaterThan(frame.length ~/ 8));
      runtime.feedMouse(100, 100);
    } finally {
      runtime.shutdown();
    }
  });

  test(
    'optional Artemis native runtime boots a hybrid unpacked project',
    () async {
      final game = Platform.environment['ART3M1S_ARTEMIS_TEST_GAME'];
      if (!Platform.isMacOS || game == null) return;
      final runtime = Art3m1sEngineRuntime();
      try {
        await runtime.initialize();
        expect(
          runtime.isInitialized,
          isTrue,
          reason: Log.entries.map((entry) => entry.message).join('\n'),
        );
        // 混合包：散装 system.ini + root.pfs 分卷，BOOT 脚本只在归档里。
        final prepared = await runtime.prepareProject(
          projectPath: game,
          isArchive: false,
          environmentPatchEnabled: false,
          platform: 'ANDROID',
        );
        expect(
          prepared,
          isNotNull,
          reason: Log.entries.map((entry) => entry.message).join('\n'),
        );
        runtime.registerFileReader();
        runtime.createRuntime(1280, 720);
        runtime.setReportedOs('ANDROID');
        expect(
          runtime.loadProjectBytes(prepared!, platform: 'ANDROID'),
          isTrue,
          reason: Log.entries.map((entry) => entry.message).join('\n'),
        );
        for (var index = 0; index < 60; index++) {
          expect(runtime.advanceWithoutRender(16), isTrue);
        }
        final frame = runtime.advanceAndRender(16);
        expect(frame, isNotNull);
        expect(frame!.length, runtime.stageWidth * runtime.stageHeight * 4);
      } finally {
        runtime.shutdown();
      }
    },
  );
}
