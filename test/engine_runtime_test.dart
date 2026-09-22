import 'dart:io';
import 'dart:typed_data';

import 'package:art3m1s/engine/backends/art3m1s/file_provider.dart';
import 'package:art3m1s/engine/engine_runtime_factory.dart';
import 'package:art3m1s/engine/engine_runtime.dart';
import 'package:art3m1s/engine/backends/art3m1s_engine_runtime.dart';
import 'package:art3m1s/engine/backends/rfvp_engine_runtime.dart';
import 'package:art3m1s/engine/backends/krkr_engine_runtime.dart';
import 'package:art3m1s/engine/backends/siglus_engine_runtime.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:art3m1s/services/logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engine ids keep legacy entries on Artemis', () {
    expect(GameEngineKind.fromId(null), GameEngineKind.art3m1s);
    expect(GameEngineKind.fromId('unknown'), GameEngineKind.art3m1s);
    expect(GameEngineKind.fromId('fvp'), GameEngineKind.rfvp);
    expect(GameEngineKind.fromId('RFVP'), GameEngineKind.rfvp);
    expect(GameEngineKind.fromId('krkr'), GameEngineKind.krkr);
    expect(GameEngineKind.fromId('Kirikiri'), GameEngineKind.krkr);
    expect(GameEngineKind.fromId('Siglus'), GameEngineKind.siglus);
  });

  test('Siglus uses its isolated host runtime adapter', () {
    final runtime = EngineRuntimeFactory.create(engine: GameEngineKind.siglus);
    expect(runtime, isA<SiglusEngineRuntime>());
    expect(runtime.hasActiveSharedTexture, isFalse);
    runtime.shutdown();
  });

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
      Uint8List? frame;
      for (var index = 0; index < 150; index++) {
        frame = runtime.advanceAndRender(16);
        if (frame != null &&
            frame.buffer.asUint32List().any(
              (pixel) => pixel & 0x00ffffff != 0,
            )) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      expect(frame, isNotNull);
      expect(frame!.length, runtime.stageWidth * runtime.stageHeight * 4);
      runtime.feedMouse(100, 100);
    } finally {
      runtime.shutdown();
    }
  });

  test('KRKR uses its isolated host runtime adapter', () {
    final runtime = EngineRuntimeFactory.create(engine: GameEngineKind.krkr);

    expect(runtime, isA<KrkrEngineRuntime>());
    expect(runtime.kind, GameEngineKind.krkr);
    expect(runtime.hasActiveSharedTexture, isFalse);
    runtime.shutdown();
  });

  test('RFVP uses its isolated host runtime adapter', () async {
    final runtime = EngineRuntimeFactory.create(engine: GameEngineKind.rfvp);

    expect(runtime, isA<RfvpEngineRuntime>());
    expect(runtime.kind, GameEngineKind.rfvp);
    expect(runtime.hasActiveSharedTexture, isFalse);
    runtime.shutdown();
  });

  test('Artemis owns its runtime bridge in the backend adapter', () {
    final runtime = EngineRuntimeFactory.create(engine: GameEngineKind.art3m1s);

    expect(runtime, isA<Art3m1sEngineRuntime>());
    expect(runtime.kind, GameEngineKind.art3m1s);
    runtime.shutdown();
  });

  test(
    'Artemis media keeps its own asset reader for resident sessions',
    () async {
      final project = Directory.systemTemp.createTempSync('artemis-media-test');
      addTearDown(() {
        FileProvider.close();
        if (project.existsSync()) project.deleteSync(recursive: true);
      });
      final sound = File(
        '${project.path}${Platform.pathSeparator}'
        'sound${Platform.pathSeparator}bgm.ogg',
      )..createSync(recursive: true);
      sound.writeAsBytesSync(Uint8List.fromList([1, 2, 3, 4]));

      final runtime = Art3m1sEngineRuntime();
      await runtime.prepareProject(
        projectPath: project.path,
        isArchive: false,
        environmentPatchEnabled: false,
        platform: 'WINDOWS',
      );
      // 常驻会话切换时，进程级 FileProvider 索引会被 detach；媒体仍必须能从
      // 当前 runtime 自己的项目路径读取资源。
      FileProvider.detachCoreMount();

      final resolved = await runtime.media.resolveAssetForTest({
        'file': 'sound/bgm.ogg',
        'resolved_file': ':sysse/bgm.ogg',
      });
      expect(resolved, isNotNull);
      expect(resolved!.readAsBytesSync(), [1, 2, 3, 4]);

      runtime.shutdown();
    },
  );

  test('Artemis and RFVP expose frozen and suspended residency only', () async {
    for (final engine in [GameEngineKind.art3m1s, GameEngineKind.rfvp]) {
      final runtime = EngineRuntimeFactory.create(engine: engine);

      expect(
        runtime.supportedSessionStates,
        contains(EngineSessionState.frozen),
      );
      expect(
        runtime.supportedSessionStates,
        contains(EngineSessionState.suspended),
      );
      expect(
        runtime.supportedSessionStates,
        isNot(contains(EngineSessionState.hibernated)),
      );
      expect(
        await runtime.setSessionState(EngineSessionState.hibernated),
        EngineSessionState.suspended,
      );
      runtime.shutdown();
    }
  });
}
