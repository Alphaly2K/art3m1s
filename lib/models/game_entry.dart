class GameEntry {
  final String name;
  final String path;
  final GameSource source;
  final DateTime addedAt;
  final DateTime? lastPlayedAt;
  final String? displayName;
  final String? coverPath;

  const GameEntry({
    required this.name,
    required this.path,
    required this.source,
    required this.addedAt,
    this.lastPlayedAt,
    this.displayName,
    this.coverPath,
  });

  String get displayNameOrName => displayName ?? name;

  Map<String, dynamic> toJson() => {
        'name': name,
        'path': path,
        'source': source.name,
        'addedAt': addedAt.toIso8601String(),
        'lastPlayedAt': lastPlayedAt?.toIso8601String(),
        'displayName': displayName,
        'coverPath': coverPath,
      };

  factory GameEntry.fromJson(Map<String, dynamic> json) => GameEntry(
        name: json['name'] as String,
        path: json['path'] as String,
        source: GameSource.values.byName(json['source'] as String),
        addedAt: DateTime.parse(json['addedAt'] as String),
        lastPlayedAt: json['lastPlayedAt'] != null
            ? DateTime.parse(json['lastPlayedAt'] as String)
            : null,
        displayName: json['displayName'] as String?,
        coverPath: json['coverPath'] as String?,
      );

  GameEntry copyWith({
    DateTime? lastPlayedAt,
    String? displayName,
    String? coverPath,
  }) =>
      GameEntry(
        name: name,
        path: path,
        source: source,
        addedAt: addedAt,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
        displayName: displayName ?? this.displayName,
        coverPath: coverPath ?? this.coverPath,
      );
}

enum GameSource {
  directory,
  pfsArchive,
}
