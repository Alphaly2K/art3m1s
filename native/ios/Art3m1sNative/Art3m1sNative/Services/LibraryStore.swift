import Combine
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
    decoder.dateDecodingStrategy = .custom { decoder in
      let value = try decoder.singleValueContainer().decode(String.self)
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
      if let date = formatter.date(from: value) { return date }
      formatter.formatOptions = [.withInternetDateTime]
      if let date = formatter.date(from: value) { return date }
      let local = DateFormatter()
      local.locale = Locale(identifier: "en_US_POSIX")
      local.timeZone = .current
      local.isLenient = false
      for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss"] {
        local.dateFormat = format
        if let date = local.date(from: value) { return date }
      }
      throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid date"))
    }
    load()
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
    reconcileStoredPaths()
  }

  func scanAppFolder(in directory: URL = AppDataPaths.games) async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }

    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let discovered = await Task.detached(priority: .userInitiated) {
        GameImporter.discover(in: directory)
      }.value
      let added = await add(discovered)
      message = discovered.isEmpty
        ? "未发现游戏。请在 Files 中把游戏放入本 App 的 Games 目录。"
        : "扫描发现 \(discovered.count) 个游戏，新增 \(added) 个"
    } catch {
      message = "扫描失败：\(error.localizedDescription)"
      AppLogger.error(message ?? "")
    }
  }

  /// Copies user-selected folders into Documents/Games, then scans only that
  /// managed directory.
  func importFolders(_ urls: [URL], into directory: URL = AppDataPaths.games) async {
    guard !isWorking else { return }
    isWorking = true
    defer { isWorking = false }

    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var added = 0
      var failures = 0
      for url in urls {
        do {
          let imported = try await Task.detached(priority: .userInitiated) {
            let copied = try GameImporter.copyIntoGamesDirectory(url, gamesDirectory: directory)
            return GameImporter.discover(in: copied)
          }.value
          added += await add(imported)
        } catch {
          failures += 1
          AppLogger.error("目录导入失败：\(error.localizedDescription)")
        }
      }
      message = "已导入 \(added) 个游戏"
        + (failures > 0 ? "，\(failures) 个目录导入失败" : "")
    } catch {
      message = "导入失败：\(error.localizedDescription)"
      AppLogger.error(message ?? "")
    }
  }

  func delete(_ game: GameEntry) {
    games.removeAll { $0.id == game.id }
    save()
  }

  @discardableResult
  func update(_ game: GameEntry) -> Bool {
    guard let index = games.firstIndex(where: { $0.id == game.id }) else {
      return false
    }
    var updated = game
    updated.lastPlayedAt = games[index].lastPlayedAt
    do {
      updated.manifestPath = try GameManifest.save(updated).path
    } catch {
      message = "项目配置保存失败：\(error.localizedDescription)"
      AppLogger.error(message ?? "")
      return false
    }
    games[index] = updated
    save()
    return true
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
      let engine = manifest?.engine.map(GameEngineKind.init(id:))
        ?? GameImporter.detectEngine(in: discovered.path)
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
          inputGate: manifest?.inputGate,
          vndbId: manifest?.vndbID ?? "",
          fontOverridePath: manifest?.fontOverride ?? "",
          reportedOs: manifest?.reportedOs ?? "",
          runtimePlatform: manifest?.runtimePlatform?.uppercased()
            ?? GameManifest.defaultRuntimePlatform,
          krkrEntryXp3: manifest?.krkrEntryXp3,
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
    decodeLibrary(data)
  }

  private func loadLegacyString(_ string: String) {
    guard let data = string.data(using: .utf8) else { return }
    decodeLibrary(data)
  }

  private func decodeLibrary(_ data: Data) {
    guard let values = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
      defaults.set(data, forKey: "game_library_recovery")
      message = "资料库数据损坏，原始数据已保留。"
      return
    }
    let rows = values.compactMap { value -> [String: Any]? in
      guard let row = value as? [String: Any] else {
        defaults.set(data, forKey: "game_library_recovery")
        return nil
      }
      return row
    }
    let legacyCounts = Dictionary(grouping: rows, by: {
      GameEntry.legacySaveId(for: $0["path"] as? String ?? "")
    }).mapValues(\.count)
    games = rows.compactMap { original in
      var row = original
      if (row["id"] as? String)?.isEmpty != false, let path = row["path"] as? String {
        let legacy = GameEntry.legacySaveId(for: path)
        row["id"] = legacyCounts[legacy] == 1 ? legacy : GameEntry.legacyId(for: path)
      }
      guard let bytes = try? JSONSerialization.data(withJSONObject: row),
            let entry = try? decoder.decode(GameEntry.self, from: bytes) else {
        defaults.set(data, forKey: "game_library_recovery")
        return nil
      }
      return entry
    }
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
        let components = storedURL.pathComponents
        if let index = components.lastIndex(of: "Games"), index + 1 < components.count {
          let relative = components[(index + 1)...].joined(separator: "/")
          let candidate = root.appendingPathComponent(relative)
          if manager.fileExists(atPath: candidate.path) {
            game.path = candidate.path
            game.manifestPath = GameManifest.manifestURL(for: DiscoveredGame(
              name: game.name, path: game.path, source: game.source
            )).path
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
