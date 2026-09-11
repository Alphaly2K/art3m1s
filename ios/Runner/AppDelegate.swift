import Flutter
import CoreVideo
import IOSurface
import Metal
import UIKit

@objc(Art3m1sRuntimeDelegate)
class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
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
    // Flutter 3.44 assigns external texture IDs from zero. The public header's
    // historical "0 means failure" comment no longer matches the engine.
    sharedTexture = texture
    sharedTextureId = textureId
    return [
      "textureId": textureId,
      "kind": 2,
      "handle": texture.ioSurfaceAddress,
      "fallbackKind": 3,
      "fallbackHandle": texture.metalTextureAddress,
    ]
  }

  private func releaseSharedTexture() {
    if let textureId = sharedTextureId {
      sharedTextureRegistry?.unregisterTexture(textureId)
    }
    sharedTextureId = nil
    sharedTexture = nil
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

  private static func isBasePfsName(_ name: String) -> Bool {
    let lower = name.lowercased()
    return lower.hasSuffix(".pfs") && lower.range(of: #"(?i)\.pfs\.\d{3}$"#, options: .regularExpression) == nil
  }

  private static func displayName(forPfs name: String) -> String {
    name.range(of: #"(?i)\.pfs$"#, options: .regularExpression)
      .map { String(name[..<$0.lowerBound]) } ?? name
  }
}

private final class Art3m1sSharedTexture: NSObject, FlutterTexture {
  let pixelBuffer: CVPixelBuffer
  let ioSurfaceAddress: Int64
  let metalTextureAddress: Int64
  private let metalTextureCache: CVMetalTextureCache
  private let cvMetalTexture: CVMetalTexture
  private let metalTexture: MTLTexture

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
      throw NSError(domain: "Art3m1s", code: 23, userInfo: [
        NSLocalizedDescriptionKey: "CVPixelBuffer has no IOSurface"
      ])
    }
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw NSError(domain: "Art3m1s", code: 22, userInfo: [
        NSLocalizedDescriptionKey: "Metal device is unavailable"
      ])
    }
    var cache: CVMetalTextureCache?
    let cacheStatus = CVMetalTextureCacheCreate(
      kCFAllocatorDefault,
      nil,
      device,
      nil,
      &cache
    )
    guard cacheStatus == kCVReturnSuccess, let cache else {
      throw NSError(domain: "Art3m1s", code: Int(cacheStatus), userInfo: [
        NSLocalizedDescriptionKey: "CVMetalTextureCacheCreate failed: \(cacheStatus)"
      ])
    }
    var cvTexture: CVMetalTexture?
    let textureStatus = CVMetalTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault,
      cache,
      buffer,
      nil,
      .bgra8Unorm,
      width,
      height,
      0,
      &cvTexture
    )
    guard
      textureStatus == kCVReturnSuccess,
      let cvTexture,
      let metalTexture = CVMetalTextureGetTexture(cvTexture)
    else {
      throw NSError(domain: "Art3m1s", code: Int(textureStatus), userInfo: [
        NSLocalizedDescriptionKey: "CVMetalTexture creation failed: \(textureStatus)"
      ])
    }
    pixelBuffer = buffer
    let surfacePointer = unsafeBitCast(surface, to: UnsafeMutableRawPointer.self)
    ioSurfaceAddress = Int64(Int(bitPattern: surfacePointer))
    metalTextureCache = cache
    cvMetalTexture = cvTexture
    self.metalTexture = metalTexture
    let texturePointer = Unmanaged.passUnretained(metalTexture as AnyObject).toOpaque()
    metalTextureAddress = Int64(Int(bitPattern: texturePointer))
    super.init()
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    Unmanaged.passRetained(pixelBuffer)
  }
}
