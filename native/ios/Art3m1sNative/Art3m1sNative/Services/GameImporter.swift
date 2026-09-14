import Foundation

struct DiscoveredGame: Hashable, Sendable {
  let name: String
  let path: String
  let source: GameSource
}

enum GameImporter {
  enum ImportError: LocalizedError {
    case sourceContainsGames
    case sourceInsideGames

    var errorDescription: String? {
      switch self {
      case .sourceContainsGames:
        return "不能导入 App 自己的 Documents 或已管理的数据目录。"
      case .sourceInsideGames:
        return "不能把 Games 目录中的文件夹再次导入 Games。"
      }
    }
  }

  static func discover(in directory: URL) -> [DiscoveredGame] {
    let projects = discoverProjects(in: directory)
    let projectPaths = Set(projects.map(normalizePath))
    let archives = discoverPFSArchives(in: directory).filter { archive in
      !projectPaths.contains { project in
        normalizePath(archive).hasPrefix("\(project)/")
      }
    }

    return (
      projects.map {
        DiscoveredGame(
          name: URL(fileURLWithPath: $0).lastPathComponent,
          path: $0,
          source: .directory
        )
      } + archives.map {
        DiscoveredGame(
          name: baseName(forPFS: $0),
          path: $0,
          source: .pfsArchive
        )
      }
    ).sorted {
      $0.name.localizedStandardCompare($1.name) == .orderedAscending
    }
  }

  static func discoverProjects(in directory: URL) -> [String] {
    var found: [String] = []
    visitProjectDirectories(directory, found: &found)
    return found.sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }
  }

  static func discoverPFSArchives(in directory: URL) -> [String] {
    let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
    guard let enumerator = FileManager.default.enumerator(
      at: directory,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    var found: [String] = []
    for case let url as URL in enumerator {
      guard (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true
      else {
        continue
      }
      let name = url.lastPathComponent.lowercased()
      guard name.hasSuffix(".pfs"),
            name.range(
              of: #"\.pfs\.\d{3}$"#,
              options: .regularExpression
            ) == nil
      else {
        continue
      }
      found.append(url.path)
    }
    return found.sorted {
      $0.localizedStandardCompare($1) == .orderedAscending
    }
  }

  static func detectEngine(in projectPath: String) -> GameEngineKind {
    let directory = URL(fileURLWithPath: projectPath)
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else {
      return .art3m1s
    }

    var hasSystemINI = false
    var hasHCB = false
    var hasDataXP3 = false
    var hasStartupTJS = false
    var rootXP3Count = 0

    for url in urls where isRegularFile(url) {
      switch url.lastPathComponent.lowercased() {
      case "system.ini":
        hasSystemINI = true
      case let name where name.hasSuffix(".hcb"):
        hasHCB = true
      case "data.xp3":
        hasDataXP3 = true
      case "startup.tjs":
        hasStartupTJS = true
      case let name where name.hasSuffix(".xp3"):
        rootXP3Count += 1
      default:
        break
      }
    }

    if hasSystemINI { return .art3m1s }
    if hasHCB { return .rfvp }
    if hasDataXP3 || hasStartupTJS || rootXP3Count == 1 { return .krkr }
    return .art3m1s
  }

  static func normalizePath(_ path: String) -> String {
    var normalized = path.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\", with: "/")
    while normalized.count > 1 && normalized.hasSuffix("/") {
      normalized.removeLast()
    }
    if normalized.hasPrefix("/private/var/") || normalized.hasPrefix("/private/tmp/") {
      normalized.removeFirst("/private".count)
    }
    return normalized
  }

  static func isSamePath(_ lhs: String, _ rhs: String) -> Bool {
    normalizePath(lhs) == normalizePath(rhs)
  }

  static func copyIntoGamesDirectory(_ source: URL) throws -> URL {
    let accessing = source.startAccessingSecurityScopedResource()
    defer {
      if accessing {
        source.stopAccessingSecurityScopedResource()
      }
    }

    let sourceURL = source.standardizedFileURL.resolvingSymlinksInPath()
    let gamesURL = AppDataPaths.games.standardizedFileURL.resolvingSymlinksInPath()

    if sourceURL.path == gamesURL.path
      || isDescendant(gamesURL, of: sourceURL) {
      throw ImportError.sourceContainsGames
    }
    if isDescendant(sourceURL, of: gamesURL) {
      throw ImportError.sourceInsideGames
    }

    let destination = AppDataPaths.games.appendingPathComponent(
      source.lastPathComponent,
      isDirectory: true
    )
    if FileManager.default.fileExists(atPath: destination.path) {
      return destination
    }

    try FileManager.default.copyItem(at: source, to: destination)
    return destination
  }

  private static func visitProjectDirectories(
    _ directory: URL,
    found: inout [String]
  ) {
    guard let urls = try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else {
      return
    }

    var subdirectories: [URL] = []
    var hasSystemINI = false
    var hasHCB = false
    var hasDataXP3 = false
    var hasStartupTJS = false
    var rootXP3Count = 0

    for url in urls {
      if isDirectory(url) {
        subdirectories.append(url)
        continue
      }
      guard isRegularFile(url) else { continue }
      switch url.lastPathComponent.lowercased() {
      case "system.ini":
        hasSystemINI = true
      case let name where name.hasSuffix(".hcb"):
        hasHCB = true
      case "data.xp3":
        hasDataXP3 = true
      case "startup.tjs":
        hasStartupTJS = true
      case let name where name.hasSuffix(".xp3"):
        rootXP3Count += 1
      default:
        break
      }
    }

    if hasSystemINI || hasHCB || hasDataXP3 || hasStartupTJS || rootXP3Count == 1 {
      found.append(directory.path)
      return
    }
    for subdirectory in subdirectories {
      visitProjectDirectories(subdirectory, found: &found)
    }
  }

  private static func baseName(forPFS path: String) -> String {
    URL(fileURLWithPath: path)
      .deletingPathExtension()
      .lastPathComponent
  }

  private static func isRegularFile(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
  }

  private static func isDirectory(_ url: URL) -> Bool {
    (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
  }

  private static func isDescendant(_ url: URL, of ancestor: URL) -> Bool {
    let childPath = url.standardizedFileURL.resolvingSymlinksInPath().path
    let ancestorPath = ancestor.standardizedFileURL.resolvingSymlinksInPath().path
    let base = ancestorPath == "/" ? ancestorPath : "\(ancestorPath)/"
    return childPath != ancestorPath && childPath.hasPrefix(base)
  }
}
