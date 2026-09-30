import Foundation

/// Artemis 项目资源视图：解包目录 > 大 id 分卷 > 小 id 分卷。
///
/// 与 Dart 侧 `ProjectVfs` 保持同一套优先级。core 侧挂载 PFS 时会自动把归档
/// 父目录当作 sidecar 覆盖层，并在多个归档之间让后挂载者胜出，因此混合包
/// （散装 `system.ini` + `root.pfs` 分卷）在引擎内部也按同一顺序解析。
struct ProjectVFS {
  /// 散装文件层：解包工程根目录，或归档所在目录。
  let directoryRoot: URL
  /// 同目录内的 PFS 候选，按路径升序；查找时反向遍历（大 id 优先）。
  let archives: [String]
  /// 归档条目名使用的字符集。
  let encoding: String

  init(game: GameEntry, encoding: String) {
    self.encoding = encoding
    switch game.source {
    case .directory:
      let root = URL(fileURLWithPath: game.path, isDirectory: true)
      directoryRoot = root
      archives = Self.archiveCandidates(in: root)
    case .pfsArchive:
      let entry = URL(fileURLWithPath: game.path)
      let parent = entry.deletingLastPathComponent()
      directoryRoot = parent
      let candidates = Self.archiveCandidates(in: parent)
      archives = candidates.isEmpty ? [game.path] : candidates
    }
  }

  var hasArchives: Bool { !archives.isEmpty }

  /// 交给 core `resources_mount_pfs` 的入口归档；纯解包目录为 nil。
  var archiveMountEntry: String? {
    guard hasArchives else { return nil }
    return archives.first { $0.lowercased().hasSuffix(".pfs") } ?? archives[0]
  }

  /// 按 VFS 优先级读取；路径不合法或未命中返回 nil。
  func read(_ path: String) -> Data? {
    guard let relative = Self.normalize(path) else { return nil }
    if let loose = Self.readFile(at: directoryRoot, relative: relative) {
      return loose
    }
    for archive in archives.reversed() {
      if let data = try? PFSReader.read(
        archivePath: archive,
        entryPath: relative,
        encoding: encoding
      ) {
        return data
      }
    }
    return nil
  }

  /// 脚本路径归一化成 `a/b/c`；含 `..`、盘符或空路径视为非法。
  static func normalize(_ path: String) -> String? {
    let parts = path
      .replacingOccurrences(of: "\\", with: "/")
      .split(separator: "/", omittingEmptySubsequences: true)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty && $0 != "." }
    guard !parts.isEmpty, !parts.contains("..") else { return nil }
    guard !parts.contains(where: { $0.contains(":") }) else { return nil }
    return parts.joined(separator: "/")
  }

  private static func readFile(at root: URL, relative: String) -> Data? {
    let url = root.appendingPathComponent(relative).standardizedFileURL
    let rootPath = root.standardizedFileURL.path
    guard url.path.hasPrefix(rootPath + "/") else { return nil }
    return try? Data(contentsOf: url)
  }

  /// 目录内的 `.pfs` 与 `.pfs.NNN` 候选（隐藏文件与 AppleDouble 已跳过）。
  static func archiveCandidates(in directory: URL) -> [String] {
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isRegularFileKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }
    return files.filter { url in
      guard (try? url.resourceValues(forKeys: [.isRegularFileKey])
        .isRegularFile) == true else {
        return false
      }
      let name = url.lastPathComponent.lowercased()
      guard !name.hasPrefix("._") else { return false }
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
