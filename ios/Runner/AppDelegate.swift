import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, UIDocumentPickerDelegate {
  private var pfsPickResult: FlutterResult?

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
      guard call.method == "pickPfsFilesAndCopy" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.pickPfsFilesAndCopy(result: result)
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
    let appSupport = try fm.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let gamesDir = appSupport.appendingPathComponent("games", isDirectory: true)
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
}

private struct SelectedPfsFile {
  let url: URL
  let name: String
  let size: Int64
}
