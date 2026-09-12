/// Host-visible engine identity persisted with each library entry.
enum GameEngineKind {
  art3m1s('art3m1s', 'Artemis'),
  rfvp('rfvp', 'FVP');

  const GameEngineKind(this.id, this.label);

  final String id;
  final String label;

  static GameEngineKind fromId(Object? value) {
    final id = value?.toString().trim().toLowerCase();
    return switch (id) {
      'rfvp' || 'fvp' => GameEngineKind.rfvp,
      _ => GameEngineKind.art3m1s,
    };
  }
}
