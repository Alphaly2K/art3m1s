import AVFoundation
import Combine
import Darwin
import Foundation
import QuartzCore
import UIKit

private typealias SiglusGetAPI = @convention(c) (UnsafeMutablePointer<Int>?) -> UnsafeRawPointer?
private typealias SiglusCreate = @convention(c) (UnsafePointer<CChar>?, Int32, UnsafeMutablePointer<UInt64>?) -> Int32
private typealias SiglusAction = @convention(c) (UInt64) -> Int32
private typealias SiglusDestroy = @convention(c) (UInt64) -> Void
private typealias SiglusStage = @convention(c) (UInt64) -> UInt32
private typealias SiglusSurface = @convention(c) (UInt64, Int32, UnsafeMutableRawPointer?, UInt32, UInt32) -> Int32
private typealias SiglusTick = @convention(c) (UInt64, UInt32, Int32, UnsafeMutablePointer<UInt8>?, Int, UnsafeMutablePointer<Int>?) -> Int32
private typealias SiglusInput = @convention(c) (UInt64, Int32, Int32, Int32, Int32, Int32) -> Int32
private typealias SiglusSetFlag = @convention(c) (UInt64, Int32) -> Int32
private typealias SiglusSetVolume = @convention(c) (UInt64, Float) -> Int32
private typealias SiglusError = @convention(c) (UnsafeMutablePointer<UInt8>?, Int) -> Int

private final class SiglusAPI {
  static let shared = SiglusAPI()
  private var api: UnsafeRawPointer?
  private var output: UnsafeRawPointer?
  private var diagnostics: UnsafeRawPointer?

  func load() throws {
    guard api == nil else { return }
    let handle = try CoreBridge.shared.symbol("art3m1s_siglus_get_api_v1")
    let get = unsafeBitCast(handle, to: SiglusGetAPI.self)
    var size = 0
    guard let table = get(&size), size == 96,
          table.load(as: UInt32.self) == UInt32(size),
          table.load(fromByteOffset: 4, as: UInt32.self) == 1,
          table.load(fromByteOffset: 8, as: UInt32.self) == 0x53494731 else {
      throw CoreBridgeError.invalidData("Siglus API V1 ABI mismatch")
    }
    let outputGet = unsafeBitCast(try CoreBridge.shared.symbol("art3m1s_siglus_get_output_api_v1"), to: SiglusGetAPI.self)
    var outputSize = 0
    guard let outputTable = outputGet(&outputSize), outputSize == 56,
          outputTable.load(as: UInt32.self) == UInt32(outputSize),
          outputTable.load(fromByteOffset: 4, as: UInt32.self) == 1,
          outputTable.load(fromByteOffset: 8, as: UInt64.self) == 0x31564f534d334152 else {
      throw CoreBridgeError.invalidData("Siglus output API V1 ABI mismatch")
    }
    if let symbol = try? CoreBridge.shared.symbol("art3m1s_siglus_get_diagnostics_api_v1") {
      var count = 0
      let pointer = unsafeBitCast(symbol, to: SiglusGetAPI.self)(&count)
      if let pointer, count == 40,
         pointer.load(as: UInt32.self) == UInt32(count),
         pointer.load(fromByteOffset: 4, as: UInt32.self) == 1,
         pointer.load(fromByteOffset: 8, as: UInt64.self) == 0x315647534d334152 {
        diagnostics = pointer
      }
    }
    api = table
    output = outputTable
  }

  func function<T>(_ slot: Int, as type: T.Type) throws -> T {
    try load()
    return try function(api, slot: slot, as: type)
  }

  func outputFunction<T>(_ slot: Int, as type: T.Type) throws -> T {
    try load()
    return try function(output, slot: slot, as: type)
  }

  private func function<T>(_ table: UnsafeRawPointer?, slot: Int, as type: T.Type) throws -> T {
    guard let pointer = table?.load(fromByteOffset: 16 + slot * 8, as: UnsafeRawPointer?.self) else {
      throw CoreBridgeError.missingSymbol("Siglus API slot \(slot)")
    }
    return unsafeBitCast(pointer, to: type)
  }

