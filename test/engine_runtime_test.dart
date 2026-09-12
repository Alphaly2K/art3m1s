import 'package:art3m1s/engine/engine_runtime_factory.dart';
import 'package:art3m1s/engine/backends/art3m1s_engine_runtime.dart';
import 'package:art3m1s/engine/backends/rfvp_engine_runtime.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engine ids keep legacy entries on Artemis', () {
    expect(GameEngineKind.fromId(null), GameEngineKind.art3m1s);
    expect(GameEngineKind.fromId('unknown'), GameEngineKind.art3m1s);
    expect(GameEngineKind.fromId('fvp'), GameEngineKind.rfvp);
    expect(GameEngineKind.fromId('RFVP'), GameEngineKind.rfvp);
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
}
