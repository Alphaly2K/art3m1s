import Darwin
import Combine
import CoreImage
import CoreVideo
import Foundation
import IOSurface
import Metal
import QuartzCore
import UIKit

enum CoreBridgeError: LocalizedError {
  case frameworkUnavailable
  case missingSymbol(String)
  case operationFailed(step: String, code: Int32)
  case invalidData(String)

  var errorDescription: String? {
    switch self {
    case .frameworkUnavailable:
      "无法加载 art3m1s_core.framework"
    case .missingSymbol(let name):
      "Rust Core 缺少符号：\(name)"
    case .operationFailed(let step, let code):
      "\(step) 失败（Core 返回 \(code)）"
    case .invalidData(let message):
      message
    }
  }
}

final class CoreBridge: @unchecked Sendable {
  static let shared = CoreBridge()

  private var handle: UnsafeMutableRawPointer?

  private init() {}

  func load() throws {
    guard handle == nil else { return }
    let candidates = [
      "@rpath/art3m1s_core.framework/art3m1s_core",
      "@loader_path/Frameworks/art3m1s_core.framework/art3m1s_core",
    ]
    for candidate in candidates {
      if let loaded = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) {
        handle = loaded
        AppLogger.info("Art3m1sCore loaded from \(candidate)")
        return
      }
    }
    throw CoreBridgeError.frameworkUnavailable
  }

  func symbol(_ name: String) throws -> UnsafeMutableRawPointer {
    try load()
    guard let handle, let address = dlsym(handle, name) else {
      throw CoreBridgeError.missingSymbol(name)
    }
    return address
  }

  func setDebugEnabled(_ enabled: Bool) {
    do {
      try load()
      let setDebug = try NativeCoreAPI.shared.function(
        .setDebug,
        as: SetDebug.self
      )
      setDebug(enabled ? 1 : 0)
    } catch {
      AppLogger.warning(
        "Core debug mode unavailable: \(error.localizedDescription)"
      )
    }
  }
}

private enum CoreAPISlot: Int {
  case hostEventsCreate = 0
  case hostEventsDestroy
  case hostEventsEnable
  case hostEventsNext
  case pollEvents
  case setFontList
  case setWindowState
  case setTextReplacements
  case setTextTranslationEnabled
  case clearHostState
  case resourcesCreate
  case resourcesDestroy
  case resourcesClear
  case resourcesMountDirectory
  case resourcesMountPFS
  case resourcesSetSaveDir
  case resourcesSetOverride
  case resourcesClearOverrides
  case runtimeCreate
  case runtimeDestroy
  case runtimeSetResources
  case runtimeSetRuntimeMediaEnabled
  case runtimeAdvanceAndPresent
  case runtimeAdvanceWithoutRender
  case runtimeStageWidth
  case runtimeStageHeight
  case runtimeLoadProject
  case runtimeLoadProjectBytes
  case runtimePixelBufferSize
  case runtimeAdvanceAndRender
  case runtimeSetExternalSurface
  case runtimeClearExternalSurface
  case runtimeFeedMouse
  case runtimeFeedClick
  case runtimeFeedMouseButton
  case runtimeFeedTouch
  case runtimeFeedKey
  case runtimeSubmitDialog
  case runtimeSubmitTextTranslation
  case runtimeSetReportedOS
  case runtimeSetEmoteBackend
  case runtimeConfigureSpatialUpscale
  case runtimeSetRenderQualityPreset
  case runtimeSetProfilerEnabled
  case runtimeProfilerSnapshot
  case runtimeSetVolume
  case runtimeNotifyVideoFinished
  case runtimeNotifySoundFinished
  case runtimeNotifyLifecycle
  case runtimeIsExitRequested
  case runtimeBackendCapabilities
  case runtimeSubmitHTTPResult
  case runtimeSetStringVariable
  case probeCaption
  case setAnglePath
  case setDebug
  case setDamageVisualization
  case setFontOverride
  case clearFontOverride
  case runtimeUploadVideoLayerFrame
}

private typealias GetCoreAPIV1 = @convention(c) (
  UnsafeMutablePointer<Int>?
) -> UnsafeRawPointer?
private typealias HostEventsCreate = @convention(c) () -> UnsafeMutableRawPointer?
private typealias HostEventsDestroy = @convention(c) (UnsafeMutableRawPointer?) -> Void
private typealias HostEventsEnable = @convention(c) (UnsafeMutableRawPointer?, Int32) -> Void
private typealias HostEventsNext = @convention(c) (UnsafeMutableRawPointer?) -> Int
private typealias HostEventsPoll = @convention(c) (
  UnsafeMutableRawPointer?,
  UnsafeMutablePointer<UInt8>?,
  Int,
  UnsafeMutablePointer<UInt32>?
) -> Int
private typealias SetFontList = @convention(c) (
  UnsafeMutableRawPointer?,
  Int32,
  Int32,
  UnsafePointer<UInt8>?,
  Int
) -> Int32
private typealias ResourcesCreate = @convention(c) () -> UnsafeMutableRawPointer?
private typealias ResourcesDestroy = @convention(c) (UnsafeMutableRawPointer?) -> Void
private typealias ResourcesMountPath = @convention(c) (
  UnsafeMutableRawPointer?,
  UnsafePointer<CChar>?
) -> Int32
private typealias ResourcesMountPFS = @convention(c) (
  UnsafeMutableRawPointer?,
  UnsafePointer<CChar>?,
  UnsafePointer<CChar>?
) -> Int32
private typealias RuntimeCreate = @convention(c) (
  UInt32,
  UInt32,
  Int32
) -> UnsafeMutableRawPointer?
private typealias RuntimeDestroy = @convention(c) (UnsafeMutableRawPointer?) -> Void
private typealias RuntimeSetResources = @convention(c) (
  UnsafeMutableRawPointer?,
  UnsafeMutableRawPointer?
) -> Int32
private typealias RuntimeConfigureSpatialUpscale = @convention(c) (
  UnsafeMutableRawPointer?,
  Float,
  Float
) -> Int32
private typealias RuntimeSetProfilerEnabled = @convention(c) (
  UnsafeMutableRawPointer?,
  Int32
) -> Void
private typealias RuntimeBackendCapabilities = @convention(c) (
  UnsafeMutableRawPointer?
) -> UInt64
private typealias RuntimeSetMediaEnabled = @convention(c) (
  UnsafeMutableRawPointer?,
  Int32
) -> Void
private typealias RuntimeLoadProject = @convention(c) (
  UnsafeMutableRawPointer?,
  UnsafePointer<UInt8>?,
  Int,
  UnsafePointer<CChar>?
) -> Int32
private typealias RuntimeSetReportedOS = @convention(c) (
  UnsafeMutableRawPointer?,
  UnsafePointer<CChar>?
) -> Void
private typealias RuntimeSetExternalSurface = @convention(c) (
  UnsafeMutableRawPointer?,
  Int32,
  UnsafeMutableRawPointer?,
  UInt32,
  UInt32
) -> Int32
private typealias RuntimeAdvancePresent = @convention(c) (
  UnsafeMutableRawPointer?,
  UInt32
) -> Int32
private typealias RuntimeAdvanceWithoutRender = @convention(c) (
  UnsafeMutableRawPointer?,
  UInt32
) -> Int32
private typealias RuntimeClearExternalSurface = @convention(c) (
  UnsafeMutableRawPointer?
) -> Void
private typealias RuntimeStageSize = @convention(c) (UnsafeMutableRawPointer?) -> UInt32
private typealias RuntimeAdvanceRender = @convention(c) (
  UnsafeMutableRawPointer?,
  UInt32,
  UnsafeMutablePointer<UInt8>?,
  UInt32
) -> UInt32
private typealias RuntimeFeedTouch = @convention(c) (
  UnsafeMutableRawPointer?,
  UInt32,
  UInt8,
  Int32,
  Int32
) -> Void
private typealias RuntimeFeedMouseButton = @convention(c) (
  UnsafeMutableRawPointer?,
  UInt32,
  Int32
) -> Void
private typealias RuntimeFeedClick = @convention(c) (
  UnsafeMutableRawPointer?
) -> Void
private typealias RuntimeFeedKey = @convention(c) (
  UnsafeMutableRawPointer?,
  UInt32,
  Int32
) -> Void
private typealias RuntimeFeedMouse = @convention(c) (
  UnsafeMutableRawPointer?,
  Int32,
  Int32
) -> Void
private typealias RuntimeNotifyFinished = @convention(c) (
  UnsafeMutableRawPointer?,
  UnsafePointer<CChar>?
) -> Void
private typealias RuntimeNotifyLifecycle = @convention(c) (
  UnsafeMutableRawPointer?,
  Int32
) -> Void
private typealias SetWindowState = @convention(c) (
  UnsafeMutableRawPointer?,
  Int32
) -> Void
private typealias SetTextReplacements = @convention(c) (
  UnsafeMutableRawPointer?,
  UnsafePointer<UInt8>?,
  Int
) -> Int32
private typealias SetTextTranslationEnabled = @convention(c) (
  UnsafeMutableRawPointer?,
  Int32
) -> Void
private typealias SetFontOverride = @convention(c) (
  UnsafePointer<UInt8>?,
  Int32
) -> Int32
private typealias ClearFontOverride = @convention(c) () -> Void
private typealias ResourcesSetOverride = @convention(c) (
  UnsafeMutableRawPointer?,
  UnsafePointer<CChar>?,
  UnsafePointer<UInt8>?,
  Int
) -> Int32
private typealias ResourcesClearOverrides = @convention(c) (
  UnsafeMutableRawPointer?
) -> Void
private typealias RuntimeIsExitRequested = @convention(c) (UnsafeMutableRawPointer?) -> Int32
private typealias RuntimeSubmitDialog = @convention(c) (
  UnsafeMutableRawPointer?,
  Int32,
  UnsafePointer<CChar>?
) -> Int32
private typealias RuntimeSubmitTextTranslation = @convention(c) (
  UnsafeMutableRawPointer?,
  UInt64,
  UnsafePointer<CChar>?
) -> Int32
private typealias SetDebug = @convention(c) (Int32) -> Void

private final class NativeCoreAPI {
  static let shared = NativeCoreAPI()

  private var libraryHandle: UnsafeMutableRawPointer?
  private var apiPointer: UnsafeRawPointer?

  private init() {}

  func load() throws {
    guard apiPointer == nil else { return }
    let candidates = [
      "@rpath/art3m1s_core.framework/art3m1s_core",
      "@loader_path/Frameworks/art3m1s_core.framework/art3m1s_core",
    ]
    var loadedHandle: UnsafeMutableRawPointer?
    for candidate in candidates {
      loadedHandle = dlopen(candidate, RTLD_NOW | RTLD_LOCAL)
      if loadedHandle != nil {
        break
      }
    }
    guard let loadedHandle else {
      throw CoreBridgeError.frameworkUnavailable
    }
    guard let symbol = dlsym(loadedHandle, "art3m1s_get_api_v1") else {
      throw CoreBridgeError.missingSymbol("art3m1s_get_api_v1")
    }
    let getAPI = unsafeBitCast(symbol, to: GetCoreAPIV1.self)
    var structSize = 0
    guard let pointer = getAPI(&structSize) else {
      throw CoreBridgeError.missingSymbol("Core API V1")
    }
    let abiVersion = pointer.load(fromByteOffset: 4, as: UInt32.self)
    let magic = pointer.load(fromByteOffset: 8, as: UInt64.self)
    let minimumSize =
      16 + (CoreAPISlot.runtimeUploadVideoLayerFrame.rawValue + 1) * 8
    guard abiVersion == 1,
          magic == 0x415254334D314150,
          structSize >= minimumSize
    else {
      throw CoreBridgeError.missingSymbol("Core API V1 ABI mismatch")
    }
    libraryHandle = loadedHandle
    apiPointer = pointer
    AppLogger.info("Art3m1sCore API V1 loaded")
  }

  func function<T>(_ slot: CoreAPISlot, as type: T.Type) throws -> T {
    try load()
    guard let apiPointer else {
      throw CoreBridgeError.frameworkUnavailable
    }
    let offset = 16 + slot.rawValue * MemoryLayout<UnsafeRawPointer?>.size
    guard let raw = apiPointer.load(
      fromByteOffset: offset,
      as: UnsafeRawPointer?.self
    ) else {
      throw CoreBridgeError.missingSymbol("Core API slot \(slot.rawValue)")
    }
    return unsafeBitCast(raw, to: T.self)
  }
}

