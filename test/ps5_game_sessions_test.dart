import 'package:art3m1s/controllers/ps5_game_sessions.dart';
import 'package:art3m1s/engine/engine_runtime.dart';
import 'package:art3m1s/models/game_engine.dart';
import 'package:art3m1s/models/game_entry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GameEntry game(String id, GameEngineKind engine) => GameEntry(
    id: id,
    name: id,
    path: '/games/$id',
    source: GameSource.directory,
    engine: engine,
    addedAt: DateTime(2026),
  );

  EngineSessionState stateOf(Ps5GameSessionRegistry registry, String id) {
    return registry.sessions
        .singleWhere((session) => session.entry.id == id)
        .state;
  }

  test('PS5 host keeps one active session and applies residency policy', () {
    final registry = Ps5GameSessionRegistry();
    final artemis = game('artemis', GameEngineKind.art3m1s);
    final rfvp = game('rfvp', GameEngineKind.rfvp);

    expect(registry.activate(artemis), isTrue);
    expect(registry.activeSessionId, 'artemis');

    registry.freezeToHome('artemis');
    expect(registry.activeSessionId, isNull);
    expect(stateOf(registry, 'artemis'), EngineSessionState.frozen);

    expect(registry.activate(rfvp), isTrue);
    expect(registry.activeSessionId, 'rfvp');
    expect(stateOf(registry, 'artemis'), EngineSessionState.suspended);
    expect(stateOf(registry, 'rfvp'), EngineSessionState.active);

    registry.activate(artemis);
    expect(registry.activeSessionId, 'artemis');
    expect(stateOf(registry, 'artemis'), EngineSessionState.active);
    expect(stateOf(registry, 'rfvp'), EngineSessionState.suspended);
    expect(registry.sessions, hasLength(2));
  });

  test('Kirikiri remains outside the resident-session host', () {
    final registry = Ps5GameSessionRegistry();

    expect(registry.activate(game('krkr', GameEngineKind.krkr)), isFalse);
    expect(registry.sessions, isEmpty);
    expect(registry.activeSessionId, isNull);
  });
}
