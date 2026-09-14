import Foundation

@MainActor
final class LibraryStore: ObservableObject {
  @Published private(set) var games: [GameEntry] = []
  @Published private(set) var isWorking = false
  @Published var message: String?

  private let defaults: UserDefaults
  private let storageKey = "game_library"
  private let encoder: JSONEncoder
  private let decoder: JSONDecoder

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.sortedKeys]
    decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
  }

  static var preview: LibraryStore {
    let store = LibraryStore(
      defaults: UserDefaults(suiteName: "Art3m1sNativePreview") ?? .standard
    )
    store.games = [
      GameEntry(
        name: "Sample Game",
        path: "/tmp/Sample Game",
        source: .directory,
        engine: .art3m1s
      )
    ]
    return store
  }

  func prepare() async {
    do {
      try AppDataPaths.ensureInitialized()
    } catch {
      message = "无法创建应用数据目录：\(error.localizedDescription)"
      AppLogger.error(message ?? "")
    }
    load()
    reconcileStoredPaths()
  }

  func scanAppFolder() async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }

    do {
      try AppDataPaths.ensureInitialized()
      let discovered = GameImporter.discover(in: AppDataPaths.games)
      let previousLastPlayed = Dictionary(
        grouping: games,
        by: { $0.displayNameOrName.lowercased() }
      )
      games.removeAll()
      let added = await add(discovered)
      if added > 0 {
        for index in games.indices {
          let key = games[index].displayNameOrName.lowercased()
          games[index].lastPlayedAt = previousLastPlayed[key]?
            .compactMap(\.lastPlayedAt)
            .max()
        }
      }
      save()
      message = added == 0
        ? "未发现游戏。请在 Files 中把游戏放入本 App 的 Games 目录。"
        : "已更新 \(added) 个游戏"
    } catch {
      message = "扫描失败：\(error.localizedDescription)"
      AppLogger.error(message ?? "")
    }
  }

  /// Copies user-selected folders into Documents/Games, then scans only that
  /// managed directory.
  func importFolders(_ urls: [URL]) async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }

    do {
      try AppDataPaths.ensureInitialized()
      var imported: [DiscoveredGame] = []
      for url in urls {
        let copied = try GameImporter.copyIntoGamesDirectory(url)
        imported.append(contentsOf: GameImporter.discover(in: copied))
      }
      guard !imported.isEmpty else {
        message = "所选目录中没有可识别的游戏"
        return
      }
      let added = await add(imported)
      message = added == 0 ? "所选游戏都已在资料库中" : "已导入 \(added) 个游戏"
    } catch {
      message = "导入失败：\(error.localizedDescription)"
      AppLogger.error(message ?? "")
    }
  }

  func delete(_ game: GameEntry) {
    games.removeAll { $0.id == game.id }
    save()
  }

  func update(_ game: GameEntry) {
    guard let index = games.firstIndex(where: { $0.id == game.id }) else {
      return
    }
    games[index] = game
    save()
  }

  func markPlayed(_ game: GameEntry) {
    guard let index = games.firstIndex(where: { $0.id == game.id }) else {
      return
    }
    games[index].lastPlayedAt = .now
    save()
  }

  private func add(_ discoveredGames: [DiscoveredGame]) async -> Int {
    var added = 0
    for discovered in discoveredGames {
      let normalized = GameImporter.normalizePath(discovered.path)
      if games.contains(where: { GameImporter.isSamePath($0.path, normalized) }) {
        continue
      }

      let manifest = GameManifest.load(for: discovered)
      let engine = GameImporter.detectEngine(in: discovered.path)
      let resolvedName = manifest?.name?.trimmingCharacters(in: .whitespacesAndNewlines)
      let name = resolvedName?.isEmpty == false ? resolvedName! : discovered.name
      let manifestPath = GameManifest.manifestURL(for: discovered).path

      games.append(
        GameEntry(
          name: name,
          path: discovered.path,
          source: discovered.source,
          engine: engine,
          displayName: resolvedName == discovered.name ? nil : resolvedName,
          translationEnabled: manifest?.translationEnabled ?? false,
          translationPatchPath: manifest?.translationPatchPath ?? "",
          environmentPatchEnabled: manifest?.environmentPatchEnabled ?? false,
          experimentalElunaEnabled: manifest?.experimentalElunaEnabled ?? false,
          inputGate: manifest?.inputGate,
          vndbId: manifest?.vndbID ?? "",
          fontOverridePath: manifest?.fontOverride ?? "",
          reportedOs: manifest?.reportedOs ?? "",
          runtimePlatform: manifest?.runtimePlatform?.uppercased()
            ?? GameManifest.defaultRuntimePlatform,
          manifestPath: manifestPath
        )
      )
      added += 1
    }
    if added > 0 {
      save()
    }
    return added
  }

  private func load() {
    guard let data = defaults.data(forKey: storageKey) else {
      if let string = defaults.string(forKey: storageKey) {
        loadLegacyString(string)
      }
      return
    }
    games = (try? decoder.decode([GameEntry].self, from: data)) ?? []
  }

  private func loadLegacyString(_ string: String) {
    guard let data = string.data(using: .utf8) else { return }
    games = (try? decoder.decode([GameEntry].self, from: data)) ?? []
  }

  private func save() {
    guard let data = try? encoder.encode(games) else {
      AppLogger.error("资料库序列化失败")
      return
    }
    defaults.set(data, forKey: storageKey)
  }

  private func reconcileStoredPaths() {
    guard !games.isEmpty else { return }
    let manager = FileManager.default
    let root = AppDataPaths.games.standardizedFileURL
    var repaired: [GameEntry] = []

    for original in games {
      var game = original
      let storedURL = URL(fileURLWithPath: game.path).standardizedFileURL
      if !manager.fileExists(atPath: storedURL.path) {
        let candidate = root.appendingPathComponent(
          storedURL.lastPathComponent,
          isDirectory: game.source == .directory
        )
        if manager.fileExists(atPath: candidate.path) {
          game.path = candidate.path
          if let manifestPath = game.manifestPath {
            let manifestName = URL(fileURLWithPath: manifestPath).lastPathComponent
            game.manifestPath = candidate
              .appendingPathComponent(manifestName)
              .path
          }
        }
      }
      repaired.append(game)
    }

    var unique: [String: GameEntry] = [:]
    for game in repaired {
      let key = GameImporter.normalizePath(game.path)
      guard let existing = unique[key] else {
        unique[key] = game
        continue
      }
      let existingDate = existing.lastPlayedAt ?? existing.addedAt
      let candidateDate = game.lastPlayedAt ?? game.addedAt
      if candidateDate > existingDate {
        unique[key] = game
      }
    }

    let reconciled = unique.values.sorted { $0.addedAt < $1.addedAt }
    if reconciled != games {
      games = reconciled
      save()
      AppLogger.info("Reconciled \(games.count) stored library entries")
    }
  }
}