enum PFSReader {
  private typealias OpenWithEncoding = @convention(c) (
    UnsafePointer<CChar>?,
    UnsafePointer<CChar>?
  ) -> UnsafeMutableRawPointer?
  private typealias FileSize = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<CChar>?
  ) -> Int32
  private typealias Read = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafePointer<CChar>?,
    UInt64,
    UnsafeMutablePointer<UInt8>?,
    UInt32
  ) -> Int32
  private typealias Close = @convention(c) (UnsafeMutableRawPointer?) -> Void
  private typealias EntryCount = @convention(c) (
    UnsafeMutableRawPointer?
  ) -> Int32
  private typealias EntryPath = @convention(c) (
    UnsafeMutableRawPointer?,
    Int32,
    UnsafeMutablePointer<CChar>?,
    Int32
  ) -> Int32

  static func listEntries(
    archivePath: String,
    encoding: String
  ) throws -> [String] {
    guard let handle = loadLibrary(),
          let openSymbol = dlsym(handle, "pfs_open_with_encoding"),
          let countSymbol = dlsym(handle, "pfs_entry_count"),
          let pathSymbol = dlsym(handle, "pfs_entry_path"),
          let closeSymbol = dlsym(handle, "pfs_close")
    else {
      throw CoreBridgeError.missingSymbol("PFS listing ABI")
    }
    let open = unsafeBitCast(openSymbol, to: OpenWithEncoding.self)
    let entryCount = unsafeBitCast(countSymbol, to: EntryCount.self)
    let entryPath = unsafeBitCast(pathSymbol, to: EntryPath.self)
    let close = unsafeBitCast(closeSymbol, to: Close.self)
    let archive = archivePath.withCString { open($0, encoding) }
    guard let archive else {
      throw CoreBridgeError.missingSymbol("PFS archive \(archivePath)")
    }
    defer { close(archive) }
    let count = entryCount(archive)
    guard count > 0 else { return [] }
    var paths: [String] = []
    paths.reserveCapacity(Int(count))
    for index in 0..<count {
      var buffer = [CChar](repeating: 0, count: 4096)
      let written = buffer.withUnsafeMutableBufferPointer {
        entryPath(archive, index, $0.baseAddress, Int32($0.count))
      }
      guard written >= 0,
            let path = String(
              bytes: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) },
              encoding: .utf8
            ),
            !path.isEmpty
      else {
        continue
      }
      paths.append(path)
    }
    return paths
  }

  static func read(
    archivePath: String,
    entryPath: String,
    encoding: String
  ) throws -> Data {
    guard let handle = loadLibrary(),
          let openSymbol = dlsym(handle, "pfs_open_with_encoding"),
          let sizeSymbol = dlsym(handle, "pfs_file_size"),
          let readSymbol = dlsym(handle, "pfs_read"),
          let closeSymbol = dlsym(handle, "pfs_close")
    else {
      throw CoreBridgeError.missingSymbol("PFS ABI")
    }
    let open = unsafeBitCast(openSymbol, to: OpenWithEncoding.self)
    let fileSize = unsafeBitCast(sizeSymbol, to: FileSize.self)
    let readEntry = unsafeBitCast(readSymbol, to: Read.self)
    let close = unsafeBitCast(closeSymbol, to: Close.self)

    let archive = archivePath.withCString { open($0, encoding) }
    guard let archive else {
      throw CoreBridgeError.missingSymbol("PFS archive \(archivePath)")
    }
    defer { close(archive) }
    let size = entryPath.withCString { fileSize(archive, $0) }
    guard size > 0 else {
      throw CoreBridgeError.missingSymbol(entryPath)
    }
    var data = Data(count: Int(size))
    let written: Int32 = data.withUnsafeMutableBytes { buffer in
      entryPath.withCString {
        readEntry(
          archive,
          $0,
          0,
          buffer.bindMemory(to: UInt8.self).baseAddress,
          UInt32(size)
        )
      }
    }
    guard written > 0 else {
      throw CoreBridgeError.missingSymbol(entryPath)
    }
    data.removeSubrange(Int(written)..<data.count)
    return data
  }

  private static func loadLibrary() -> UnsafeMutableRawPointer? {
    do {
      try NativeCoreAPI.shared.load()
    } catch {
      return nil
    }
    return dlopen(
      "@rpath/art3m1s_core.framework/art3m1s_core",
      RTLD_NOW | RTLD_LOCAL
    )
  }
}

struct NativeDialogRequest: Identifiable {
  let id = UUID()
  let title: String
  let message: String
  let hasCancel: Bool
  let hasTextField: Bool
  let initialText: String
}

struct NativeRuntimeHUD: Equatable {
  var graphicsAPI = "启动中"
  var zeroCopyPath = "等待 runtime"
  var metalFXStatus: String?
  var residentMiB = 0.0
  var fps = 0.0
}

private final class NativeSharedSurface {
  let pixelBuffer: CVPixelBuffer
  let ioSurface: IOSurfaceRef
  let metalTexture: MTLTexture

  private let metalTextureCache: CVMetalTextureCache
  private let cvMetalTexture: CVMetalTexture
  private let imageContext: CIContext

  var ioSurfacePointer: UnsafeMutableRawPointer {
    unsafeBitCast(ioSurface, to: UnsafeMutableRawPointer.self)
  }

  var metalTexturePointer: UnsafeMutableRawPointer {
    Unmanaged.passUnretained(metalTexture as AnyObject).toOpaque()
  }

  init(width: Int, height: Int) throws {
    let attributes: [CFString: Any] = [
      kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
      kCVPixelBufferMetalCompatibilityKey: true,
      kCVPixelBufferOpenGLESCompatibilityKey: true,
    ]
    var buffer: CVPixelBuffer?
    let bufferStatus = CVPixelBufferCreate(
      kCFAllocatorDefault,
      width,
      height,
      kCVPixelFormatType_32BGRA,
      attributes as CFDictionary,
      &buffer
    )
    guard bufferStatus == kCVReturnSuccess, let buffer else {
      throw CoreBridgeError.operationFailed(
        step: "CVPixelBufferCreate",
        code: Int32(bufferStatus)
      )
    }
    guard let surface = CVPixelBufferGetIOSurface(buffer)?
      .takeUnretainedValue() else {
      throw CoreBridgeError.invalidData("共享纹理没有 IOSurface backing")
    }
    guard let device = MTLCreateSystemDefaultDevice() else {
      throw CoreBridgeError.invalidData("当前设备没有可用 Metal device")
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
      throw CoreBridgeError.operationFailed(
        step: "CVMetalTextureCacheCreate",
        code: Int32(cacheStatus)
      )
    }

    var texture: CVMetalTexture?
    let textureStatus = CVMetalTextureCacheCreateTextureFromImage(
      kCFAllocatorDefault,
      cache,
      buffer,
      nil,
      .bgra8Unorm,
      width,
      height,
      0,
      &texture
    )
    guard textureStatus == kCVReturnSuccess,
          let texture,
          let metalTexture = CVMetalTextureGetTexture(texture)
    else {
      throw CoreBridgeError.operationFailed(
        step: "CVMetalTextureCreate",
        code: Int32(textureStatus)
      )
    }

    pixelBuffer = buffer
    ioSurface = surface
    cvMetalTexture = texture
    metalTextureCache = cache
    self.metalTexture = metalTexture
    imageContext = CIContext(mtlDevice: device)
  }

  func makeCGImage() -> CGImage? {
    let image = CIImage(cvPixelBuffer: pixelBuffer)
    return imageContext.createCGImage(image, from: image.extent)
  }
}

private struct ProcessSample {
  let cpuTime: Double
  let residentBytes: UInt64
  let wallTime: CFTimeInterval
}

private enum ProjectCharset {
  static func detect(_ data: Data, platform: String) -> String {
    let ascii = String(
      bytes: data.map { $0 < 0x80 ? $0 : 0x20 },
      encoding: .ascii
    ) ?? ""
    let target = platform.trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
    var current = ""
    for rawLine in ascii.split(whereSeparator: \.isNewline) {
      let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if line.isEmpty || line.hasPrefix(";") || line.hasPrefix("#") {
        continue
      }
      if line.hasPrefix("["), line.hasSuffix("]") {
        current = String(line.dropFirst().dropLast())
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .uppercased()
        continue
      }
      guard current == target,
            let separator = line.firstIndex(of: "=")
      else {
        continue
      }
      let key = line[..<separator]
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
      guard key == "CHARSET" else { continue }
      return normalize(String(line[line.index(after: separator)...]))
    }
    return "Shift_JIS"
  }

  private static func normalize(_ value: String) -> String {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
    case "UTF-8", "UTF8":
      return "UTF-8"
    default:
      return "Shift_JIS"
    }
  }
}

@MainActor
final class NativeGameRuntime: ObservableObject {
  @Published private(set) var frame: CGImage?
  @Published private(set) var isRunning = false
  @Published private(set) var stageWidth = 1280
  @Published private(set) var stageHeight = 720
  @Published private(set) var hud = NativeRuntimeHUD()
  @Published var errorMessage: String?
  @Published var windowTitle: String?
  @Published var dialog: NativeDialogRequest?
  @Published var avoidOverlay = false
  @Published var showStatusBar = false
  @Published var masterVolume = 1.0
  @Published var shouldClose = false

  private var game: GameEntry
  private let backend: Int
  private let translationSettings: TranslationSettings
  private let renderUpscalingEnabled: Bool
  private let debugModeEnabled: Bool
  private var metalFXStatus: String?
  private(set) lazy var media = NativeMediaBridge()
  private var resources: UnsafeMutableRawPointer?
  private var runtime: UnsafeMutableRawPointer?
  private var hostEvents: UnsafeMutableRawPointer?
  private var translationService: NativeTranslationService?
  private var inputGate = InputGatePolicy.full
  private var mouseButtonsDown: Set<UInt32> = []
  private var sharedSurface: NativeSharedSurface?
  @Published private(set) var externalSurfaceKind: Int32?
  private var metalLayer: CAMetalLayer?
  private var metalLayerSize = CGSize.zero
  private var pfsEncoding = "Shift_JIS"
  private var projectPlatform = GameManifest.defaultRuntimePlatform
  private var timer: Timer?
  private var nextFrameDeadline = CACurrentMediaTime()
  private var frameIndex = 0
  private var pixelBuffer: [UInt8] = []
  private var frameTimestamps: [CFTimeInterval] = []
  private var lastHUDUpdate = 0.0

  var effectiveInputGate: InputGatePolicy {
    inputGate
  }

  init(
    game: GameEntry,
    backend: Int,
    translationSettings: TranslationSettings,
    renderUpscalingEnabled: Bool,
    debugModeEnabled: Bool
  ) {
    self.game = game
    self.backend = backend
    self.translationSettings = translationSettings
    self.renderUpscalingEnabled = renderUpscalingEnabled
    self.debugModeEnabled = debugModeEnabled
  }

