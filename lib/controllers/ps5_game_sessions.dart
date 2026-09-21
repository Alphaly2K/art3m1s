import 'package:flutter/widgets.dart';

import '../engine/engine_runtime.dart';
import '../models/game_entry.dart';

class Ps5GameSessionRecord {
  const Ps5GameSessionRecord({required this.entry, required this.state});

  final GameEntry entry;
  final EngineSessionState state;

  Ps5GameSessionRecord copyWith({GameEntry? entry, EngineSessionState? state}) {
    return Ps5GameSessionRecord(
      entry: entry ?? this.entry,
      state: state ?? this.state,
    );
  }
}

/// Host session registry. It owns policy; engine runtimes own implementation.
///
/// Returning home leaves the current session [EngineSessionState.frozen].
/// Starting another game moves the previous foreground session to
/// [EngineSessionState.suspended] so the single platform presentation surface
/// can be handed over safely.
class Ps5GameSessionRegistry {
  final Map<String, Ps5GameSessionRecord> _sessions = {};

  Iterable<Ps5GameSessionRecord> get sessions => _sessions.values;
  Set<String> get sessionIds => Set.unmodifiable(_sessions.keys);
  String? get activeSessionId => _sessions.values
      .where((session) => session.state == EngineSessionState.active)
      .firstOrNull
      ?.entry
      .id;

  bool contains(String gameId) => _sessions.containsKey(gameId);

  bool activate(GameEntry entry) {
    for (final item in _sessions.entries.toList()) {
      if (item.key == entry.id) continue;
      if (item.value.state == EngineSessionState.active ||
          item.value.state == EngineSessionState.frozen) {
        _sessions[item.key] = item.value.copyWith(
          state: EngineSessionState.suspended,
        );
      }
    }
    _sessions[entry.id] = Ps5GameSessionRecord(
      entry: entry,
      state: EngineSessionState.active,
    );
    return true;
  }

  void freezeToHome(String gameId) {
    final session = _sessions[gameId];
    if (session?.state != EngineSessionState.active) return;
    _sessions[gameId] = session!.copyWith(state: EngineSessionState.frozen);
  }

  void setResidency(String gameId, EngineSessionState state) {
    if (state == EngineSessionState.active) {
      final session = _sessions[gameId];
      if (session != null) activate(session.entry);
      return;
    }
    final session = _sessions[gameId];
    if (session != null) _sessions[gameId] = session.copyWith(state: state);
  }

  void remove(String gameId) => _sessions.remove(gameId);
}

/// PS5 壳内的常驻游戏会话入口。
///
/// 同一时间只有 [activeSessionId] 对应的会话运行；具体驻留等级由 Host 会话
/// 策略选择，并通过 EngineRuntime 的统一生命周期协议下发。
class Ps5GameSessionScope extends InheritedWidget {
  const Ps5GameSessionScope({
    super.key,
    required this.activeSessionId,
    required this.sessionIds,
    required this.activate,
    required super.child,
  });

  final String? activeSessionId;
  final Set<String> sessionIds;
  final ValueChanged<GameEntry> activate;

  bool contains(String gameId) => sessionIds.contains(gameId);

  static Ps5GameSessionScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<Ps5GameSessionScope>();
  }

  @override
  bool updateShouldNotify(Ps5GameSessionScope oldWidget) {
    return activeSessionId != oldWidget.activeSessionId ||
        sessionIds.length != oldWidget.sessionIds.length ||
        !sessionIds.containsAll(oldWidget.sessionIds);
  }
}
