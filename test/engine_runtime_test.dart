import 'package:art3m1s/engine/engine_runtime.dart';
import 'package:art3m1s/engine/engine_runtime_factory.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engine ids keep legacy entries on Artemis', () {
    expect(GameEngineKind.fromId(null), GameEngineKind.art3m1s);
    expect(GameEngineKind.fromId('unknown'), GameEngineKind.art3m1s);
    expect(GameEngineKind.fromId('fvp'), GameEngineKind.rfvp);
    expect(GameEngineKind.fromId('RFVP'), GameEngineKind.rfvp);
  });

  test('unwired RFVP remains a safe engine runtime placeholder', () async {
    final runtime = EngineRuntimeFactory.create(engine: GameEngineKind.rfvp);

    expect(runtime, isA<UnsupportedEngineRuntime>());
    expect(runtime.kind, GameEngineKind.rfvp);
    await runtime.initialize();
    expect(runtime.isInitialized, isFalse);
    runtime.shutdown();
  });
}