  func start() async {
    guard !isRunning else { return }
    do {
      try AppDataPaths.ensureInitialized()
      game = GameManifest.loadEntrySettings(game)
      try NativeCoreAPI.shared.load()
      let iniContent = try readSystemINI()
      parseStageSize(iniContent)
      projectPlatform = Self.resolvePlatform(
        in: iniContent,
        requested: runtimePlatform
      )
      if game.source == .pfsArchive {
        pfsEncoding = ProjectCharset.detect(
          iniContent,
          platform: projectPlatform
        )
      }
      inputGate = game.inputGate ?? .full
      try registerHostEvents()
      try mountResources()
      configureMedia()
      configureTranslation()
      applyFontOverride()
      try applyEnvironmentOverrides()
      try createRuntime()
      applyRuntimeOptions()
      syncHostState()
      try loadProject(iniContent)
      attachRenderSurface()
      applyRenderOutputPolicy()
      isRunning = true
      nextFrameDeadline = CACurrentMediaTime()
      hud = NativeRuntimeHUD(
        graphicsAPI: Self.backendLabel(backend),
        zeroCopyPath: surfaceDescription,
        metalFXStatus: metalFXStatus,
        residentMiB: 0,
        fps: 0
      )
      startTimer()
    } catch {
      errorMessage = error.localizedDescription
      AppLogger.error("Native runtime start failed: \(error.localizedDescription)")
      stopRuntime()
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    isRunning = false
    notifyLifecycle(0)
    stopRuntime()
  }

  func attachMetalLayer(_ layer: CAMetalLayer, size: CGSize) {
    guard size.width > 0, size.height > 0 else { return }
    metalLayer = layer
    metalLayerSize = size
    guard runtime != nil else { return }
    attachRenderSurface()
    applyRenderOutputPolicy()
  }

  func feedTouch(id: UInt32, phase: UInt8, point: CGPoint) {
    guard inputGate.touch, let runtime else { return }
    let x = Int32(min(max(point.x, 0), CGFloat(stageWidth)))
    let y = Int32(min(max(point.y, 0), CGFloat(stageHeight)))
    do {
      let function = try NativeCoreAPI.shared.function(
        .runtimeFeedTouch,
        as: RuntimeFeedTouch.self
      )
      function(runtime, id, phase, x, y)
    } catch {
      AppLogger.warning("feedTouch unavailable: \(error.localizedDescription)")
    }
  }

  func feedMouseButton(button: UInt32, pressed: Bool) {
    guard inputGate.mouseButtons, let runtime else { return }
    if pressed {
      mouseButtonsDown.insert(button)
    } else {
      mouseButtonsDown.remove(button)
    }
    guard let function = try? NativeCoreAPI.shared.function(
      .runtimeFeedMouseButton,
      as: RuntimeFeedMouseButton.self
    ) else {
      return
    }
    function(runtime, button, pressed ? 1 : 0)
  }

  func feedKey(_ virtualKey: Int, pressed: Bool) {
    guard let filtered = inputGate.filterKey(virtualKey),
          let runtime
    else {
      return
    }
    guard let function = try? NativeCoreAPI.shared.function(
      .runtimeFeedKey,
      as: RuntimeFeedKey.self
    ) else {
      return
    }
    function(runtime, UInt32(filtered), pressed ? 1 : 0)
  }

  func feedForwardedKey(_ virtualKey: Int, pressed: Bool) {
    guard let filtered = inputGate.filterForwardedKey(virtualKey),
          let runtime
    else {
      return
    }
    guard let function = try? NativeCoreAPI.shared.function(
      .runtimeFeedKey,
      as: RuntimeFeedKey.self
    ) else {
      return
    }
    function(runtime, UInt32(filtered), pressed ? 1 : 0)
  }

  func feedWheel(_ virtualKey: Int) {
    feedForwardedKey(virtualKey, pressed: true)
    feedForwardedKey(virtualKey, pressed: false)
  }

  func feedClick() {
    guard inputGate.mouseButtons, let runtime else { return }
    guard let function = try? NativeCoreAPI.shared.function(
      .runtimeFeedClick,
      as: RuntimeFeedClick.self
    ) else {
      return
    }
    function(runtime)
  }

  func releasePointerButtons() {
    for button in mouseButtonsDown {
      feedMouseButton(button: button, pressed: false)
    }
    mouseButtonsDown.removeAll()
  }

  func submitDialog(accepted: Bool, text: String) {
    guard let runtime else { return }
    do {
      let submit = try NativeCoreAPI.shared.function(
        .runtimeSubmitDialog,
        as: RuntimeSubmitDialog.self
      )
      text.withCString {
        _ = submit(runtime, accepted ? 1 : 0, $0)
      }
      dialog = nil
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  private func registerHostEvents() throws {
    let create = try NativeCoreAPI.shared.function(
      .hostEventsCreate,
      as: HostEventsCreate.self
    )
    guard let hostEvents = create() else {
      throw CoreBridgeError.missingSymbol("hostEventsCreate")
    }
    self.hostEvents = hostEvents
    let enable = try NativeCoreAPI.shared.function(
      .hostEventsEnable,
      as: HostEventsEnable.self
    )
    enable(hostEvents, 1)
  }

  func feedMouse(point: CGPoint) {
    guard inputGate.mouseMove, let runtime else { return }
    do {
      let function = try NativeCoreAPI.shared.function(
        .runtimeFeedMouse,
        as: RuntimeFeedMouse.self
      )
      function(runtime, Int32(point.x), Int32(point.y))
    } catch {
      AppLogger.warning("feedMouse unavailable: \(error.localizedDescription)")
    }
  }

  func setSuspended(_ suspended: Bool) {
    media.setSuspended(suspended)
    setWindowState(minimized: suspended)
    notifyLifecycle(suspended ? 1 : 2)
  }

  func setMasterVolume(_ value: Double) {
    masterVolume = min(max(value, 0), 1)
    media.setMasterVolume(masterVolume)
  }

  private func setWindowState(minimized: Bool) {
    guard let hostEvents,
          let function = try? NativeCoreAPI.shared.function(
            .setWindowState,
            as: SetWindowState.self
          )
    else {
      return
    }
    function(hostEvents, minimized ? 1 : 0)
  }

  func notifyLifecycle(_ state: Int32) {
    guard let runtime,
          let function = try? NativeCoreAPI.shared.function(
            .runtimeNotifyLifecycle,
            as: RuntimeNotifyLifecycle.self
          )
    else {
      return
    }
    function(runtime, state)
  }

  private func notifyVideoFinished(_ id: String?) {
    guard let runtime,
          let function = try? NativeCoreAPI.shared.function(
            .runtimeNotifyVideoFinished,
            as: RuntimeNotifyFinished.self
          )
    else {
      return
    }
    (id ?? "").withCString { function(runtime, $0) }
  }

  private func notifySoundFinished(_ id: String?) {
    guard let runtime,
          let function = try? NativeCoreAPI.shared.function(
            .runtimeNotifySoundFinished,
            as: RuntimeNotifyFinished.self
          )
    else {
      return
    }
    (id ?? "").withCString { function(runtime, $0) }
  }

  private func mountResources() throws {
    let create = try NativeCoreAPI.shared.function(
      .resourcesCreate,
      as: ResourcesCreate.self
    )
    guard let resources = create() else {
      throw CoreBridgeError.missingSymbol("resourcesCreate")
    }
    self.resources = resources

    let mounted: Int32
    switch game.source {
    case .directory:
      let mount = try NativeCoreAPI.shared.function(
        .resourcesMountDirectory,
        as: ResourcesMountPath.self
      )
      mounted = game.path.withCString { mount(resources, $0) }
    case .pfsArchive:
      let archives = Self.pfsArchives(for: game.path)
      guard !archives.isEmpty else {
        throw CoreBridgeError.invalidData("找不到可挂载的 PFS 归档")
      }
      let mount = try NativeCoreAPI.shared.function(
        .resourcesMountPFS,
        as: ResourcesMountPFS.self
      )
      var mountedArchives = 0
      for archive in archives {
        let result = archive.withCString { path in
          pfsEncoding.withCString { encoding in
            mount(resources, path, encoding)
          }
        }
        if result != 0 {
          mountedArchives += 1
        }
      }
      mounted = mountedArchives > 0 ? 1 : 0
    }
    guard mounted != 0 else {
      throw CoreBridgeError.operationFailed(
        step: "resourcesMount",
        code: 0
      )
    }

    let save = AppDataPaths.saves.appendingPathComponent(
      game.id,
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: save,
      withIntermediateDirectories: true
    )
    let setSave = try NativeCoreAPI.shared.function(
      .resourcesSetSaveDir,
      as: ResourcesMountPath.self
    )
    let saveResult = save.path.withCString { setSave(resources, $0) }
    guard saveResult != 0 else {
      throw CoreBridgeError.operationFailed(
        step: "resourcesSetSaveDir",
        code: saveResult
      )
    }
  }

  private func configureMedia() {
    media.configure { [weak self] path in
      self?.readProjectAsset(path)
    }
    media.onVideoFinished = { [weak self] id in
      self?.notifyVideoFinished(id)
    }
    media.onSoundFinished = { [weak self] id in
      self?.notifySoundFinished(id)
    }
  }

  private func configureTranslation() {
    guard game.translationEnabled else {
      translationService?.dispose()
      translationService = nil
      return
    }
    let patchPath = game.translationPatchPath.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    let patchData: Data?
    if patchPath.isEmpty {
      patchData = nil
    } else {
      patchData = FileManager.default.fileExists(atPath: patchPath)
        ? try? Data(contentsOf: URL(fileURLWithPath: patchPath))
        : readProjectAsset(patchPath)
    }
    let cacheURL = AppDataPaths.translations
      .appendingPathComponent("\(game.id).pb")
    translationService = NativeTranslationService(
      settings: translationSettings,
      patchData: patchData,
      patchPath: patchPath,
      cacheURL: cacheURL
    )
    AppLogger.info(
      "Translation configured: mode=\(translationSettings.mode.rawValue)"
    )
  }

  private func applyFontOverride() {
    var fontData: Data?
    if !game.fontOverrideFilePath.isEmpty {
      fontData = try? Data(
        contentsOf: URL(fileURLWithPath: game.fontOverrideFilePath)
      )
    }
    if fontData == nil, !game.fontOverridePath.isEmpty {
      fontData = readProjectAsset(game.fontOverridePath)
    }
    guard let fontData, !fontData.isEmpty else {
      if let clear = try? NativeCoreAPI.shared.function(
        .clearFontOverride,
        as: ClearFontOverride.self
      ) {
        clear()
      }
      return
    }
    guard let setFont = try? NativeCoreAPI.shared.function(
      .setFontOverride,
      as: SetFontOverride.self
    ) else {
      return
    }
    let result = fontData.withUnsafeBytes { buffer in
      setFont(
        buffer.bindMemory(to: UInt8.self).baseAddress,
        Int32(fontData.count)
      )
    }
    if result == 0 {
      AppLogger.warning("Core rejected font override")
    }
  }

  private func syncHostState() {
    guard let hostEvents else { return }
    pushFontList(hostEvents, monospace: false, vertical: false)
    pushFontList(hostEvents, monospace: true, vertical: false)
    if let setWindow = try? NativeCoreAPI.shared.function(
      .setWindowState,
      as: SetWindowState.self
    ) {
      setWindow(hostEvents, 0)
    }
    guard let translationService else {
      if let disable = try? NativeCoreAPI.shared.function(
        .setTextTranslationEnabled,
        as: SetTextTranslationEnabled.self
      ) {
        disable(hostEvents, 0)
      }
      return
    }
    let replacements = translationService.hostReplacementTable
    if let data = try? JSONSerialization.data(withJSONObject: replacements),
       let setReplacements = try? NativeCoreAPI.shared.function(
         .setTextReplacements,
         as: SetTextReplacements.self
       ) {
      _ = data.withUnsafeBytes { buffer in
        setReplacements(
          hostEvents,
          buffer.bindMemory(to: UInt8.self).baseAddress,
          data.count
        )
      }
    }
    if let setEnabled = try? NativeCoreAPI.shared.function(
      .setTextTranslationEnabled,
      as: SetTextTranslationEnabled.self
    ) {
      setEnabled(
        hostEvents,
        translationService.hostOnlineEnabled ? 1 : 0
      )
    }
  }

  private func pushFontList(
    _ hostEvents: UnsafeMutableRawPointer,
    monospace: Bool,
    vertical: Bool
  ) {
    guard let function = try? NativeCoreAPI.shared.function(
      .setFontList,
      as: SetFontList.self
    ) else {
      return
    }
    let names = UIFont.familyNames.sorted()
    let data = Data(names.joined(separator: "\n").utf8)
    _ = data.withUnsafeBytes { buffer in
      function(
        hostEvents,
        monospace ? 1 : 0,
        vertical ? 1 : 0,
        buffer.bindMemory(to: UInt8.self).baseAddress,
        data.count
      )
    }
  }

  private func applyEnvironmentOverrides() throws {
    guard game.environmentPatchEnabled, let resources else { return }
    if let clear = try? NativeCoreAPI.shared.function(
      .resourcesClearOverrides,
      as: ResourcesClearOverrides.self
    ) {
      clear(resources)
    }
    var overrides = EnvironmentPatch.virtualFiles
    if let original = readProjectAsset("system/first.iet") {
      let transformed = EnvironmentPatch.transform(
        path: "system/first.iet",
        original: original
      )
      if transformed != original {
        overrides["system/first.iet"] = transformed
      }
    }
    guard let setOverride = try? NativeCoreAPI.shared.function(
      .resourcesSetOverride,
      as: ResourcesSetOverride.self
    ) else {
      return
    }
    for (path, data) in overrides {
      let result = path.withCString { pathPointer in
        data.withUnsafeBytes { buffer in
          setOverride(
            resources,
            pathPointer,
            buffer.bindMemory(to: UInt8.self).baseAddress,
            data.count
          )
        }
      }
      if result == 0 {
        throw CoreBridgeError.operationFailed(
          step: "resourcesSetOverride(\(path))",
          code: result
        )
      }
    }
  }

  private func readProjectAsset(_ path: String) -> Data? {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
      .split(separator: "/")
      .map(String.init)
      .filter { !$0.isEmpty && $0 != "." }
    guard !normalized.contains(".."), !normalized.isEmpty else { return nil }
    let relative = normalized.joined(separator: "/")
    switch game.source {
    case .directory:
      return try? Data(
        contentsOf: URL(fileURLWithPath: game.path)
          .appendingPathComponent(relative)
      )
    case .pfsArchive:
      if let sidecar = readPFSSidecar(relative) {
        return sidecar
      }
      for archive in Self.pfsArchives(for: game.path).reversed() {
        if let data = try? PFSReader.read(
          archivePath: archive,
          entryPath: relative,
          encoding: pfsEncoding
        ) {
          return data
        }
      }
      return nil
    }
  }

  private func readSystemINI() throws -> Data {
    switch game.source {
    case .directory:
      let url = URL(fileURLWithPath: game.path)
        .appendingPathComponent("system.ini")
      return try Data(contentsOf: url)
    case .pfsArchive:
      if let data = readProjectAsset("system.ini") {
        return data
      }
      throw CoreBridgeError.missingSymbol("system.ini")
    }
  }

  private func readPFSSidecar(_ relativePath: String) -> Data? {
    let root = URL(fileURLWithPath: game.path).deletingLastPathComponent()
    let url = root.appendingPathComponent(relativePath)
    guard url.standardizedFileURL.path.hasPrefix(
      root.standardizedFileURL.path + "/"
    ) else {
      return nil
    }
    return try? Data(contentsOf: url)
  }

  private func parseStageSize(_ data: Data) {
    let ascii = String(
      bytes: data.map { $0 < 0x80 ? $0 : 0x20 },
      encoding: .ascii
    ) ?? ""
    for line in ascii.split(separator: "\n") {
      let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased()
      if value.hasPrefix("WIDTH="),
         let width = Int(value.split(separator: "=").last ?? "") {
        stageWidth = max(width, 1)
      }
      if value.hasPrefix("HEIGHT="),
         let height = Int(value.split(separator: "=").last ?? "") {
        stageHeight = max(height, 1)
      }
    }
  }

  private func createRuntime() throws {
    guard let resources else {
      throw CoreBridgeError.missingSymbol("resources")
    }
    let create = try NativeCoreAPI.shared.function(
      .runtimeCreate,
      as: RuntimeCreate.self
    )
    guard let runtime = create(
      UInt32(stageWidth),
      UInt32(stageHeight),
      Int32(backend)
    ) else {
      throw CoreBridgeError.operationFailed(step: "runtimeCreate", code: 0)
    }
    self.runtime = runtime

    let bind = try NativeCoreAPI.shared.function(
      .runtimeSetResources,
      as: RuntimeSetResources.self
    )
    let bindResult = bind(runtime, resources)
    guard bindResult != 0 else {
      throw CoreBridgeError.operationFailed(
        step: "runtimeSetResources",
        code: bindResult
      )
    }

    if let setProfiler = try? NativeCoreAPI.shared.function(
      .runtimeSetProfilerEnabled,
      as: RuntimeSetProfilerEnabled.self
    ) {
      setProfiler(runtime, debugModeEnabled ? 1 : 0)
    }

    if let media = try? NativeCoreAPI.shared.function(
      .runtimeSetRuntimeMediaEnabled,
      as: RuntimeSetMediaEnabled.self
    ) {
      media(runtime, 1)
      AppLogger.info("Artemis runtime video decoding enabled")
    } else {
      AppLogger.warning(
        "Artemis runtime video decoding unavailable in this core build"
      )
    }
  }

  private func applyRuntimeOptions() {
    guard let runtime else { return }
    let reportedOS = game.reportedOs.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    guard !reportedOS.isEmpty,
          let setReportedOS = try? NativeCoreAPI.shared.function(
            .runtimeSetReportedOS,
            as: RuntimeSetReportedOS.self
          )
    else {
      return
    }
    reportedOS.withCString {
      setReportedOS(runtime, $0)
    }
  }

  private func loadProject(_ iniContent: Data) throws {
    guard let runtime else {
      throw CoreBridgeError.missingSymbol("runtime")
    }
    let load = try NativeCoreAPI.shared.function(
      .runtimeLoadProjectBytes,
      as: RuntimeLoadProject.self
    )
    let result: Int32 = iniContent.withUnsafeBytes { buffer in
      projectPlatform.withCString { platform in
        load(
          runtime,
          buffer.bindMemory(to: UInt8.self).baseAddress,
          iniContent.count,
          platform
        )
      }
    }
    guard result == 0 else {
      throw CoreBridgeError.operationFailed(
        step: "runtimeLoadProjectBytes",
        code: result
      )
    }

    let width = try NativeCoreAPI.shared.function(
      .runtimeStageWidth,
      as: RuntimeStageSize.self
    )(runtime)
    let height = try NativeCoreAPI.shared.function(
      .runtimeStageHeight,
      as: RuntimeStageSize.self
    )(runtime)
    if width > 0 { stageWidth = Int(width) }
    if height > 0 { stageHeight = Int(height) }
    pixelBuffer = [UInt8](
      repeating: 0,
      count: stageWidth * stageHeight * 4
    )
  }

  private var runtimePlatform: String {
    let value = game.runtimePlatform
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
    return value.isEmpty ? GameManifest.defaultRuntimePlatform : value
  }

  private static func resolvePlatform(
    in data: Data,
    requested: String
  ) -> String {
    let ascii = String(
      bytes: data.map { $0 < 0x80 ? $0 : 0x20 },
      encoding: .ascii
    ) ?? ""
    let sections: Set<String> = Set(
      ascii.split(whereSeparator: \.isNewline).compactMap { rawLine in
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard line.hasPrefix("["), line.hasSuffix("]") else { return nil }
        return String(line.dropFirst().dropLast())
          .trimmingCharacters(in: .whitespacesAndNewlines)
          .uppercased()
      }
    )
    let normalized = requested
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .uppercased()
    if sections.contains(normalized) {
      return normalized
    }
    for candidate in ["WINDOWS", "ANDROID", "IOS", "WASM"]
    where sections.contains(candidate) {
      return candidate
    }
    return normalized.isEmpty
      ? GameManifest.defaultRuntimePlatform
      : normalized
  }

  private func attachRenderSurface() {
    guard let runtime else { return }
    clearExternalSurface()
    externalSurfaceKind = nil
    sharedSurface = nil
    if let metalLayer,
       metalLayerSize.width > 0,
       metalLayerSize.height > 0 {
      do {
        let attach = try NativeCoreAPI.shared.function(
          .runtimeSetExternalSurface,
          as: RuntimeSetExternalSurface.self
        )
        let result = attach(
          runtime,
          4,
          Unmanaged.passUnretained(metalLayer).toOpaque(),
          UInt32(metalLayerSize.width),
          UInt32(metalLayerSize.height)
        )
        if result != 0 {
          externalSurfaceKind = 4
          sharedSurface = nil
          frame = nil
          AppLogger.info(
            "CAMetalLayer attached: "
              + "\(Int(metalLayerSize.width))x\(Int(metalLayerSize.height))"
          )
          return
        }
        AppLogger.warning("Core rejected CAMetalLayer attachment")
      } catch {
        AppLogger.warning(
          "CAMetalLayer unavailable: \(error.localizedDescription)"
        )
      }
    }

    do {
      let surface = try NativeSharedSurface(
        width: stageWidth,
        height: stageHeight
      )
      let attach = try NativeCoreAPI.shared.function(
        .runtimeSetExternalSurface,
        as: RuntimeSetExternalSurface.self
      )
      let candidates: [(Int32, UnsafeMutableRawPointer)] = [
        (2, surface.ioSurfacePointer),
        (3, surface.metalTexturePointer),
      ]
      for (kind, pointer) in candidates {
        let result = attach(
          runtime,
          kind,
          pointer,
          UInt32(stageWidth),
          UInt32(stageHeight)
        )
        if result != 0 {
          sharedSurface = surface
          externalSurfaceKind = kind
          AppLogger.info(
            "Shared surface attached: kind=\(kind) \(stageWidth)x\(stageHeight)"
          )
          return
        }
      }
      AppLogger.warning("Core rejected IOSurface attachment; using RGBA readback")
    } catch {
      AppLogger.warning(
        "IOSurface unavailable; using RGBA readback: \(error.localizedDescription)"
      )
    }
  }

  private func applyRenderOutputPolicy() {
    guard renderUpscalingEnabled else {
      metalFXStatus = nil
      return
    }
    guard backend == 3, let runtime, stageWidth > 0, stageHeight > 0 else {
      metalFXStatus = "不可用"
      return
    }
    guard let configure = try? NativeCoreAPI.shared.function(
      .runtimeConfigureSpatialUpscale,
      as: RuntimeConfigureSpatialUpscale.self
    ) else {
      metalFXStatus = "不可用"
      return
    }

    let outputWidth = max(Int(metalLayerSize.width), 1)
    let outputHeight = max(Int(metalLayerSize.height), 1)
    let scale = min(
      1,
      min(
        CGFloat(stageWidth) / CGFloat(outputWidth),
        CGFloat(stageHeight) / CGFloat(outputHeight)
      )
    )
    let result = configure(runtime, Float(scale), 0.25)
    let capabilities = try? NativeCoreAPI.shared.function(
      .runtimeBackendCapabilities,
      as: RuntimeBackendCapabilities.self
    )
    let supported = capabilities.map {
      $0(runtime) & (UInt64(1) << 6) != 0
    } ?? false
    if result == 0 {
      metalFXStatus = "配置失败"
      AppLogger.warning("Render output policy rejected")
    } else if !supported {
      metalFXStatus = "不可用（线性缩放）"
    } else if scale >= 1 {
      metalFXStatus = "开启（无缩放）"
    } else {
      metalFXStatus = "已开启"
    }
  }

  private func detachSharedSurface() {
    clearExternalSurface()
    sharedSurface = nil
    externalSurfaceKind = nil
  }

  private func clearExternalSurface() {
    guard let runtime, externalSurfaceKind != nil else { return }
    if let clear = try? NativeCoreAPI.shared.function(
      .runtimeClearExternalSurface,
      as: RuntimeClearExternalSurface.self
    ) {
      clear(runtime)
    }
  }

  private var surfaceDescription: String {
    switch externalSurfaceKind {
    case 4:
      return "CAMetalLayer"
    case 2:
      return "IOSurface"
    case 3:
      return "MTLTexture"
    default:
      return "RGBA 回读"
    }
  }

  private func startTimer() {
    timer?.invalidate()
    let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.tick()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func tick() {
    guard let runtime else { return }
    do {
      drainEvents()
      let isExit = try NativeCoreAPI.shared.function(
        .runtimeIsExitRequested,
        as: RuntimeIsExitRequested.self
      )(runtime)
      if isExit != 0 {
        shouldClose = true
        stop()
        return
      }

      let now = CACurrentMediaTime()
      let target = 1.0 / 60.0
      guard now >= nextFrameDeadline else { return }
      let overdue = now - nextFrameDeadline
      let dueTicks = min(
        max(1 + Int(overdue / target), 1),
        8
      )
      nextFrameDeadline += target * Double(dueTicks)
      if now - nextFrameDeadline > target * 2 {
        nextFrameDeadline = now + target
      }

      for _ in 0..<max(dueTicks - 1, 0) {
        _ = advanceWithoutRender(deltaMs: nextFrameDeltaMs())
      }
      let deltaMs = nextFrameDeltaMs()

      if externalSurfaceKind != nil {
        let present = try NativeCoreAPI.shared.function(
          .runtimeAdvanceAndPresent,
          as: RuntimeAdvancePresent.self
        )
        let result = present(runtime, deltaMs)
        if result >= 0 {
          if externalSurfaceKind == 2 || externalSurfaceKind == 3 {
            if result > 0, let image = sharedSurface?.makeCGImage() {
              frame = image
            }
          }
          updateHUD(now: now)
          return
        }
        AppLogger.warning(
          "Shared surface present failed (\(result)); falling back to RGBA"
        )
        detachSharedSurface()
      }

      let advance = try NativeCoreAPI.shared.function(
        .runtimeAdvanceAndRender,
        as: RuntimeAdvanceRender.self
      )
      let written = pixelBuffer.withUnsafeMutableBytes { buffer in
        advance(
          runtime,
          deltaMs,
          buffer.bindMemory(to: UInt8.self).baseAddress,
          UInt32(pixelBuffer.count)
        )
      }
      if written > 0 {
        frame = makeImage(from: pixelBuffer, count: Int(written))
      }
      updateHUD(now: now)
    } catch {
      errorMessage = error.localizedDescription
      stop()
    }
  }

  private func advanceWithoutRender(deltaMs: UInt32) -> Bool {
    guard let runtime,
          let function = try? NativeCoreAPI.shared.function(
            .runtimeAdvanceWithoutRender,
            as: RuntimeAdvanceWithoutRender.self
          )
    else {
      return false
    }
    let result = function(runtime, deltaMs) != 0
    if result {
      drainEvents()
    }
    return result
  }

  private func nextFrameDeltaMs() -> UInt32 {
    let previous = (frameIndex * 1_000) / 60
    frameIndex += 1
    let current = (frameIndex * 1_000) / 60
    return UInt32(max(current - previous, 1))
  }

  private func updateHUD(now: CFTimeInterval) {
    frameTimestamps.append(now)
    frameTimestamps.removeAll { now - $0 > 1.0 }

    guard now - lastHUDUpdate >= 0.5 else { return }
    let sample = Self.processSample()
    lastHUDUpdate = now
    hud = NativeRuntimeHUD(
      graphicsAPI: Self.backendLabel(backend),
      zeroCopyPath: surfaceDescription,
      metalFXStatus: metalFXStatus,
      residentMiB: Double(sample.residentBytes) / 1_048_576,
      fps: Double(frameTimestamps.count)
    )
  }

  private func makeImage(from bytes: [UInt8], count: Int) -> CGImage? {
    guard stageWidth > 0,
          stageHeight > 0,
          count >= stageWidth * stageHeight * 4,
          let provider = CGDataProvider(
            data: Data(bytes.prefix(stageWidth * stageHeight * 4)) as CFData
          )
    else {
      return nil
    }
    return CGImage(
      width: stageWidth,
      height: stageHeight,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: stageWidth * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(
        rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }

  private static func backendLabel(_ backend: Int) -> String {
    switch backend {
    case 3:
      return "Metal"
    case 6:
      return "ANGLE / Metal"
    case 1:
      return "ANGLE / OpenGL ES"
    case 0:
      return "自动"
    default:
      return "Backend \(backend)"
    }
  }

  fileprivate static func processSample() -> ProcessSample {
    var info = mach_task_basic_info()
    var count = mach_msg_type_number_t(
      MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size
    )
    let result = withUnsafeMutablePointer(to: &info) { pointer in
      pointer.withMemoryRebound(
        to: integer_t.self,
        capacity: Int(count)
      ) {
        task_info(
          mach_task_self_,
          task_flavor_t(MACH_TASK_BASIC_INFO),
          $0,
          &count
        )
      }
    }
    guard result == KERN_SUCCESS else {
      return ProcessSample(
        cpuTime: 0,
        residentBytes: 0,
        wallTime: CACurrentMediaTime()
      )
    }
    let cpuTime =
      Double(info.user_time.seconds + info.system_time.seconds)
      + Double(info.user_time.microseconds + info.system_time.microseconds)
        / 1_000_000
    return ProcessSample(
      cpuTime: cpuTime,
      residentBytes: info.resident_size,
      wallTime: CACurrentMediaTime()
    )
  }

  private static func pfsArchives(for path: String) -> [String] {
    let baseURL = URL(fileURLWithPath: path)
    let directory = baseURL.deletingLastPathComponent()
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

  private func drainEvents() {
    guard let hostEvents else { return }
    do {
      let next = try NativeCoreAPI.shared.function(
        .hostEventsNext,
        as: HostEventsNext.self
      )
      let poll = try NativeCoreAPI.shared.function(
        .pollEvents,
        as: HostEventsPoll.self
      )
      while true {
        let required = next(hostEvents)
        guard required > 0 else { return }
        var buffer = [UInt8](repeating: 0, count: max(required, 16 * 1024))
        var count: UInt32 = 0
        let capacity = buffer.count
        let written = buffer.withUnsafeMutableBytes { raw in
          poll(
            hostEvents,
            raw.bindMemory(to: UInt8.self).baseAddress,
            capacity,
            &count
          )
        }
        guard written > 0, count > 0 else { return }
        parseEventBuffer(buffer, written: written, count: Int(count))
      }
    } catch {
      AppLogger.warning("Host event poll failed: \(error.localizedDescription)")
    }
  }

  private func parseEventBuffer(
    _ buffer: [UInt8],
    written: Int,
    count: Int
  ) {
    var offset = 0
    for _ in 0..<count {
      guard offset + 24 <= written else { return }
      let version = readUInt32(buffer, offset)
      let kind = readUInt32(buffer, offset + 4)
      let payloadLength = Int(readUInt32(buffer, offset + 16))
      let auxiliary = readUInt32(buffer, offset + 20)
      offset += 24
      guard version == 1, offset + payloadLength <= written else { return }
      let payload = Data(buffer[offset..<(offset + payloadLength)])
      offset += payloadLength
      switch kind {
      case 1:
        AppLogger.info(String(data: payload, encoding: .utf8) ?? "")
      case 2:
        handleMediaEvent(payload)
      case 3:
        handleUIEvent(payload, auxiliary: auxiliary)
      default:
        break
      }
    }
  }

  private func handleUIEvent(_ payload: Data, auxiliary _: UInt32) {
    guard let object = try? JSONSerialization.jsonObject(with: payload)
      as? [String: Any],
      let kind = object["kind"] as? String
    else {
      return
    }
    let body = object["payload"] as? [String: Any] ?? [:]
    switch kind {
    case "text_translate":
      guard let serialNumber = body["serial"] as? NSNumber,
            let text = body["text"] as? String
      else {
        return
      }
      let serial = serialNumber.uint64Value
      translationService?.enqueue(
        source: text,
        ruby: body["ruby"] as? String
      ) { [weak self] translated in
        self?.submitTextTranslation(serial: serial, text: translated)
      }
    case "avoid":
      avoidOverlay = (body["action"] as? String) == "show"
    case "caption":
      windowTitle = body["data"] as? String
        ?? body["caption"] as? String
        ?? body["text"] as? String
    case "write_clipboard":
      if let text = body["string"] as? String ?? body["text"] as? String {
        UIPasteboard.general.string = text
      }
    case "vibrate":
      UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    case "openbrowser":
      if let raw = body["url"] as? String, let url = URL(string: raw) {
        UIApplication.shared.open(url)
      }
    case "dialog_show":
      dialog = NativeDialogRequest(
        title: body["title"] as? String ?? "",
        message: body["message"] as? String ?? "",
        hasCancel: body["hasCancel"] as? Bool ?? false,
        hasTextField: body["textfield"] as? Bool ?? false,
        initialText: body["initialText"] as? String ?? ""
      )
    case "statusbar":
      showStatusBar = Self.asBool(body["show"])
        || Self.asBool(body["visible"])
    default:
      break
    }
  }

  private func handleMediaEvent(_ payload: Data) {
    guard let object = try? JSONSerialization.jsonObject(with: payload)
      as? [String: Any],
      let kind = object["kind"] as? String
    else {
      return
    }
    let body = object["payload"] as? [String: Any] ?? [:]
    media.handleCommand(kind: kind, payload: body)
  }

  private func submitTextTranslation(serial: UInt64, text: String?) {
    guard let runtime,
          let function = try? NativeCoreAPI.shared.function(
            .runtimeSubmitTextTranslation,
            as: RuntimeSubmitTextTranslation.self
          )
    else {
      return
    }
    (text ?? "").withCString {
      _ = function(runtime, serial, $0)
    }
  }

  private func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset])
      | (UInt32(bytes[offset + 1]) << 8)
      | (UInt32(bytes[offset + 2]) << 16)
      | (UInt32(bytes[offset + 3]) << 24)
  }

  private static func asBool(_ value: Any?) -> Bool {
    if let value = value as? Bool { return value }
    if let value = value as? NSNumber { return value.boolValue }
    if let value = value as? String {
      return value == "1" || value.lowercased() == "true"
    }
    return false
  }

  private func stopRuntime() {
    detachSharedSurface()
    releasePointerButtons()
    if let clearFont = try? NativeCoreAPI.shared.function(
      .clearFontOverride,
      as: ClearFontOverride.self
    ) {
      clearFont()
    }
    translationService?.dispose()
    translationService = nil
    media.dispose()
    if let hostEvents {
      if let destroy = try? NativeCoreAPI.shared.function(
        .hostEventsDestroy,
        as: HostEventsDestroy.self
      ) {
        destroy(hostEvents)
      }
      self.hostEvents = nil
    }
    if let runtime {
      if let destroy = try? NativeCoreAPI.shared.function(
        .runtimeDestroy,
        as: RuntimeDestroy.self
      ) {
        destroy(runtime)
      }
      self.runtime = nil
    }
    if let resources {
      if let destroy = try? NativeCoreAPI.shared.function(
        .resourcesDestroy,
        as: ResourcesDestroy.self
      ) {
        destroy(resources)
      }
      self.resources = nil
    }
    frame = nil
    pixelBuffer = []
    avoidOverlay = false
  }
}

private enum NativeRFVPSlot: Int {
  case runtimeCreate = 0
  case runtimeDestroy
  case runtimeStep
  case runtimeIsExitRequested
  case runtimeStageWidth
  case runtimeStageHeight
  case runtimeCapabilities
  case runtimePixelBufferSize
  case runtimeFeedInput
  case runtimePollAudioCommand
  case runtimeSetExternalSurface
  case runtimeClearExternalSurface
  case runtimeAdvanceAndPresent
  case runtimeAdvanceAndRender
  case runtimeSetLogCallback
  case logNextBytes
  case pollLog
  case runtimeSetTextReplacements
  case runtimeSetTextTranslationEnabled
  case runtimeSubmitTextTranslation
  case runtimeNextTextEventSize
  case runtimePollTextEvents
  case runtimeSetFontOverride
  case runtimeClearFontOverride
  case runtimeSetTraceMask
  case runtimeSetProfilerEnabled
  case runtimeProfilerSnapshot
  case runtimeSetDamageVisualization
}

private typealias RFVPGetAPI = @convention(c) (
  UnsafeMutablePointer<Int>?
) -> UnsafeRawPointer?
private typealias RFVPRuntimeCreate = @convention(c) (
  UnsafePointer<UInt8>?,
  Int,
  UnsafePointer<UInt8>?,
  Int,
  UInt32,
  UInt32,
  Int32,
  UInt32,
  UnsafeMutablePointer<UInt64>?
) -> Int32
private typealias RFVPRuntimeDestroy = @convention(c) (UInt64) -> Void
private typealias RFVPRuntimeStep = @convention(c) (
  UInt64,
  UInt32
) -> Int32
private typealias RFVPRuntimeIsExitRequested = @convention(c) (
  UInt64
) -> Int32
private typealias RFVPRuntimeStageSize = @convention(c) (UInt64) -> UInt32
private typealias RFVPRuntimeCapabilities = @convention(c) (UInt64) -> UInt64
private typealias RFVPRuntimePixelBufferSize = @convention(c) (
  UInt64
) -> UInt32
private typealias RFVPRuntimeFeedInput = @convention(c) (
  UInt64,
  UnsafeRawPointer?,
  Int
) -> Int32
private typealias RFVPRuntimePollAudioCommand = @convention(c) (
  UInt64,
  UnsafeMutableRawPointer?
) -> Int32
private typealias RFVPRuntimeSetExternalSurface = @convention(c) (
  UInt64,
  Int32,
  UnsafeMutableRawPointer?,
  UInt32,
  UInt32
) -> Int32
private typealias RFVPRuntimeClearExternalSurface = @convention(c) (
  UInt64
) -> Void
private typealias RFVPRuntimeAdvanceAndPresent = @convention(c) (
  UInt64,
  UInt32
) -> Int32
private typealias RFVPRuntimeAdvanceAndRender = @convention(c) (
  UInt64,
  UInt32,
  UnsafeMutablePointer<UInt8>?,
  UInt32
) -> UInt32
private typealias RFVPLogNextBytes = @convention(c) () -> Int
private typealias RFVPPollLog = @convention(c) (
  UnsafeMutablePointer<UInt8>?,
  Int
) -> Int
private typealias RFVPRuntimeSetFontOverride = @convention(c) (
  UInt64,
  UnsafePointer<UInt8>?,
  UInt32
) -> Int32
private typealias RFVPRuntimeClearFontOverride = @convention(c) (
  UInt64
) -> Int32
private typealias RFVPRuntimeSetProfilerEnabled = @convention(c) (
  UInt64,
  Int32
) -> Void

private final class NativeRFVPAPI {
  static let shared = NativeRFVPAPI()

  private var libraryHandle: UnsafeMutableRawPointer?
  private var apiPointer: UnsafeRawPointer?

  private init() {}

  func load() throws {
    guard apiPointer == nil else { return }
    let candidates = [
      "@rpath/art3m1s_core.framework/art3m1s_core",
      "@loader_path/Frameworks/art3m1s_core.framework/art3m1s_core",
    ]
    var loadedHandle: UnsafeMutableRawPointer?
    for candidate in candidates {
      loadedHandle = dlopen(candidate, RTLD_NOW | RTLD_LOCAL)
      if loadedHandle != nil {
        break
      }
    }
    guard let loadedHandle else {
      throw CoreBridgeError.frameworkUnavailable
    }
    guard let symbol = dlsym(loadedHandle, "art3m1s_rfvp_get_api_v1") else {
      throw CoreBridgeError.missingSymbol("art3m1s_rfvp_get_api_v1")
    }
    let getAPI = unsafeBitCast(symbol, to: RFVPGetAPI.self)
    var structSize = 0
    guard let pointer = getAPI(&structSize) else {
      throw CoreBridgeError.missingSymbol("RFVP API V1")
    }
    let abiVersion = pointer.load(fromByteOffset: 4, as: UInt32.self)
    let magic = pointer.load(fromByteOffset: 8, as: UInt64.self)
    let minimumSize =
      16 + (NativeRFVPSlot.runtimeSetDamageVisualization.rawValue + 1) * 8
    guard abiVersion == 1,
          magic == 0x315646524d334152,
          structSize >= minimumSize
    else {
      throw CoreBridgeError.missingSymbol("RFVP API V1 ABI mismatch")
    }
    libraryHandle = loadedHandle
    apiPointer = pointer
    AppLogger.info("Art3m1sCore RFVP API V1 loaded")
  }

  func function<T>(_ slot: NativeRFVPSlot, as type: T.Type) throws -> T {
    try load()
    guard let apiPointer else {
      throw CoreBridgeError.frameworkUnavailable
    }
    let offset = 16 + slot.rawValue * MemoryLayout<UnsafeRawPointer?>.size
    guard let raw = apiPointer.load(
      fromByteOffset: offset,
      as: UnsafeRawPointer?.self
    ) else {
      throw CoreBridgeError.missingSymbol("RFVP API slot \(slot.rawValue)")
    }
    return unsafeBitCast(raw, to: T.self)
  }
}

private struct NativeRFVPInputEvent {
  var structSize: UInt32
  var kind: UInt32
  var code: UInt32
  var phase: UInt32
  var x: Int32
  var y: Int32
  var value: Int32
  var modifiers: UInt32
  var id: UInt64

  init(
    kind: UInt32,
    code: UInt32 = 0,
    phase: UInt32,
    x: Int32 = 0,
    y: Int32 = 0,
    value: Int32 = 0,
    modifiers: UInt32 = 0,
    id: UInt64 = 0
  ) {
    structSize = UInt32(MemoryLayout<NativeRFVPInputEvent>.size)
    self.kind = kind
    self.code = code
    self.phase = phase
    self.x = x
    self.y = y
    self.value = value
    self.modifiers = modifiers
    self.id = id
  }
}

private enum NativeRFVPInputKind {
  static let key: UInt32 = 1
  static let pointerMove: UInt32 = 3
  static let pointerButton: UInt32 = 4
  static let wheel: UInt32 = 5
  static let touch: UInt32 = 6
  static let focus: UInt32 = 7
  static let quit: UInt32 = 8
}

private enum NativeRFVPInputPhase {
  static let down: UInt32 = 0
  static let up: UInt32 = 1
  static let move: UInt32 = 3
}

private enum NativeRFVPAudioCommand {
  static let structSize = 88
  static let statusOk: Int32 = 0
  static let statusNoCommand: Int32 = 2

  static let loadEncoded: UInt32 = 1
  static let createStream: UInt32 = 2
  static let submitI16: UInt32 = 3
  static let submitF32: UInt32 = 4
  static let play: UInt32 = 5
  static let stop: UInt32 = 6
  static let pause: UInt32 = 7
  static let resume: UInt32 = 8
  static let setParams: UInt32 = 9
  static let destroyStream: UInt32 = 10
  static let masterVolume: UInt32 = 11

  static func decode(_ data: Data) -> Decoded? {
    guard data.count >= structSize else { return nil }
    let kind = readUInt32(data, 4)
    let streamID = readUInt32(data, 8)
    let sampleFormat = readUInt32(data, 12)
    let encodedKind = readUInt32(data, 16)
    let sampleRate = readUInt32(data, 20)
    let channels = readUInt32(data, 24)
    let repeatPlayback = readUInt32(data, 28)
    let fadeMs = readUInt32(data, 32)
    let volume = readFloat(data, 36)
    let pan = readFloat(data, 40)
    let sampleCount = readUInt64(data, 48)
    let payloadPointer = readUInt64(data, 56)
    let payloadSize = readUInt64(data, 64)
    var payload = Data()
    if payloadPointer != 0, payloadSize > 0,
       let pointer = UnsafeRawPointer(bitPattern: UInt(payloadPointer)) {
      payload = Data(
        bytes: pointer,
        count: min(Int(payloadSize), 256 * 1024 * 1024)
      )
    }
    return Decoded(
      kind: kind,
      streamID: streamID,
      sampleFormat: sampleFormat,
      encodedKind: encodedKind,
      sampleRate: sampleRate,
      channels: channels,
      repeatPlayback: repeatPlayback != 0,
      fadeMs: fadeMs,
      volume: volume,
      pan: pan,
      sampleCount: sampleCount,
      payload: payload
    )
  }

  struct Decoded {
    let kind: UInt32
    let streamID: UInt32
    let sampleFormat: UInt32
    let encodedKind: UInt32
    let sampleRate: UInt32
    let channels: UInt32
    let repeatPlayback: Bool
    let fadeMs: UInt32
    let volume: Float
    let pan: Float
    let sampleCount: UInt64
    let payload: Data
  }

  private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[offset])
      | (UInt32(data[offset + 1]) << 8)
      | (UInt32(data[offset + 2]) << 16)
      | (UInt32(data[offset + 3]) << 24)
  }

  private static func readUInt64(_ data: Data, _ offset: Int) -> UInt64 {
    var value: UInt64 = 0
    for index in 0..<8 {
      value |= UInt64(data[offset + index]) << UInt64(index * 8)
    }
    return value
  }

  private static func readFloat(_ data: Data, _ offset: Int) -> Float {
    Float(bitPattern: readUInt32(data, offset))
  }
}

@MainActor
private final class NativeRFVPAudioHost {
  private struct PCMStream {
    var sampleRate: Int
    var channels: Int
    var bytes: Data
  }

  private var encoded: [UInt32: Data] = [:]
  private var pcm: [UInt32: PCMStream] = [:]
  private var handles: [UInt32: NativeAudioHandle] = [:]
  private var master = 1.0
  private var suspended = false
  private var disposed = false

  func handle(_ command: NativeRFVPAudioCommand.Decoded) {
    guard !disposed else { return }
    switch command.kind {
    case NativeRFVPAudioCommand.loadEncoded:
      pcm.removeValue(forKey: command.streamID)
      encoded[command.streamID] = command.payload
      handles.removeValue(forKey: command.streamID)?.dispose()
    case NativeRFVPAudioCommand.createStream:
      guard command.sampleRate > 0, command.channels > 0 else { return }
      encoded.removeValue(forKey: command.streamID)
      handles.removeValue(forKey: command.streamID)?.dispose()
      pcm[command.streamID] = PCMStream(
        sampleRate: Int(command.sampleRate),
        channels: Int(command.channels),
        bytes: Data()
      )
    case NativeRFVPAudioCommand.submitI16:
      pcm[command.streamID]?.bytes.append(command.payload)
    case NativeRFVPAudioCommand.submitF32:
      guard var stream = pcm[command.streamID] else { return }
      stream.bytes.append(Self.float32ToInt16(command.payload))
      pcm[command.streamID] = stream
    case NativeRFVPAudioCommand.play:
      play(command)
    case NativeRFVPAudioCommand.stop:
      guard let handle = handles.removeValue(forKey: command.streamID) else {
        return
      }
      if command.fadeMs > 0 {
        handle.fadeTo(0, durationMs: Int(command.fadeMs))
        handle.dispose(afterMilliseconds: Int(command.fadeMs))
      } else {
        handle.dispose()
      }
    case NativeRFVPAudioCommand.pause:
      handles[command.streamID]?.pause()
    case NativeRFVPAudioCommand.resume:
      handles[command.streamID]?.play()
    case NativeRFVPAudioCommand.setParams:
      guard let handle = handles[command.streamID] else { return }
      handle.gain = min(max(Double(command.volume), 0), 1)
      handle.setEffectiveVolume(effectiveVolume(handle))
      handle.panTo(Double(command.pan), durationMs: 0)
    case NativeRFVPAudioCommand.destroyStream:
      encoded.removeValue(forKey: command.streamID)
      pcm.removeValue(forKey: command.streamID)
      handles.removeValue(forKey: command.streamID)?.dispose()
    case NativeRFVPAudioCommand.masterVolume:
      master = min(max(Double(command.volume), 0), 1)
      for handle in handles.values {
        handle.setEffectiveVolume(effectiveVolume(handle))
      }
    default:
      break
    }
  }

  func setSuspended(_ value: Bool) {
    guard suspended != value else { return }
    suspended = value
    for handle in handles.values {
      handle.setHostSuspended(value)
    }
  }

  func setMasterVolume(_ value: Double) {
    master = min(max(value, 0), 1)
    for handle in handles.values {
      handle.setEffectiveVolume(effectiveVolume(handle))
    }
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    encoded.removeAll()
    pcm.removeAll()
    for handle in handles.values {
      handle.dispose()
    }
    handles.removeAll()
  }

  private func play(_ command: NativeRFVPAudioCommand.Decoded) {
    let source: Data?
    if let stream = pcm[command.streamID] {
      source = Self.makeWAV(
        pcm: stream.bytes,
        sampleRate: stream.sampleRate,
        channels: stream.channels
      )
    } else if let data = encoded[command.streamID] {
      source = try? NativeAudioDecoder.playableData(data)
    } else {
      source = nil
    }
    guard let source else {
      AppLogger.warning(
        "RFVP audio stream \(command.streamID) has no playable data"
      )
      return
    }
    do {
      let handle = try NativeAudioHandle(
        id: "rfvp:\(command.streamID)",
        source: source,
        loopSource: nil,
        channel: command.streamID < 0x1000 ? "bgm" : "se",
        gain: min(max(Double(command.volume), 0), 1),
        pan: min(max(Double(command.pan), -1), 1),
        loop: command.repeatPlayback
      )
      handles.removeValue(forKey: command.streamID)?.dispose()
      handles[command.streamID] = handle
      handle.setHostSuspended(suspended)
      let target = effectiveVolume(handle)
      handle.setEffectiveVolume(command.fadeMs > 0 ? 0 : target)
      handle.play()
      if command.fadeMs > 0 {
        handle.fadeTo(target, durationMs: Int(command.fadeMs))
      }
    } catch {
      AppLogger.warning(
        "RFVP audio stream \(command.streamID) failed: "
          + error.localizedDescription
      )
    }
  }

  private func effectiveVolume(_ handle: NativeAudioHandle) -> Double {
    min(max(master * handle.gain, 0), 1)
  }

  private static func float32ToInt16(_ data: Data) -> Data {
    guard data.count >= 4 else { return Data() }
    var floats = [Float](repeating: 0, count: data.count / 4)
    _ = floats.withUnsafeMutableBytes { destination in
      data.copyBytes(to: destination)
    }
    var samples = [Int16](repeating: 0, count: floats.count)
    for index in floats.indices {
      let value = min(max(floats[index], -1), 1)
      samples[index] = Int16(value * 32_767)
    }
    return samples.withUnsafeBytes { Data($0) }
  }

  private static func makeWAV(
    pcm: Data,
    sampleRate: Int,
    channels: Int
  ) -> Data? {
    guard !pcm.isEmpty,
          sampleRate > 0,
          channels > 0,
          pcm.count % (channels * 2) == 0
    else {
      return nil
    }
    let byteRate = sampleRate * channels * 2
    let blockAlign = channels * 2
    var output = Data(capacity: 44 + pcm.count)
    output.append(contentsOf: Array("RIFF".utf8))
    appendUInt32(UInt32(36 + pcm.count), to: &output)
    output.append(contentsOf: Array("WAVE".utf8))
    output.append(contentsOf: Array("fmt ".utf8))
    appendUInt32(16, to: &output)
    appendUInt16(1, to: &output)
    appendUInt16(UInt16(channels), to: &output)
    appendUInt32(UInt32(sampleRate), to: &output)
    appendUInt32(UInt32(byteRate), to: &output)
    appendUInt16(UInt16(blockAlign), to: &output)
    appendUInt16(16, to: &output)
    output.append(contentsOf: Array("data".utf8))
    appendUInt32(UInt32(pcm.count), to: &output)
    output.append(pcm)
    return output
  }

  private static func appendUInt16(_ value: UInt16, to data: inout Data) {
    var value = value.littleEndian
    withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
  }

  private static func appendUInt32(_ value: UInt32, to data: inout Data) {
    var value = value.littleEndian
    withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
  }
}

@MainActor
private final class NativeRFVPRuntime: ObservableObject {
  @Published private(set) var frame: CGImage?
  @Published private(set) var isRunning = false
  @Published private(set) var stageWidth = 1280
  @Published private(set) var stageHeight = 720
  @Published private(set) var hud = NativeRuntimeHUD()
  @Published var errorMessage: String?
  @Published var avoidOverlay = false
  @Published var showStatusBar = false
  @Published var shouldClose = false
  @Published private(set) var externalSurfaceKind: Int32?

  private var game: GameEntry
  private let backend: Int
  private let debugModeEnabled: Bool
  private var runtime: UInt64 = 0
  private var inputGate = InputGatePolicy.full
  private var mouseButtonsDown: Set<UInt32> = []
  private var sharedSurface: NativeSharedSurface?
  private var metalLayer: CAMetalLayer?
  private var metalLayerSize = CGSize.zero
  private var pixelBuffer: [UInt8] = []
  private var timer: Timer?
  private var nextFrameDeadline = CACurrentMediaTime()
  private var frameIndex = 0
  private var frameTimestamps: [CFTimeInterval] = []
  private var lastHUDUpdate = 0.0
  private let audio = NativeRFVPAudioHost()

  var effectiveInputGate: InputGatePolicy {
    inputGate
  }

  init(game: GameEntry, backend: Int, debugModeEnabled: Bool) {
    self.game = game
    self.backend = backend
    self.debugModeEnabled = debugModeEnabled
  }

  func start() async {
    guard !isRunning else { return }
    do {
      game = GameManifest.loadEntrySettings(game)
      guard game.engine == .rfvp else {
        throw CoreBridgeError.invalidData("当前项目不是 FVP 项目")
      }
      guard game.source == .directory else {
        throw CoreBridgeError.invalidData("FVP 暂不支持 PFS 归档项目")
      }
      try AppDataPaths.ensureInitialized()
      try NativeRFVPAPI.shared.load()
      inputGate = game.inputGate ?? .full
      let save = AppDataPaths.saves.appendingPathComponent(
        game.id,
        isDirectory: true
      )
      try FileManager.default.createDirectory(
        at: save,
        withIntermediateDirectories: true
      )
      try createRuntime(saveRoot: save.path)
      if let setProfiler = try? NativeRFVPAPI.shared.function(
        .runtimeSetProfilerEnabled,
        as: RFVPRuntimeSetProfilerEnabled.self
      ) {
        setProfiler(runtime, debugModeEnabled ? 1 : 0)
      }
      applyFontOverride()
      attachRenderSurface()
      isRunning = true
      nextFrameDeadline = CACurrentMediaTime()
      hud = NativeRuntimeHUD(
        graphicsAPI: Self.backendLabel(backend),
        zeroCopyPath: surfaceDescription,
        metalFXStatus: nil,
        residentMiB: 0,
        fps: 0
      )
      startTimer()
    } catch {
      errorMessage = error.localizedDescription
      AppLogger.error("RFVP runtime start failed: \(error.localizedDescription)")
      stop()
    }
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    isRunning = false
    clearExternalSurface()
    sharedSurface = nil
    externalSurfaceKind = nil
    frame = nil
    pixelBuffer = []
    audio.dispose()
    guard runtime != 0 else { return }
    if let destroy = try? NativeRFVPAPI.shared.function(
      .runtimeDestroy,
      as: RFVPRuntimeDestroy.self
    ) {
      destroy(runtime)
    }
    runtime = 0
  }

  func attachMetalLayer(_ layer: CAMetalLayer, size: CGSize) {
    guard size.width > 0, size.height > 0 else { return }
    metalLayer = layer
    metalLayerSize = size
    guard runtime != 0 else { return }
    attachRenderSurface()
  }

  func feedTouch(id: UInt32, phase: UInt8, point: CGPoint) {
    guard inputGate.touch else { return }
    let nativePhase: UInt32
    switch phase {
    case 0:
      nativePhase = NativeRFVPInputPhase.down
    case 2:
      nativePhase = NativeRFVPInputPhase.up
    default:
      nativePhase = NativeRFVPInputPhase.move
    }
    pushInput([
      NativeRFVPInputEvent(
        kind: NativeRFVPInputKind.touch,
        phase: nativePhase,
        x: point.x.int32Clamped,
        y: point.y.int32Clamped,
        id: UInt64(id)
      ),
    ])
  }

  func feedMouse(point: CGPoint) {
    guard inputGate.mouseMove else { return }
    pushInput([
      NativeRFVPInputEvent(
        kind: NativeRFVPInputKind.pointerMove,
        phase: NativeRFVPInputPhase.move,
        x: point.x.int32Clamped,
        y: point.y.int32Clamped
      ),
    ])
  }

  func feedMouseButton(button: UInt32, pressed: Bool) {
    guard inputGate.mouseButtons else { return }
    if pressed {
      mouseButtonsDown.insert(button)
    } else {
      mouseButtonsDown.remove(button)
    }
    let code: UInt32
    switch button {
    case 2:
      code = 2
    case 3:
      code = 4
    default:
      code = 1
    }
    pushInput([
      NativeRFVPInputEvent(
        kind: NativeRFVPInputKind.pointerButton,
        code: code,
        phase: pressed
          ? NativeRFVPInputPhase.down
          : NativeRFVPInputPhase.up
      ),
    ])
  }

  func feedClick() {
    guard inputGate.mouseButtons else { return }
    pushInput([
      NativeRFVPInputEvent(
        kind: NativeRFVPInputKind.pointerButton,
        code: 1,
        phase: NativeRFVPInputPhase.down
      ),
      NativeRFVPInputEvent(
        kind: NativeRFVPInputKind.pointerButton,
        code: 1,
        phase: NativeRFVPInputPhase.up
      ),
    ])
  }

  func feedKey(_ virtualKey: Int, pressed: Bool) {
    guard let filtered = inputGate.filterKey(virtualKey) else { return }
    pushKey(filtered, pressed: pressed)
  }

  func feedForwardedKey(_ virtualKey: Int, pressed: Bool) {
    guard let filtered = inputGate.filterForwardedKey(virtualKey) else {
      return
    }
    pushKey(filtered, pressed: pressed)
  }

  func feedWheel(deltaY: Int32) {
    guard deltaY != 0 else { return }
    pushInput([
      NativeRFVPInputEvent(
        kind: NativeRFVPInputKind.wheel,
        phase: 0,
        y: deltaY
      ),
    ])
  }

  func releasePointerButtons() {
    for button in mouseButtonsDown {
      feedMouseButton(button: button, pressed: false)
    }
    mouseButtonsDown.removeAll()
  }

  func setSuspended(_ suspended: Bool) {
    audio.setSuspended(suspended)
    pushInput([
      NativeRFVPInputEvent(
        kind: NativeRFVPInputKind.focus,
        phase: suspended ? 0 : 1
      ),
    ])
  }

  func setMasterVolume(_ value: Double) {
    audio.setMasterVolume(value)
  }

  private func createRuntime(saveRoot: String) throws {
    let create = try NativeRFVPAPI.shared.function(
      .runtimeCreate,
      as: RFVPRuntimeCreate.self
    )
    let root = Array(game.path.utf8)
    let save = Array(saveRoot.utf8)
    var handle: UInt64 = 0
    let status = root.withUnsafeBufferPointer { rootBuffer in
      save.withUnsafeBufferPointer { saveBuffer in
        create(
          rootBuffer.baseAddress,
          rootBuffer.count,
          saveBuffer.baseAddress,
          saveBuffer.count,
          UInt32(stageWidth),
          UInt32(stageHeight),
          Int32(backend),
          1,
          &handle
        )
      }
    }
    guard status == 0, handle != 0 else {
      throw CoreBridgeError.operationFailed(
        step: "RFVP runtimeCreate",
        code: status
      )
    }
    runtime = handle
    let width = try NativeRFVPAPI.shared.function(
      .runtimeStageWidth,
      as: RFVPRuntimeStageSize.self
    )(runtime)
    let height = try NativeRFVPAPI.shared.function(
      .runtimeStageHeight,
      as: RFVPRuntimeStageSize.self
    )(runtime)
    if width > 0 { stageWidth = Int(width) }
    if height > 0 { stageHeight = Int(height) }
    let capacity = try NativeRFVPAPI.shared.function(
      .runtimePixelBufferSize,
      as: RFVPRuntimePixelBufferSize.self
    )(runtime)
    pixelBuffer = [UInt8](repeating: 0, count: Int(capacity))
  }

  private func applyFontOverride() {
    var data: Data?
    if !game.fontOverrideFilePath.isEmpty {
      data = try? Data(
        contentsOf: URL(fileURLWithPath: game.fontOverrideFilePath)
      )
    }
    if data == nil, !game.fontOverridePath.isEmpty {
      data = try? Data(
        contentsOf: URL(fileURLWithPath: game.path)
          .appendingPathComponent(game.fontOverridePath)
      )
    }
    guard let data, !data.isEmpty else { return }
    guard let setFont = try? NativeRFVPAPI.shared.function(
      .runtimeSetFontOverride,
      as: RFVPRuntimeSetFontOverride.self
    ) else {
      return
    }
    let status = data.withUnsafeBytes { raw in
      setFont(
        runtime,
        raw.bindMemory(to: UInt8.self).baseAddress,
        UInt32(data.count)
      )
    }
    if status != 0 {
      AppLogger.warning("RFVP rejected font override: \(status)")
    }
  }

  private func attachRenderSurface() {
    guard runtime != 0 else { return }
    clearExternalSurface()
    externalSurfaceKind = nil
    sharedSurface = nil
    if let metalLayer,
       metalLayerSize.width > 0,
       metalLayerSize.height > 0 {
      do {
        let attach = try NativeRFVPAPI.shared.function(
          .runtimeSetExternalSurface,
          as: RFVPRuntimeSetExternalSurface.self
        )
        let status = attach(
          runtime,
          4,
          Unmanaged.passUnretained(metalLayer).toOpaque(),
          UInt32(metalLayerSize.width),
          UInt32(metalLayerSize.height)
        )
        if status == 0 {
          externalSurfaceKind = 4
          frame = nil
          AppLogger.info(
            "RFVP CAMetalLayer attached: "
              + "\(Int(metalLayerSize.width))x\(Int(metalLayerSize.height))"
          )
          return
        }
      } catch {
        AppLogger.warning(
          "RFVP CAMetalLayer unavailable: \(error.localizedDescription)"
        )
      }
    }

    do {
      let surface = try NativeSharedSurface(
        width: stageWidth,
        height: stageHeight
      )
      let attach = try NativeRFVPAPI.shared.function(
        .runtimeSetExternalSurface,
        as: RFVPRuntimeSetExternalSurface.self
      )
      let candidates: [(Int32, UnsafeMutableRawPointer)] = [
        (2, surface.ioSurfacePointer),
        (3, surface.metalTexturePointer),
      ]
      for (kind, pointer) in candidates {
        let status = attach(
          runtime,
          kind,
          pointer,
          UInt32(stageWidth),
          UInt32(stageHeight)
        )
        if status == 0 {
          sharedSurface = surface
          externalSurfaceKind = kind
          return
        }
      }
      AppLogger.warning("RFVP rejected IOSurface; using RGBA readback")
    } catch {
      AppLogger.warning(
        "RFVP IOSurface unavailable; using RGBA readback: "
          + error.localizedDescription
      )
    }
  }

  private func clearExternalSurface() {
    guard runtime != 0, externalSurfaceKind != nil else { return }
    if let clear = try? NativeRFVPAPI.shared.function(
      .runtimeClearExternalSurface,
      as: RFVPRuntimeClearExternalSurface.self
    ) {
      clear(runtime)
    }
  }

  private var surfaceDescription: String {
    switch externalSurfaceKind {
    case 4:
      return "CAMetalLayer"
    case 2:
      return "IOSurface"
    case 3:
      return "MTLTexture"
    default:
      return "RGBA 回读"
    }
  }

  private func startTimer() {
    timer?.invalidate()
    let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
      Task { @MainActor in
        self?.tick()
      }
    }
    RunLoop.main.add(timer, forMode: .common)
    self.timer = timer
  }

  private func tick() {
    guard runtime != 0 else { return }
    drainAudio()
    drainLogs()
    do {
      let requestExit = try NativeRFVPAPI.shared.function(
        .runtimeIsExitRequested,
        as: RFVPRuntimeIsExitRequested.self
      )
      if requestExit(runtime) != 0 {
        shouldClose = true
        stop()
        return
      }
      let now = CACurrentMediaTime()
      let target = 1.0 / 60.0
      guard now >= nextFrameDeadline else { return }
      let overdue = now - nextFrameDeadline
      let dueTicks = min(max(1 + Int(overdue / target), 1), 8)
      nextFrameDeadline += target * Double(dueTicks)
      if now - nextFrameDeadline > target * 2 {
        nextFrameDeadline = now + target
      }
      for _ in 0..<max(dueTicks - 1, 0) {
        advanceWithoutRender(deltaMs: nextFrameDeltaMs())
      }
      let deltaMs = nextFrameDeltaMs()
      if externalSurfaceKind != nil {
        let present = try NativeRFVPAPI.shared.function(
          .runtimeAdvanceAndPresent,
          as: RFVPRuntimeAdvanceAndPresent.self
        )
        let result = present(runtime, deltaMs)
        if result >= 0 {
          if externalSurfaceKind == 2 || externalSurfaceKind == 3 {
            if result > 0, let image = sharedSurface?.makeCGImage() {
              frame = image
            }
          }
          updateHUD(now: now)
          drainAudio()
          drainLogs()
          return
        }
        AppLogger.warning(
          "RFVP shared surface present failed (\(result)); using RGBA"
        )
        clearExternalSurface()
        sharedSurface = nil
        externalSurfaceKind = nil
      }
      let written = advanceAndRender(deltaMs: deltaMs)
      if written > 0 {
        frame = makeImage(from: pixelBuffer, count: written)
      }
      updateHUD(now: now)
    } catch {
      errorMessage = error.localizedDescription
      stop()
    }
  }

  private func advanceWithoutRender(deltaMs: UInt32) {
    guard runtime != 0,
          let step = try? NativeRFVPAPI.shared.function(
            .runtimeStep,
            as: RFVPRuntimeStep.self
          )
    else {
      return
    }
    _ = step(runtime, deltaMs)
    drainAudio()
  }

  private func advanceAndRender(deltaMs: UInt32) -> Int {
    guard runtime != 0,
          let render = try? NativeRFVPAPI.shared.function(
            .runtimeAdvanceAndRender,
            as: RFVPRuntimeAdvanceAndRender.self
          )
    else {
      return 0
    }
    return pixelBuffer.withUnsafeMutableBytes { raw in
      Int(
        render(
          runtime,
          deltaMs,
          raw.bindMemory(to: UInt8.self).baseAddress,
          UInt32(pixelBuffer.count)
        )
      )
    }
  }

  private func drainAudio() {
    guard runtime != 0,
          let poll = try? NativeRFVPAPI.shared.function(
            .runtimePollAudioCommand,
            as: RFVPRuntimePollAudioCommand.self
          )
    else {
      return
    }
    var guardCount = 0
    while guardCount < 4096 {
      guardCount += 1
      var raw = [UInt8](
        repeating: 0,
        count: NativeRFVPAudioCommand.structSize
      )
      let status = raw.withUnsafeMutableBytes { buffer in
        poll(runtime, buffer.baseAddress)
      }
      if status == NativeRFVPAudioCommand.statusNoCommand {
        return
      }
      guard status == NativeRFVPAudioCommand.statusOk,
            let command = NativeRFVPAudioCommand.decode(Data(raw))
      else {
        return
      }
      audio.handle(command)
    }
  }

  private func drainLogs() {
    guard let next = try? NativeRFVPAPI.shared.function(
      .logNextBytes,
      as: RFVPLogNextBytes.self
    ), let poll = try? NativeRFVPAPI.shared.function(
      .pollLog,
      as: RFVPPollLog.self
    ) else {
      return
    }
    var guardCount = 0
    while guardCount < 1024 {
      guardCount += 1
      let required = next()
      guard required >= 8 else { return }
      var bytes = [UInt8](repeating: 0, count: required)
      let written = bytes.withUnsafeMutableBytes { raw in
        poll(raw.bindMemory(to: UInt8.self).baseAddress, required)
      }
      guard written >= 8 else { return }
      var offset = 0
      while offset + 8 <= written {
        let level = readUInt32(bytes, offset)
        let length = Int(readUInt32(bytes, offset + 4))
        guard offset + 8 + length <= written else { break }
        let message = String(
          bytes: bytes[(offset + 8)..<(offset + 8 + length)],
          encoding: .utf8
        ) ?? ""
        switch level {
        case 69:
          AppLogger.error("[RFVP] \(message)")
        case 87:
          AppLogger.warning("[RFVP] \(message)")
        case 68:
          AppLogger.debug("[RFVP] \(message)")
        default:
          AppLogger.info("[RFVP] \(message)")
        }
        offset += 8 + length
      }
    }
  }

  private func pushKey(_ key: Int, pressed: Bool) {
    pushInput([
      NativeRFVPInputEvent(
        kind: NativeRFVPInputKind.key,
        code: UInt32(truncatingIfNeeded: key),
        phase: pressed
          ? NativeRFVPInputPhase.down
          : NativeRFVPInputPhase.up
      ),
    ])
  }

  private func pushInput(_ events: [NativeRFVPInputEvent]) {
    guard runtime != 0, !events.isEmpty else { return }
    guard let feed = try? NativeRFVPAPI.shared.function(
      .runtimeFeedInput,
      as: RFVPRuntimeFeedInput.self
    ) else {
      return
    }
    let status = events.withUnsafeBufferPointer { buffer in
      feed(
        runtime,
        buffer.baseAddress,
        events.count
      )
    }
    if status != 0 {
      AppLogger.warning("RFVP input rejected: \(status)")
    }
  }

  private func nextFrameDeltaMs() -> UInt32 {
    let previous = (frameIndex * 1_000) / 60
    frameIndex += 1
    let current = (frameIndex * 1_000) / 60
    return UInt32(max(current - previous, 1))
  }

  private func updateHUD(now: CFTimeInterval) {
    frameTimestamps.append(now)
    frameTimestamps.removeAll { now - $0 > 1.0 }
    guard now - lastHUDUpdate >= 0.5 else { return }
    let sample = NativeGameRuntime.processSample()
    lastHUDUpdate = now
    hud = NativeRuntimeHUD(
      graphicsAPI: Self.backendLabel(backend),
      zeroCopyPath: surfaceDescription,
      metalFXStatus: nil,
      residentMiB: Double(sample.residentBytes) / 1_048_576,
      fps: Double(frameTimestamps.count)
    )
  }

  private func makeImage(from bytes: [UInt8], count: Int) -> CGImage? {
    let required = stageWidth * stageHeight * 4
    guard required > 0,
          count >= required,
          let provider = CGDataProvider(
            data: Data(bytes.prefix(required)) as CFData
          )
    else {
      return nil
    }
    return CGImage(
      width: stageWidth,
      height: stageHeight,
      bitsPerComponent: 8,
      bitsPerPixel: 32,
      bytesPerRow: stageWidth * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(
        rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
      ),
      provider: provider,
      decode: nil,
      shouldInterpolate: false,
      intent: .defaultIntent
    )
  }

  private static func backendLabel(_ backend: Int) -> String {
    switch backend {
    case 3:
      return "Metal"
    case 6:
      return "ANGLE / Metal"
    case 1:
      return "ANGLE / OpenGL ES"
    case 0:
      return "自动"
    default:
      return "Backend \(backend)"
    }
  }
}

@MainActor
final class NativePlayerRuntime: ObservableObject {
  private let art3m1s: NativeGameRuntime
  private let rfvp: NativeRFVPRuntime
  private let usesRFVP: Bool
  private var observers: [AnyCancellable] = []

