import Cocoa
import CoreVideo
import FlutterMacOS
import IOSurface
import macos_window_utils

class MainFlutterWindow: NSWindow {
  private var sharedTextureHost: Art3m1sSharedTextureHost?
  private var artemisV2: ArtemisFlutterHost?

  override func awakeFromNib() {
    let windowFrame = self.frame
    let macOSWindowUtilsViewController = MacOSWindowUtilsViewController()
    self.contentViewController = macOSWindowUtilsViewController
    self.setFrame(windowFrame, display: true)

    // 在窗口首次显示前同步配置外观，避免启动瞬间闪过一个
    // 未隐藏标题栏的默认窗口（Dart 侧配置是异步的，赶不上首帧）。
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)

    // macos_ui 的现代窗口外观：原生毛玻璃背景 + 侧栏 vibrancy。
    MainFlutterWindowManipulator.start(mainFlutterWindow: self)

    RegisterGeneratedPlugins(registry: macOSWindowUtilsViewController.flutterViewController)
    let textureRegistrar = macOSWindowUtilsViewController.flutterViewController.registrar(
      forPlugin: "Art3m1sSharedTexture"
    )
    sharedTextureHost = Art3m1sSharedTextureHost(registrar: textureRegistrar)
    if let directory = Bundle.main.executableURL?.deletingLastPathComponent() {
      let core = directory.appendingPathComponent("libart3m1s_artemis_core.dylib").path
      let metal = directory.appendingPathComponent("libart3m1s_artemis_metal_host.dylib").path
      let media = directory.appendingPathComponent("libart3m1s_artemis_media_host.dylib").path
      let frameworks = Bundle.main.privateFrameworksURL
      let dxvk = frameworks?.appendingPathComponent("libart3m1s_artemis_dxvk_host.dylib").path
      if FileManager.default.fileExists(atPath: core), FileManager.default.fileExists(atPath: metal) {
        let host = ArtemisFlutterHost(registry: textureRegistrar.textures, corePath: core, metalPath: metal,
          mediaPath: FileManager.default.fileExists(atPath: media) ? media : nil,
          angleDirectory: directory.path,
          dxvkDirectory: dxvk.flatMap { FileManager.default.fileExists(atPath: $0) ? frameworks?.path : nil })
        host.register(messenger: textureRegistrar.messenger)
        artemisV2 = host
        NotificationCenter.default.addObserver(self, selector: #selector(closeArtemisV2(_:)),
          name: NSWindow.willCloseNotification, object: self)
      }
    }
    super.awakeFromNib()
  }

  @objc private func closeArtemisV2(_ notification: Notification) {
    artemisV2?.close()
    artemisV2 = nil
  }
}

private final class Art3m1sSharedTextureHost: NSObject {
  private let registry: FlutterTextureRegistry
  private var channel: FlutterMethodChannel?
  private var texture: Art3m1sSharedTexture?
  private var textureId: Int64?

  init(registrar: FlutterPluginRegistrar) {
    registry = registrar.textures
    super.init()
    let channel = FlutterMethodChannel(
      name: "moe.alphaly.art3m1s/shared_texture",
      binaryMessenger: registrar.messenger
    )
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "HOST_RELEASED", message: "Texture host was released", details: nil))
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
          result(try self.create(width: width, height: height))
        } catch {
          result(FlutterError(code: "CREATE_FAILED", message: error.localizedDescription, details: nil))
        }
      case "frameAvailable":
        if let textureId = self.textureId {
          self.registry.textureFrameAvailable(textureId)
        }
        result(nil)
      case "release":
        self.releaseTexture()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    releaseTexture()
  }

  private func create(width: Int, height: Int) throws -> [String: Int64] {
    releaseTexture()
    let texture = try Art3m1sSharedTexture(width: width, height: height)
    let textureId = registry.register(texture)
    // Flutter 3.44 assigns external texture IDs from zero. The public header's
    // historical "0 means failure" comment no longer matches the engine.
    self.texture = texture
    self.textureId = textureId
    return ["textureId": textureId, "kind": 2, "handle": texture.ioSurfaceAddress]
  }

  private func releaseTexture() {
    if let textureId {
      registry.unregisterTexture(textureId)
    }
    textureId = nil
    texture = nil
  }
}

private final class Art3m1sSharedTexture: NSObject, FlutterTexture {
  let pixelBuffer: CVPixelBuffer
  let ioSurfaceAddress: Int64

  init(width: Int, height: Int) throws {
    let attributes: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
      kCVPixelBufferMetalCompatibilityKey: true,
      kCVPixelBufferOpenGLCompatibilityKey: true,
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
