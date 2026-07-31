import Flutter
import CoreVideo
import IOSurface
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var pfsPickResult: FlutterResult?
  private var libraryPanelResult: FlutterResult?
  private var sharedTextureRegistry: FlutterTextureRegistry?
  private var sharedTexture: Art3m1sSharedTexture?
  private var sharedTextureId: Int64?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    sharedTextureRegistry = engineBridge.applicationRegistrar.textures()

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

    let textureChannel = FlutterMethodChannel(
      name: "moe.alphaly.art3m1s/shared_texture",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    textureChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "APP_DELEGATE_RELEASED", message: "AppDelegate was released", details: nil))
        return
      }
      switch call.method {
      case "create":
        guard
          let args = call.arguments as? [String: Any],
          let width = args["width"] as? Int,
          let height = args["height"] as? Int,
          width > 0,
          height > 0
        else {
          result(FlutterError(code: "INVALID_SIZE", message: "Invalid shared texture size", details: nil))
          return
        }
        do {
          result(try self.createSharedTexture(width: width, height: height))
        } catch {
          result(FlutterError(code: "CREATE_FAILED", message: error.localizedDescription, details: nil))
        }
      case "frameAvailable":
        if let textureId = self.sharedTextureId {
          self.sharedTextureRegistry?.textureFrameAvailable(textureId)
        }
        result(nil)
      case "release":
        self.releaseSharedTexture()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func createSharedTexture(width: Int, height: Int) throws -> [String: Int64] {
    releaseSharedTexture()
    guard let registry = sharedTextureRegistry else {
      throw NSError(domain: "Art3m1s", code: 20, userInfo: [
        NSLocalizedDescriptionKey: "Flutter texture registry is unavailable"
      ])
    }
    let texture = try Art3m1sSharedTexture(width: width, height: height)
    let textureId = registry.register(texture)
    guard textureId != 0 else {
      throw NSError(domain: "Art3m1s", code: 21, userInfo: [
        NSLocalizedDescriptionKey: "Flutter rejected the shared texture"
      ])
    }
    sharedTexture = texture
    sharedTextureId = textureId
    return ["textureId": textureId, "kind": 2, "handle": texture.ioSurfaceAddress]
  }

  private func releaseSharedTexture() {
    if let textureId = sharedTextureId {
      sharedTextureRegistry?.unregisterTexture(textureId)
    }
    sharedTextureId = nil
    sharedTexture = nil
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

  private func copySelectedPfsFilesToSandbox(_ urls: [URL]) throws -> [String] {
    NSLog("[Art3m1s] PFS import selected \(urls.count) files")

    let files = try urls.map { url in
      SelectedPfsFile(url: url, name: url.lastPathComponent, size: try fileSize(url))
    }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

    let bases = files.filter { Self.isBasePfsName($0.name) }
    guard !bases.isEmpty else {
      throw NSError(domain: "Art3m1s", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "请选择 base .pfs 文件"
      ])
    }

    let duplicateBaseNames = Dictionary(grouping: bases) { $0.name.lowercased() }
      .filter { $0.value.count > 1 }
      .keys
    guard duplicateBaseNames.isEmpty else {
      throw NSError(domain: "Art3m1s", code: 2, userInfo: [
        NSLocalizedDescriptionKey: "一次不能导入多个同名 PFS：\(duplicateBaseNames.sorted().joined(separator: ", "))"
      ])
    }
    let orphanVolumes = files.filter { file in
      Self.isPfsVolumeName(file.name)
        && !bases.contains { Self.isPfsVolumeName(file.name, forBase: $0.name) }
    }
    guard orphanVolumes.isEmpty else {
      throw NSError(domain: "Art3m1s", code: 3, userInfo: [
        NSLocalizedDescriptionKey: "分卷缺少对应的 base .pfs：\(orphanVolumes.map(\.name).joined(separator: ", "))"
      ])
    }

    let fm = FileManager.default
    let gamesDir = try appGamesURL()
    try fm.createDirectory(at: gamesDir, withIntermediateDirectories: true)
    var importedPaths: [String] = []

    for base in bases {
      let volumes = files.filter {
        Self.isPfsVolumeName($0.name, forBase: base.name)
      }
      let gameFiles = [base] + volumes
      let totalSize = gameFiles.reduce(0) { $0 + $1.size }
      let gameId = Self.computeGameId(name: base.name, size: totalSize)
      let targetDir = gamesDir.appendingPathComponent(gameId, isDirectory: true)
      let importedBase = targetDir.appendingPathComponent(base.name).path

      if try isComplete(files: gameFiles, targetDir: targetDir) {
        importedPaths.append(importedBase)
        continue
      }

      if fm.fileExists(atPath: targetDir.path) {
        try fm.removeItem(at: targetDir)
      }
      try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)

      for file in gameFiles {
        let dest = targetDir.appendingPathComponent(file.name, isDirectory: false)
        NSLog("[Art3m1s] PFS import copy \(file.name)")
        try copyFile(from: file.url, to: dest)
      }
      importedPaths.append(importedBase)
    }

    NSLog("[Art3m1s] PFS import completed: \(importedPaths.joined(separator: ", "))")
    return importedPaths
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
    let expectedNames = Set(files.map(\.name))
    let existingNames = Set(
      try fm.contentsOfDirectory(
        at: targetDir,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
      ).filter {
        (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
      }.map(\.lastPathComponent)
    )
    guard existingNames == expectedNames else { return false }
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

  private static func isPfsVolumeName(_ name: String, forBase base: String? = nil) -> Bool {
    let lower = name.lowercased()
    guard lower.range(of: #"(?i)\.pfs\.\d{3}$"#, options: .regularExpression) != nil else {
      return false
    }
    guard let base else { return true }
    return lower.hasPrefix("\(displayName(forPfs: base).lowercased()).pfs.")
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

private final class Art3m1sSharedTexture: NSObject, FlutterTexture {
  let pixelBuffer: CVPixelBuffer
  let ioSurfaceAddress: Int64

  init(width: Int, height: Int) throws {
    let attributes: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
      kCVPixelBufferMetalCompatibilityKey: true,
      kCVPixelBufferOpenGLESCompatibilityKey: true,
    ]
    var buffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attributes as CFDictionary,
      &buffer
    )
    guard status == kCVReturnSuccess, let buffer else {
      throw NSError(domain: "Art3m1s", code: Int(status), userInfo: [
        NSLocalizedDescriptionKey: "CVPixelBufferCreate failed: \(status)"
      ])
    }
    guard let surface = CVPixelBufferGetIOSurface(buffer) else {
      throw NSError(domain: "Art3m1s", code: 22, userInfo: [
        NSLocalizedDescriptionKey: "CVPixelBuffer has no IOSurface"
      ])
    }
    pixelBuffer = buffer
    let surfacePointer = unsafeBitCast(surface, to: UnsafeMutableRawPointer.self)
    ioSurfaceAddress = Int64(Int(bitPattern: surfacePointer))
    super.init()
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    Unmanaged.passRetained(pixelBuffer)
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