  var lastError: String {
    guard let get = try? function(9, as: SiglusError.self) else { return "" }
    let count = get(nil, 0)
    guard count > 0, count <= 65536 else { return "" }
    var bytes = [UInt8](repeating: 0, count: count)
    let written = bytes.withUnsafeMutableBufferPointer { get($0.baseAddress, $0.count) }
    return String(decoding: bytes.prefix(min(max(written, 0), count)), as: UTF8.self)
  }

  func setDebug(_ runtime: UInt64, enabled: Bool) {
    if let set = try? function(diagnostics, slot: 2, as: SiglusSetFlag.self) {
      _ = set(runtime, enabled ? 1 : 0)
    }
  }

  func drainLogs() {
    typealias Next = @convention(c) () -> Int
    typealias Poll = @convention(c) (UnsafeMutablePointer<UInt8>?, Int) -> Int
    guard let next = try? function(diagnostics, slot: 0, as: Next.self),
          let poll = try? function(diagnostics, slot: 1, as: Poll.self) else { return }
    for _ in 0..<8 {
      let required = next()
      guard required > 0, required <= 16 * 1024 + 8 else { return }
      var bytes = [UInt8](repeating: 0, count: 64 * 1024)
      let written = bytes.withUnsafeMutableBufferPointer { poll($0.baseAddress, $0.count) }
      guard written > 0, written <= bytes.count else { return }
      var offset = 0
      while offset + 8 <= written {
        let level = Self.uint32(bytes, offset)
        let length = Int(Self.uint32(bytes, offset + 4))
        guard length <= 16 * 1024, offset + 8 + length <= written else { return }
        let message = "[Siglus] " + String(decoding: bytes[(offset + 8)..<(offset + 8 + length)], as: UTF8.self)
        switch level {
        case 69: AppLogger.error(message)
        case 87: AppLogger.warning(message)
        case 68: AppLogger.debug(message)
        default: AppLogger.info(message)
        }
        offset += 8 + length
      }
    }
  }

  private static func uint32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
    UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
      | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
  }
}

@MainActor
final class NativeSiglusRuntime: ObservableObject {
  @Published private(set) var frame: CGImage?
  @Published private(set) var isRunning = false
  @Published private(set) var stageWidth = 1280
  @Published private(set) var stageHeight = 720
  @Published private(set) var hud = NativeRuntimeHUD()
  @Published private(set) var externalSurfaceKind: Int32?
  @Published private(set) var errorMessage: String?
  @Published private(set) var shouldClose = false
  private let game: GameEntry
  private let backend: Int
  private let debug: Bool
  private var runtime: UInt64 = 0
  private var timer: Timer?
  private var suspended = false
  private var audioSessionActive = false
  private var pointer = CGPoint.zero
  private var buttons: Set<UInt32> = []
  private var touchID: UInt32?
  private var keys: Set<Int> = []
  private var surface: NativeSharedSurface?
  private var layer: CAMetalLayer?
  private var layerSize = CGSize.zero
  private var pixels = [UInt8]()
  private var frameIndex: UInt64 = 0
  private var nextDeadline = CACurrentMediaTime()
  private var timestamps: [CFTimeInterval] = []
  private var lastHUDUpdate = 0.0
  var effectiveInputGate: InputGatePolicy { game.inputGate ?? .full }
  var avoidOverlay: Bool { false }
  var showStatusBar: Bool { false }

  init(game: GameEntry, backend: Int, debugModeEnabled: Bool) {
    self.game = game
    self.backend = backend
    debug = debugModeEnabled
  }