  init(
    game: GameEntry,
    backend: Int,
    translationSettings: TranslationSettings,
    renderUpscalingEnabled: Bool,
    debugModeEnabled: Bool
  ) {
    let resolved = GameManifest.loadEntrySettings(game)
    usesRFVP = resolved.engine == .rfvp
    art3m1s = NativeGameRuntime(
      game: resolved,
      backend: backend,
      translationSettings: translationSettings,
      renderUpscalingEnabled: renderUpscalingEnabled,
      debugModeEnabled: debugModeEnabled
    )
    rfvp = NativeRFVPRuntime(
      game: resolved,
      backend: backend,
      debugModeEnabled: debugModeEnabled
    )
    observers = [
      art3m1s.objectWillChange.sink { [weak self] _ in
        self?.objectWillChange.send()
      },
      rfvp.objectWillChange.sink { [weak self] _ in
        self?.objectWillChange.send()
      },
    ]
    AppLogger.info(
      "Player runtime selected: \(usesRFVP ? "RFVP" : "Artemis")"
    )
  }

  var frame: CGImage? {
    usesRFVP ? rfvp.frame : art3m1s.frame
  }

  var isRunning: Bool {
    usesRFVP ? rfvp.isRunning : art3m1s.isRunning
  }

  var stageWidth: Int {
    usesRFVP ? rfvp.stageWidth : art3m1s.stageWidth
  }

