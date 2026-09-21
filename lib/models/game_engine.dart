/// Host-visible engine identity persisted with each library entry.
enum GameEngineKind {
  art3m1s('art3m1s', 'Artemis'),
  rfvp('rfvp', 'FVP'),
  krkr('krkr', 'Kirikiri');

  const GameEngineKind(this.id, this.label);

  final String id;
  final String label;

  /// 迁移期兼容:旧库条目和旧 manifest 可能缺失引擎字段,
  /// 未知值一律按最早支持的 Artemis 处理。新写入必须提供真实引擎 id。
  static GameEngineKind fromId(Object? value) {
    final id = value?.toString().trim().toLowerCase();
    return switch (id) {
      'rfvp' || 'fvp' => GameEngineKind.rfvp,
      'krkr' || 'kirikiri' => GameEngineKind.krkr,
      _ => GameEngineKind.art3m1s,
    };
  }

  /// 该引擎在"每游戏设置"中有意义的字段。
  ///
  /// 不同引擎的能力交集很小:Artemis 的环境补丁、Eluna、机种上报、启动平台段
  /// 都是 Artemis 专属概念;RFVP 侧的同名设置是空实现。设置页和 manifest 都以
  /// 此为准,不给用户展示无效开关。
  Set<GameSettingField> get supportedGameSettings => switch (this) {
    GameEngineKind.art3m1s => GameSettingField.values.toSet(),
    GameEngineKind.rfvp => const {
      GameSettingField.displayName,
      GameSettingField.cover,
      GameSettingField.vndbId,
      // RFVP 的 text event ABI 尚未落地,翻译字段仅作预留接线。
      GameSettingField.translationEnabled,
      GameSettingField.translationPatchPath,
      GameSettingField.fontOverride,
      GameSettingField.inputGate,
    },
    GameEngineKind.krkr => const {
      GameSettingField.displayName,
      GameSettingField.cover,
      GameSettingField.vndbId,
      GameSettingField.inputGate,
      GameSettingField.krkrEntryXp3,
    },
  };

  /// 是否支持 PFS 归档项目(发现、挂载、归档内清单)。
  bool get supportsPfsArchives => this == GameEngineKind.art3m1s;

  /// 是否支持导入前的原生 caption 探测。
  bool get supportsCaptionProbe => this == GameEngineKind.art3m1s;
}

/// 每游戏可编辑的设置字段。用于设置页渲染过滤和 manifest 按键过滤。
enum GameSettingField {
  displayName,
  cover,
  vndbId,
  translationEnabled,
  translationPatchPath,
  environmentPatch,
  experimentalEluna,
  fontOverride,
  reportedOs,
  runtimePlatform,
  inputGate,
  krkrEntryXp3,
}