  func start() async {
    guard runtime == 0, !isRunning else { return }
    do {
      guard game.source == .directory else { throw CoreBridgeError.invalidData("Siglus 不支持 PFS 归档项目") }
      try SiglusAPI.shared.load()
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
      try AVAudioSession.sharedInstance().setActive(true)
      audioSessionActive = true
      let create = try SiglusAPI.shared.function(1, as: SiglusCreate.self)
      let result = game.path.withCString { create($0, Int32(clamping: backend), &runtime) }
      try check(result, step: "创建 Siglus runtime")
      stageWidth = Int(try SiglusAPI.shared.function(3, as: SiglusStage.self)(runtime))
      stageHeight = Int(try SiglusAPI.shared.function(4, as: SiglusStage.self)(runtime))
      guard stageWidth > 0, stageHeight > 0, stageWidth <= 16384, stageHeight <= 16384,
            stageWidth * stageHeight <= 64 * 1024 * 1024 else {
        throw CoreBridgeError.invalidData("Siglus 返回无效画面尺寸")
      }
      pixels = [UInt8](repeating: 0, count: stageWidth * stageHeight * 4)
      SiglusAPI.shared.setDebug(runtime, enabled: debug)
      try check(try SiglusAPI.shared.outputFunction(0, as: SiglusAction.self)(runtime), step: "启动 Siglus 音频")
      attachSurface()
      errorMessage = nil
      shouldClose = false
      frameIndex = 0
      nextDeadline = CACurrentMediaTime()
      isRunning = true
      setSuspended(suspended)
      let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
        Task { @MainActor in self?.tick() }
      }
      RunLoop.main.add(timer, forMode: .common)
      self.timer = timer
    } catch {
      errorMessage = error.localizedDescription
      stop()
    }
    SiglusAPI.shared.drainLogs()
  }

  func stop() {
    timer?.invalidate()
    timer = nil
    isRunning = false
    defer {
      if audioSessionActive {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        audioSessionActive = false
      }
    }
    guard runtime != 0 else { return }
    releaseInputs()
    detachSurface()
    if let destroy = try? SiglusAPI.shared.function(2, as: SiglusDestroy.self) { destroy(runtime) }
    runtime = 0
    surface = nil
    pixels.removeAll()
    frame = nil
    SiglusAPI.shared.drainLogs()
  }

  func attachMetalLayer(_ layer: CAMetalLayer, size: CGSize) {
    guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else { return }
    self.layer = layer
    layerSize = size
    if runtime != 0 { attachSurface() }
  }

  private func attachSurface() {
    detachSurface()
    guard runtime != 0, let attach = try? SiglusAPI.shared.function(5, as: SiglusSurface.self) else { return }
    if let layer, layerSize.width > 0, layerSize.height > 0,
       layerSize.width <= 16384, layerSize.height <= 16384,
       attach(runtime, 4, Unmanaged.passUnretained(layer).toOpaque(), UInt32(layerSize.width), UInt32(layerSize.height)) == 0 {
      externalSurfaceKind = 4
      return
    }
    if let shared = try? NativeSharedSurface(width: stageWidth, height: stageHeight) {
      for (kind, pointer) in [(Int32(2), shared.ioSurfacePointer), (Int32(3), shared.metalTexturePointer)] {
        if attach(runtime, kind, pointer, UInt32(stageWidth), UInt32(stageHeight)) == 0 {
          surface = shared
          externalSurfaceKind = kind
          return
        }
      }
    }
  }

  private func detachSurface() {
    if runtime != 0, let detach = try? SiglusAPI.shared.function(5, as: SiglusSurface.self) {
      _ = detach(runtime, 0, nil, 0, 0)
    }
    externalSurfaceKind = nil
    surface = nil
  }

  private func tick() {
    guard runtime != 0, isRunning, !suspended else { return }
    do {
      let now = CACurrentMediaTime()
      guard now >= nextDeadline else { return }
      let count = min(max(1 + Int((now - nextDeadline) * 60), 1), 8)
      nextDeadline += Double(count) / 60
      if now - nextDeadline > 1.0 / 30 { nextDeadline = now + 1.0 / 60 }
      let tick = try SiglusAPI.shared.function(6, as: SiglusTick.self)
      for index in 0..<count {
        let before = frameIndex * 1000 / 60
        frameIndex += 1
        let delta = UInt32(frameIndex * 1000 / 60 - before)
        let mode: Int32 = index < count - 1 ? 0 : externalSurfaceKind == nil ? 1 : 2
        var written = 0
        let status = pixels.withUnsafeMutableBufferPointer {
          tick(runtime, delta, mode, mode == 1 ? $0.baseAddress : nil, mode == 1 ? $0.count : 0, &written)
        }
        if status != 0, mode == 2 { detachSurface(); continue }
        try check(status, step: "推进 Siglus runtime")
        if mode == 1, written == pixels.count { frame = makeImage() }
        if mode == 2, externalSurfaceKind != 4 { frame = surface?.makeCGImage() }
        if try SiglusAPI.shared.function(8, as: SiglusAction.self)(runtime) != 0 {
          shouldClose = true
          stop()
          return
        }
      }
      SiglusAPI.shared.drainLogs()
      timestamps.append(now)
      timestamps.removeAll { now - $0 > 1 }
      if now - lastHUDUpdate >= 0.5 {
        lastHUDUpdate = now
        hud = NativeRuntimeHUD(graphicsAPI: "Siglus", zeroCopyPath: externalSurfaceKind.map { "共享表面 \($0)" } ?? "RGBA 回读", metalFXStatus: nil, residentMiB: 0, fps: Double(timestamps.count))
      }
    } catch {
      errorMessage = error.localizedDescription
      stop()
    }
  }

  private func makeImage() -> CGImage? {
    guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
    return CGImage(width: stageWidth, height: stageHeight, bitsPerComponent: 8, bitsPerPixel: 32,
      bytesPerRow: stageWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
      provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
  }

  private func check(_ status: Int32, step: String) throws {
    if status != 0 { throw CoreBridgeError.invalidData("\(step)失败（\(status)）：\(SiglusAPI.shared.lastError)") }
  }

  private func input(_ kind: Int32, _ code: Int32, _ x: Int32 = 0, _ y: Int32 = 0, _ value: Int32 = 0) {
    guard runtime != 0, let feed = try? SiglusAPI.shared.function(7, as: SiglusInput.self) else { return }
    _ = feed(runtime, kind, code, x, y, value)
  }

  private func coordinate(_ value: CGFloat) -> Int32 {
    Int32(min(max(value, CGFloat(Int32.min)), CGFloat(Int32.max)))
  }

  func feedMouse(point: CGPoint) {
    guard !suspended, effectiveInputGate.mouseMove, point.x.isFinite, point.y.isFinite else { return }
    pointer = point
    input(0, 0, coordinate(point.x), coordinate(point.y))
  }
  func feedMouseButton(button: UInt32, pressed: Bool) {
    guard !suspended, effectiveInputGate.mouseButtons else { return }
    if pressed { buttons.insert(button) } else { buttons.remove(button) }
    input(1, Int32(clamping: button), coordinate(pointer.x), coordinate(pointer.y), pressed ? 1 : 0)
  }
  func feedTouch(id: UInt32, phase: UInt8, point: CGPoint) {
    guard !suspended, effectiveInputGate.touch, point.x.isFinite, point.y.isFinite else { return }
    if phase == 0, touchID == nil { touchID = id }
    guard touchID == id else { return }
    if phase >= 2 { touchID = nil }
    pointer = point
    input(2, Int32(phase), coordinate(point.x), coordinate(point.y))
  }
  func feedKey(_ key: Int, pressed: Bool) {
    guard !suspended, let key = effectiveInputGate.filterKey(key) else { return }
    if pressed { keys.insert(key) } else { keys.remove(key) }
    input(3, Int32(clamping: key), 0, 0, pressed ? 1 : 0)
  }
  func feedForwardedKey(_ key: Int, pressed: Bool) {
    guard !suspended, let key = effectiveInputGate.filterForwardedKey(key) else { return }
    if key == 136 || key == 137 {
      if pressed { feedWheel(key) }
      return
    }
    if pressed { keys.insert(key) } else { keys.remove(key) }
    input(3, Int32(clamping: key), 0, 0, pressed ? 1 : 0)
  }
  func feedWheel(_ key: Int) {
    guard !suspended else { return }
    input(4, 0, 0, 0, key == 136 ? 1 : -1)
  }
  private func releaseInputs() {
    for button in buttons { input(1, Int32(clamping: button), 0, 0, 0) }
    buttons.removeAll()
    for key in keys { input(3, Int32(clamping: key), 0, 0, 0) }
    keys.removeAll()
    if touchID != nil { input(2, 3, coordinate(pointer.x), coordinate(pointer.y)) }
    touchID = nil
  }
  func setSuspended(_ value: Bool) {
    suspended = value
    nextDeadline = CACurrentMediaTime()
    if value { releaseInputs() }
    if runtime != 0, let suspend = try? SiglusAPI.shared.outputFunction(2, as: SiglusSetFlag.self) {
      _ = suspend(runtime, value ? 1 : 0)
    }
  }
  func setMasterVolume(_ value: Double) {
    guard value.isFinite, runtime != 0, let volume = try? SiglusAPI.shared.outputFunction(3, as: SiglusSetVolume.self) else { return }
    _ = volume(runtime, Float(min(max(value, 0), 1)))
  }
}
