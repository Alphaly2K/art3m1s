import Cocoa
import AVFoundation
import CoreVideo
import FlutterMacOS
import IOSurface
import macos_window_utils

class MainFlutterWindow: NSWindow {
  private var sharedTextureHost: Art3m1sSharedTextureHost?
  private var siglusAudioHost: Art3m1sSiglusAudioHost?

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
    let audioRegistrar = macOSWindowUtilsViewController.flutterViewController.registrar(
      forPlugin: "Art3m1sSiglusAudio"
    )
    siglusAudioHost = Art3m1sSiglusAudioHost(registrar: audioRegistrar)

    super.awakeFromNib()
  }
}

/// The Siglus VM mixes through Kira's device-free backend. Only this host
/// object owns the macOS output device and its queued PCM buffers.
private final class Art3m1sSiglusAudioHost: NSObject {
  private let channel: FlutterMethodChannel
  private var engine: AVAudioEngine?
  private var player: AVAudioPlayerNode?
  private var format: AVAudioFormat?
  private var masterVolume: Float = 1
  private let queueLock = NSLock()
  private var queuedFrames = 0
  private let maxQueuedFrames = 24_000

  init(registrar: FlutterPluginRegistrar) {
    channel = FlutterMethodChannel(
      name: "moe.alphaly.art3m1s/siglus_audio",
      binaryMessenger: registrar.messenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "HOST_RELEASED", message: "Siglus audio host released", details: nil))
        return
      }
      switch call.method {
      case "start":
        do {
          try self.start()
          result(true)
        } catch {
          result(FlutterError(code: "AUDIO_START_FAILED", message: error.localizedDescription, details: nil))
        }
      case "append":
        guard let bytes = call.arguments as? FlutterStandardTypedData else {
          result(FlutterError(code: "INVALID_PCM", message: "Expected Float32 PCM bytes", details: nil))
          return
        }
        result(self.append(bytes.data))
      case "suspend":
        let suspended = (call.arguments as? Bool) ?? false
        if suspended { self.player?.pause() } else { self.player?.play() }
        result(nil)
      case "volume":
        let value = (call.arguments as? NSNumber)?.floatValue ?? 1
        self.masterVolume = min(max(value, 0), 1)
        self.player?.volume = self.masterVolume
        result(nil)
      case "dispose":
        self.dispose()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit { dispose() }

  private func start() throws {
    dispose()
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2) else {
      throw NSError(domain: "Art3m1sSiglusAudio", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Cannot create 48 kHz stereo format"
      ])
    }
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: format)
    engine.prepare()
    try engine.start()
    player.volume = masterVolume
    player.play()
    self.engine = engine
    self.player = player
    self.format = format
  }

  private func append(_ bytes: Data) -> Bool {
    guard let player, let format, !bytes.isEmpty, bytes.count % 8 == 0 else { return false }
    let frames = bytes.count / 8
    guard frames <= 4_800 else { return false }
    queueLock.lock()
    let accepted = queuedFrames + frames <= maxQueuedFrames
    if accepted { queuedFrames += frames }
    queueLock.unlock()
    guard accepted else { return false }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
          let channels = buffer.floatChannelData else {
      finish(frames)
      return false
    }
    buffer.frameLength = AVAudioFrameCount(frames)
    bytes.withUnsafeBytes { raw in
      for frame in 0..<frames {
        let left = raw.loadUnaligned(fromByteOffset: frame * 8, as: UInt32.self)
        let right = raw.loadUnaligned(fromByteOffset: frame * 8 + 4, as: UInt32.self)
        channels[0][frame] = Float(bitPattern: UInt32(littleEndian: left))
        channels[1][frame] = Float(bitPattern: UInt32(littleEndian: right))
      }
    }
    player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
      self?.finish(frames)
    }
    return true
  }

  private func finish(_ frames: Int) {
    queueLock.lock()
    queuedFrames = max(0, queuedFrames - frames)
    queueLock.unlock()
  }

  private func dispose() {
    player?.stop()
    engine?.stop()
    player = nil
    engine = nil
    format = nil
    queueLock.lock()
    queuedFrames = 0
    queueLock.unlock()
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
