import Foundation

enum AppDataPaths {
  private static let managedDirectories = [
    "Games",
    "Saves",
    "covers",
    "translations",
    "screenshots",
    "exports",
  ]

  static var root: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  static var games: URL {
    root.appendingPathComponent("Games", isDirectory: true)
  }

  static var saves: URL {
    root.appendingPathComponent("Saves", isDirectory: true)
  }

  static var covers: URL {
    root.appendingPathComponent("covers", isDirectory: true)
  }

  static var translations: URL {
    root.appendingPathComponent("translations", isDirectory: true)
  }

  static var screenshots: URL {
    root.appendingPathComponent("screenshots", isDirectory: true)
  }

  static var exports: URL {
    root.appendingPathComponent("exports", isDirectory: true)
  }

  static func displayPath(for path: String) -> String {
    let rootPath = root.standardizedFileURL.path
    let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
    let prefix = rootPath == "/" ? rootPath : "\(rootPath)/"
    guard normalized.hasPrefix(prefix) else { return path }
    return String(normalized.dropFirst(prefix.count))
  }

  @discardableResult
  static func ensureInitialized() throws -> URL {
    let fileManager = FileManager.default
    try migrateLegacyLayout(fileManager: fileManager)
    for directory in [
      root,
      games,
      saves,
      covers,
      translations,
      screenshots,
      exports,
    ] {
      try fileManager.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
    }
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    var gamesURL = games
    try? gamesURL.setResourceValues(values)
    return root
  }

  private static func migrateLegacyLayout(fileManager: FileManager) throws {
    let legacyRoot = root.appendingPathComponent("Art3m1s", isDirectory: true)
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(
      atPath: legacyRoot.path,
      isDirectory: &isDirectory
    ), isDirectory.boolValue else {
      return
    }

    for name in managedDirectories {
      let source = legacyRoot.appendingPathComponent(name, isDirectory: true)
      guard fileManager.fileExists(atPath: source.path) else { continue }
      let destination = root.appendingPathComponent(name, isDirectory: true)
      if fileManager.fileExists(atPath: destination.path) {
        try mergeDirectory(
          source,
          into: destination,
          fileManager: fileManager
        )
      } else {
        try fileManager.moveItem(at: source, to: destination)
      }
    }

    let remaining = try remainingItems(in: legacyRoot, fileManager: fileManager)
    if remaining.isEmpty {
      try? fileManager.removeItem(at: legacyRoot)
    }
  }

  private static func mergeDirectory(
    _ source: URL,
    into destination: URL,
    fileManager: FileManager
  ) throws {
    try fileManager.createDirectory(
      at: destination,
      withIntermediateDirectories: true
    )
    for item in try fileManager.contentsOfDirectory(
      at: source,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) {
      let target = destination.appendingPathComponent(item.lastPathComponent)
      guard !fileManager.fileExists(atPath: target.path) else {
        let isSourceDirectory = try item.resourceValues(
          forKeys: [.isDirectoryKey]
        ).isDirectory == true
        let isTargetDirectory = (
          try? target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
        ) == true
        if isSourceDirectory, isTargetDirectory {
          try mergeDirectory(item, into: target, fileManager: fileManager)
        }
        continue
      }
      try fileManager.moveItem(at: item, to: target)
    }
    let remaining = try remainingItems(in: source, fileManager: fileManager)
    if remaining.isEmpty {
      try? fileManager.removeItem(at: source)
    }
  }

  private static func remainingItems(
    in directory: URL,
    fileManager: FileManager
  ) throws -> [String] {
    try fileManager.contentsOfDirectory(atPath: directory.path)
      .filter { $0 != ".DS_Store" }
  }
}