  var stageHeight: Int {
    usesRFVP ? rfvp.stageHeight : art3m1s.stageHeight
  }

  var hud: NativeRuntimeHUD {
    usesRFVP ? rfvp.hud : art3m1s.hud
  }

  var errorMessage: String? {
    usesRFVP ? rfvp.errorMessage : art3m1s.errorMessage
  }

  var avoidOverlay: Bool {
    usesRFVP ? rfvp.avoidOverlay : art3m1s.avoidOverlay
  }

  var showStatusBar: Bool {
    usesRFVP ? rfvp.showStatusBar : art3m1s.showStatusBar
  }

  var shouldClose: Bool {
    usesRFVP ? rfvp.shouldClose : art3m1s.shouldClose
  }

  var dialog: NativeDialogRequest? {
    usesRFVP ? nil : art3m1s.dialog
  }

  var externalSurfaceKind: Int32? {
    usesRFVP ? rfvp.externalSurfaceKind : art3m1s.externalSurfaceKind
  }

  var effectiveInputGate: InputGatePolicy {
    usesRFVP ? rfvp.effectiveInputGate : art3m1s.effectiveInputGate
  }

  func start() async {
    if usesRFVP {
      await rfvp.start()
    } else {
      await art3m1s.start()
    }
  }

  func stop() {
    if usesRFVP {
      rfvp.stop()
    } else {
      art3m1s.stop()
    }
  }

