import Foundation

struct GameManifest: Decodable, Sendable {
  static let fileName = "art3m1s.json"
  static let defaultRuntimePlatform = "WINDOWS"

  var name: String?
  var vndbID: String?
  var engine: String?
  var translationEnabled: Bool?
  var translationPatchPath: String?
  var environmentPatchEnabled: Bool?
  var experimentalElunaEnabled: Bool?
  var fontOverride: String?
  var reportedOs: String?
  var runtimePlatform: String?
  var inputGate: InputGatePolicy?

  enum CodingKeys: String, CodingKey {
    case name
    case vndbID = "vndbId"
    case engine
    case translationEnabled
    case translationPatchPath
    case environmentPatchEnabled
    case experimentalElunaEnabled
    case fontOverride
    case reportedOs
    case runtimePlatform
    case inputGate
  }

  static func load(for discovered: DiscoveredGame) -> GameManifest? {
    switch discovered.source {
    case .directory:
      let root = URL(fileURLWithPath: discovered.path)
      let candidates = [
        root.appendingPathComponent(fileName),
        root.appendingPathComponent(fileName.lowercased()),
      ]
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
    for raw in entries {
      let normalized = raw.replacingOccurrences(of: "\\", with: "/")
      let parts = normalized.split(separator: "/")
      guard parts.count <= 2,
            parts.last?.lowercased() == fileName.lowercased()
      else {
        continue
      }
      return normalized
    }
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
    if let value = manifest.experimentalElunaEnabled {
      updated.experimentalElunaEnabled = value
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
