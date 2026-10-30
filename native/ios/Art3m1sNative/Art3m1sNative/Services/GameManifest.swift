import Foundation

struct GameManifest: Codable, Sendable {
  static let fileName = "art3m1s.json"
  static let defaultRuntimePlatform = "WINDOWS"

  var name: String?
  var vndbID: String?
  var engine: String?
  var translationEnabled: Bool?
  var translationPatchPath: String?
  var environmentPatchEnabled: Bool?
  var fontOverride: String?
  var reportedOs: String?
  var runtimePlatform: String?
  var krkrEntryXp3: String?
  var inputGate: InputGatePolicy?

  enum CodingKeys: String, CodingKey {
    case name
    case vndbID = "vndbId"
    case engine
    case translationEnabled
    case translationPatchPath
    case environmentPatchEnabled
    case fontOverride
    case reportedOs
    case runtimePlatform
    case krkrEntryXp3
    case inputGate
  }

  static func load(for discovered: DiscoveredGame) -> GameManifest? {
    switch discovered.source {
    case .directory:
      let root = URL(fileURLWithPath: discovered.path)
      let manager = FileManager.default
      let children = (try? manager.contentsOfDirectory(
        at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
      )) ?? []
      var paths = children.filter { $0.lastPathComponent.lowercased() == fileName }
      for child in children {
        guard let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true else { continue }
        paths += ((try? manager.contentsOfDirectory(
          at: child, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        )) ?? []).filter { $0.lastPathComponent.lowercased() == fileName }
      }
      let candidates = paths.sorted {
        let lhs = $0.pathComponents.count
        let rhs = $1.pathComponents.count
        return lhs == rhs ? $0.path < $1.path : lhs < rhs
      }
      for candidate in candidates {
        guard let data = try? Data(contentsOf: candidate) else { continue }
        if let manifest = try? JSONDecoder().decode(
          GameManifest.self,
          from: data
        ) {
          return manifest
        }
      }
    case .pfsArchive:
      let sidecar = URL(fileURLWithPath: "\(discovered.path).\(fileName)")
      if let data = try? Data(contentsOf: sidecar),
         let manifest = try? JSONDecoder().decode(
           GameManifest.self,
           from: data
         ) {
        return manifest
      }
      for archive in archives(for: discovered.path).reversed() {
        guard let entries = try? PFSReader.listEntries(
          archivePath: archive,
          encoding: "Shift_JIS"
        ), let selected = selectManifestPath(entries) else {
          continue
        }
        guard let data = try? PFSReader.read(
          archivePath: archive,
          entryPath: selected,
          encoding: "Shift_JIS"
        ), let manifest = try? JSONDecoder().decode(
          GameManifest.self,
          from: data
        ) else {
          continue
        }
        return manifest
      }
    }
    return nil
  }

  static func selectManifestPath(_ entries: [String]) -> String? {
    let candidates = entries.map { $0.replacingOccurrences(of: "\\", with: "/") }
      .filter {
        let parts = $0.split(separator: "/")
        return !parts.isEmpty && parts.count <= 2 && !parts.contains("..")
          && !$0.hasPrefix("/") && parts.last?.lowercased() == fileName
      }
      .sorted {
        let lhs = $0.split(separator: "/").count
        let rhs = $1.split(separator: "/").count
        return lhs == rhs ? $0 < $1 : lhs < rhs
      }
    if let first = candidates.first { return first }
    return nil
  }

  static func manifestURL(for discovered: DiscoveredGame) -> URL {
    switch discovered.source {
    case .directory:
      URL(fileURLWithPath: discovered.path)
        .appendingPathComponent(fileName)
    case .pfsArchive:
      URL(fileURLWithPath: "\(discovered.path).\(fileName)")
    }
  }

  @discardableResult
  static func save(_ entry: GameEntry) throws -> URL {
    let discovered = DiscoveredGame(name: entry.name, path: entry.path, source: entry.source)
    let url = manifestURL(for: discovered)
    let manifest = GameManifest(
      name: entry.displayNameOrName,
      vndbID: entry.vndbId,
      engine: entry.engine.rawValue,
      translationEnabled: entry.translationEnabled,
      translationPatchPath: entry.translationPatchPath,
      environmentPatchEnabled: entry.environmentPatchEnabled,
      fontOverride: entry.fontOverridePath,
      reportedOs: entry.reportedOs,
      runtimePlatform: entry.runtimePlatform,
      krkrEntryXp3: entry.krkrEntryXp3,
      inputGate: entry.inputGate
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(manifest).write(to: url, options: .atomic)
    return url
  }

  static func loadEntrySettings(_ entry: GameEntry) -> GameEntry {
    let discovered = DiscoveredGame(
      name: entry.name,
      path: entry.path,
      source: entry.source
    )
    guard let manifest = load(for: discovered) else { return entry }
    var updated = entry
    if let engine = manifest.engine {
      updated.engine = GameEngineKind(id: engine)
    }
    if let value = manifest.name, !value.isEmpty {
      updated.name = value
    }
    if let value = manifest.translationEnabled {
      updated.translationEnabled = value
    }
    if let value = manifest.translationPatchPath {
      updated.translationPatchPath = value
    }
    if let value = manifest.environmentPatchEnabled {
      updated.environmentPatchEnabled = value
    }
    if let value = manifest.inputGate {
      updated.inputGate = value
    }
    if let value = manifest.vndbID {
      updated.vndbId = value
    }
    if let value = manifest.fontOverride {
      updated.fontOverridePath = value
    }
    if let value = manifest.reportedOs {
      updated.reportedOs = value
    }
    if let value = manifest.runtimePlatform, !value.isEmpty {
      updated.runtimePlatform = value.uppercased()
    }
    if let value = manifest.krkrEntryXp3 {
      updated.krkrEntryXp3 = value
    }
    updated.manifestPath = manifestURL(for: discovered).path
    return updated
  }

  private static func archives(for path: String) -> [String] {
    let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else {
      return [path]
    }
    return files.filter { url in
      guard (try? url.resourceValues(forKeys: [.isRegularFileKey])
        .isRegularFile) == true else {
        return false
      }
      let name = url.lastPathComponent.lowercased()
      return name.hasSuffix(".pfs")
        || name.range(
          of: #"\.pfs\.\d{3}$"#,
          options: .regularExpression
        ) != nil
    }
    .map(\.path)
    .sorted()
  }
}