  func attachMetalLayer(_ layer: CAMetalLayer, size: CGSize) {
    if usesRFVP {
      rfvp.attachMetalLayer(layer, size: size)
    } else {
      art3m1s.attachMetalLayer(layer, size: size)
    }
  }

  func feedTouch(id: UInt32, phase: UInt8, point: CGPoint) {
    if usesRFVP {
      rfvp.feedTouch(id: id, phase: phase, point: point)
    } else {
      art3m1s.feedTouch(id: id, phase: phase, point: point)
    }
  }

  func feedMouse(point: CGPoint) {
    if usesRFVP {
      rfvp.feedMouse(point: point)
    } else {
      art3m1s.feedMouse(point: point)
    }
  }

  func feedMouseButton(button: UInt32, pressed: Bool) {
    if usesRFVP {
      rfvp.feedMouseButton(button: button, pressed: pressed)
    } else {
      art3m1s.feedMouseButton(button: button, pressed: pressed)
    }
  }

  func feedKey(_ key: Int, pressed: Bool) {
    if usesRFVP {
      rfvp.feedKey(key, pressed: pressed)
    } else {
      art3m1s.feedKey(key, pressed: pressed)
    }
  }

  func feedForwardedKey(_ key: Int, pressed: Bool) {
    if usesRFVP {
      rfvp.feedForwardedKey(key, pressed: pressed)
    } else {
      art3m1s.feedForwardedKey(key, pressed: pressed)
    }
  }

