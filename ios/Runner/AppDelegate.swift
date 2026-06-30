import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var pfsPickResult: FlutterResult?
  private var libraryPanelResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "moe.alphaly.art3m1s/native_ptrs",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "APP_DELEGATE_RELEASED", message: "AppDelegate was released", details: nil))
        return
      }
      switch call.method {
      case "pickPfsFilesAndCopy":
        self.pickPfsFilesAndCopy(result: result)
      case "showIosLibraryManager":
        self.showIosLibraryManager(result: result)
      case "prepareIosAppFolders":
        do {
          let root = try self.ensureAppFolders()
          result(root.path)
        } catch {
          result(FlutterError(code: "PREPARE_FOLDERS_FAILED", message: error.localizedDescription, details: nil))
        }
      case "scanIosAppGamesFolder":
        do {
          result(try self.scanIosAppGamesFolder())
        } catch {
          result(FlutterError(code: "SCAN_GAMES_FAILED", message: error.localizedDescription, details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func pickPfsFilesAndCopy(result: @escaping FlutterResult) {
    guard pfsPickResult == nil else {
      result(FlutterError(code: "PICK_IN_PROGRESS", message: "A picker is already active", details: nil))
      return
    }
    guard let presenter = topViewController() else {
      result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "No active view controller", details: nil))
      return
    }

    pfsPickResult = result
    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
    } else {
      picker = UIDocumentPickerViewController(documentTypes: ["public.data"], in: .import)
    }
    picker.delegate = self
    picker.allowsMultipleSelection = true
    presenter.present(picker, animated: true)
  }

  private func showIosLibraryManager(result: @escaping FlutterResult) {
    guard libraryPanelResult == nil else {
      result(FlutterError(code: "PANEL_IN_PROGRESS", message: "A library panel is already active", details: nil))
      return
    }
    guard let presenter = topViewController() else {
      result(FlutterError(code: "NO_VIEW_CONTROLLER", message: "No active view controller", details: nil))
      return
    }

    do {
      _ = try ensureAppFolders()
    } catch {
      result(FlutterError(code: "PREPARE_FOLDERS_FAILED", message: error.localizedDescription, details: nil))
      return
    }

    libraryPanelResult = result
    let controller = IosLibraryManagerViewController()
    controller.onAction = { [weak self, weak controller] action in
      controller?.dismiss(animated: true) {
        self?.finishLibraryPanel(action)
      }
    }
    controller.modalPresentationStyle = .pageSheet
    if #available(iOS 15.0, *), let sheet = controller.sheetPresentationController {
      sheet.detents = [.medium()]
      sheet.prefersGrabberVisible = true
    }
    presenter.present(controller, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishPfsPick(
      FlutterError(code: "PICK_CANCELLED", message: "User cancelled file picking", details: nil)
    )
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard !urls.isEmpty else {
      documentPickerWasCancelled(controller)
      return
    }

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      guard let self else { return }
      do {
        let path = try self.copySelectedPfsFilesToSandbox(urls)
        DispatchQueue.main.async { self.finishPfsPick(path) }
      } catch {
        DispatchQueue.main.async {
          self.finishPfsPick(
            FlutterError(code: "PFS_IMPORT_FAILED", message: error.localizedDescription, details: nil)
          )
        }
      }
    }
  }

  private func finishPfsPick(_ value: Any?) {
    let result = pfsPickResult
    pfsPickResult = nil
    result?(value)
  }

  private func finishLibraryPanel(_ value: Any?) {
    let result = libraryPanelResult
    libraryPanelResult = nil
    result?(value)
  }

  private func copySelectedPfsFilesToSandbox(_ urls: [URL]) throws -> String {
    NSLog("[Art3m1s] PFS import selected \(urls.count) files")

    let files = try urls.map { url in
      SelectedPfsFile(url: url, name: url.lastPathComponent, size: try fileSize(url))
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    guard let base = files.first(where: { Self.isBasePfsName($0.name) }) else {
      throw NSError(domain: "Art3m1s", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "请选择 base .pfs 文件"
      ])
    }

    let totalSize = files.reduce(0) { $0 + $1.size }
    let gameId = Self.computeGameId(name: base.name, size: totalSize)
    let fm = FileManager.default
    let gamesDir = try appGamesURL()
    let targetDir = gamesDir.appendingPathComponent(gameId, isDirectory: true)
    try fm.createDirectory(at: gamesDir, withIntermediateDirectories: true)

    if try isComplete(files: files, targetDir: targetDir) {
      return targetDir.appendingPathComponent(base.name).path
    }

    if fm.fileExists(atPath: targetDir.path) {
      try fm.removeItem(at: targetDir)
    }
    try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

    for file in files {
      let dest = targetDir.appendingPathComponent(file.name, isDirectory: false)
      NSLog("[Art3m1s] PFS import copy \(file.name)")
      try copyFile(from: file.url, to: dest)
    }

    NSLog("[Art3m1s] PFS import completed: \(targetDir.appendingPathComponent(base.name).path)")
    return targetDir.appendingPathComponent(base.name).path
  }

  private func ensureAppFolders() throws -> URL {
    let fm = FileManager.default
    let root = try appRootURL()
    let games = root.appendingPathComponent("Games", isDirectory: true)
    let saves = root.appendingPathComponent("Saves", isDirectory: true)
    try fm.createDirectory(at: games, withIntermediateDirectories: true)
    try fm.createDirectory(at: saves, withIntermediateDirectories: true)
    try excludeFromBackup(games)
    return root
  }

  private func appRootURL() throws -> URL {
    try FileManager.default
      .url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
      .appendingPathComponent("Art3m1s", isDirectory: true)
  }

  private func appGamesURL() throws -> URL {
    try ensureAppFolders().appendingPathComponent("Games", isDirectory: true)
  }

  private func scanIosAppGamesFolder() throws -> [[String: String]] {
    let games = try appGamesURL()
    let fm = FileManager.default
    guard let enumerator = fm.enumerator(
      at: games,
      includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    var seen = Set<String>()
    var found: [[String: String]] = []
    for case let url as URL in enumerator {
      let name = url.lastPathComponent
      if name.caseInsensitiveCompare("system.ini") == .orderedSame {
        let projectDir = url.deletingLastPathComponent()
        if seen.insert(projectDir.path).inserted {
          found.append([
            "name": projectDir.lastPathComponent,
            "path": projectDir.path,
            "source": "directory",
          ])
        }
      } else if Self.isBasePfsName(name) {
        if seen.insert(url.path).inserted {
          found.append([
            "name": Self.displayName(forPfs: name),
            "path": url.path,
            "source": "pfsArchive",
          ])
        }
      }
    }

    return found.sorted {
      ($0["name"] ?? "").localizedStandardCompare($1["name"] ?? "") == .orderedAscending
    }
  }

  private func excludeFromBackup(_ url: URL) throws {
    var mutableURL = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try mutableURL.setResourceValues(values)
  }

  private func fileSize(_ url: URL) throws -> Int64 {
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attrs[.size] as? NSNumber)?.int64Value ?? 0
  }

  private func copyFile(from source: URL, to dest: URL) throws {
    if FileManager.default.fileExists(atPath: dest.path) {
      try FileManager.default.removeItem(at: dest)
    }
    try FileManager.default.copyItem(at: source, to: dest)
  }

  private func isComplete(files: [SelectedPfsFile], targetDir: URL) throws -> Bool {
    let fm = FileManager.default
    guard fm.fileExists(atPath: targetDir.path) else { return false }
    for file in files {
      let dest = targetDir.appendingPathComponent(file.name)
      guard fm.fileExists(atPath: dest.path) else { return false }
      let attrs = try fm.attributesOfItem(atPath: dest.path)
      let size = (attrs[.size] as? NSNumber)?.int64Value ?? -1
      if size != file.size { return false }
    }
    return true
  }

  private func topViewController() -> UIViewController? {
    let root = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)?
      .rootViewController
    return topViewController(from: root)
  }

  private func topViewController(from controller: UIViewController?) -> UIViewController? {
    if let presented = controller?.presentedViewController {
      return topViewController(from: presented)
    }
    if let nav = controller as? UINavigationController {
      return topViewController(from: nav.visibleViewController)
    }
    if let tab = controller as? UITabBarController {
      return topViewController(from: tab.selectedViewController)
    }
    return controller
  }

  private static func isBasePfsName(_ name: String) -> Bool {
    let lower = name.lowercased()
    return lower.hasSuffix(".pfs") && lower.range(of: #"(?i)\.pfs\.\d{3}$"#, options: .regularExpression) == nil
  }

  private static func computeGameId(name: String, size: Int64) -> String {
    let baseName = name.range(of: #"(?i)\.pfs$"#, options: .regularExpression)
      .map { String(name[..<$0.lowerBound]) } ?? name
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in "\(baseName):\(size)".utf8 {
      hash ^= UInt64(byte)
      hash = hash &* 0x100000001b3
    }
    return "\(baseName)_\(String(hash, radix: 16))"
  }

  private static func displayName(forPfs name: String) -> String {
    name.range(of: #"(?i)\.pfs$"#, options: .regularExpression)
      .map { String(name[..<$0.lowerBound]) } ?? name
  }
}

private struct SelectedPfsFile {
  let url: URL
  let name: String
  let size: Int64
}

private final class IosLibraryManagerViewController: UIViewController {
  var onAction: ((String?) -> Void)?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .clear

    let effectView = UIVisualEffectView(effect: Self.makePanelEffect())
    effectView.translatesAutoresizingMaskIntoConstraints = false
    effectView.layer.cornerRadius = 26
    effectView.layer.cornerCurve = .continuous
    effectView.clipsToBounds = true

    let title = UILabel()
    title.text = "Art3m1s 文件夹"
    title.font = .preferredFont(forTextStyle: .title2)
    title.adjustsFontForContentSizeCategory = true

    let message = UILabel()
    message.text = "在 Files app 中把游戏目录或 PFS 分卷放入 Art3m1s/Games。存档会写入 Art3m1s/Saves。"
    message.font = .preferredFont(forTextStyle: .body)
    message.textColor = .secondaryLabel
    message.numberOfLines = 0
    message.adjustsFontForContentSizeCategory = true

    let scanButton = makeButton(title: "扫描 App 文件夹", image: "folder.badge.gearshape") { [weak self] in
      self?.onAction?("scan")
    }
    let pickerButton = makeButton(title: "选择 PFS 文件", image: "archivebox") { [weak self] in
      self?.onAction?("pickPfs")
    }
    let closeButton = makeButton(title: "关闭", image: "xmark") { [weak self] in
      self?.onAction?(nil)
    }

    let stack = UIStackView(arrangedSubviews: [title, message, scanButton, pickerButton, closeButton])
    stack.axis = .vertical
    stack.spacing = 14
    stack.translatesAutoresizingMaskIntoConstraints = false

    view.addSubview(effectView)
    effectView.contentView.addSubview(stack)

    NSLayoutConstraint.activate([
      effectView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
      effectView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
      effectView.centerYAnchor.constraint(equalTo: view.centerYAnchor),

      stack.leadingAnchor.constraint(equalTo: effectView.contentView.leadingAnchor, constant: 22),
      stack.trailingAnchor.constraint(equalTo: effectView.contentView.trailingAnchor, constant: -22),
      stack.topAnchor.constraint(equalTo: effectView.contentView.topAnchor, constant: 22),
      stack.bottomAnchor.constraint(equalTo: effectView.contentView.bottomAnchor, constant: -22),
    ])
  }

  private func makeButton(title: String, image: String, action: @escaping () -> Void) -> UIButton {
    let button = ClosureButton(type: .system)
    button.setTitle(title, for: .normal)
    button.setImage(UIImage(systemName: image), for: .normal)
    button.tintColor = .white
    button.backgroundColor = .systemBlue
    button.contentEdgeInsets = UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16)
    button.imageEdgeInsets = UIEdgeInsets(top: 0, left: -4, bottom: 0, right: 8)
    button.titleLabel?.font = .preferredFont(forTextStyle: .headline)
    button.layer.cornerRadius = 14
    button.layer.cornerCurve = .continuous
    button.onTap = action
    button.addTarget(button, action: #selector(ClosureButton.invoke), for: .touchUpInside)
    button.heightAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    return button
  }

  private static func makePanelEffect() -> UIVisualEffect {
    if #available(iOS 26.0, *) {
      for className in ["UIGlassEffect", "UIKit.UIGlassEffect"] {
        if let glassClass = NSClassFromString(className) as? NSObject.Type,
           let glassEffect = glassClass.init() as? UIVisualEffect {
          return glassEffect
        }
      }
    }
    return UIBlurEffect(style: .systemMaterial)
  }
}

private final class ClosureButton: UIButton {
  var onTap: (() -> Void)?

  @objc func invoke() {
    onTap?()
  }
}