  func feedWheel(_ key: Int) {
    if usesRFVP {
      switch key {
      case 136:
        rfvp.feedWheel(deltaY: 1)
      case 137:
        rfvp.feedWheel(deltaY: -1)
      default:
        break
      }
    } else {
      art3m1s.feedWheel(key)
    }
  }

  func submitDialog(accepted: Bool, text: String) {
    if !usesRFVP {
      art3m1s.submitDialog(accepted: accepted, text: text)
    }
  }

  func setSuspended(_ suspended: Bool) {
    if usesRFVP {
      rfvp.setSuspended(suspended)
    } else {
      art3m1s.setSuspended(suspended)
    }
  }

  func setMasterVolume(_ value: Double) {
    if usesRFVP {
      rfvp.setMasterVolume(value)
    } else {
      art3m1s.setMasterVolume(value)
    }
  }
}

private extension CGFloat {
  var int32Clamped: Int32 {
    Int32(
      Swift.min(Swift.max(self, CGFloat(Int32.min)), CGFloat(Int32.max))
    )
  }
}

private func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
  UInt32(bytes[offset])
    | (UInt32(bytes[offset + 1]) << 8)
    | (UInt32(bytes[offset + 2]) << 16)
    | (UInt32(bytes[offset + 3]) << 24)
}
