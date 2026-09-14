import Darwin
import Foundation
import OSLog
import QuartzCore

@MainActor
final class SettingsStore: ObservableObject {
  @Published var mobileTouchpadEnabled: Bool {
    didSet {
      defaults.set(mobileTouchpadEnabled, forKey: "mobile_touchpad_enabled")
    }
  }
  @Published var crashReportingEnabled: Bool {
    didSet {
      defaults.set(crashReportingEnabled, forKey: "crash_reporting_enabled")
    }
  }
  @Published var runtimeHUDEnabled: Bool {
    didSet {
      defaults.set(runtimeHUDEnabled, forKey: "runtime_hud_enabled")
    }
  }
  @Published var backend: Int {
    didSet { defaults.set(backend, forKey: "gfx_backend") }
  }
  @Published var renderUpscalingEnabled: Bool {
    didSet {
      defaults.set(
        renderUpscalingEnabled,
        forKey: "render_upscaling_enabled"
      )
    }
  }
  @Published var debugModeEnabled: Bool {
    didSet {
      defaults.set(debugModeEnabled, forKey: "debug_mode_enabled")
      ProfilerSession.shared.setEnabled(debugModeEnabled)
      CoreBridge.shared.setDebugEnabled(debugModeEnabled)
    }
  }
  @Published var translation: TranslationSettings {
    didSet { saveTranslation() }
  }

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    mobileTouchpadEnabled = defaults.bool(forKey: "mobile_touchpad_enabled")
    crashReportingEnabled = defaults.bool(forKey: "crash_reporting_enabled")
    runtimeHUDEnabled = defaults.object(forKey: "runtime_hud_enabled") as? Bool
      ?? true
    backend = defaults.object(forKey: "gfx_backend") as? Int ?? 3
    renderUpscalingEnabled =
      defaults.object(forKey: "render_upscaling_enabled") as? Bool ?? true
    debugModeEnabled =
      defaults.object(forKey: "debug_mode_enabled") as? Bool ?? false

    let mode = TranslationMode(
      rawValue: defaults.string(forKey: "translation_mode") ?? ""
    ) ?? .off
    let provider = TranslationProvider(
      rawValue: Self.providerKey(defaults.string(forKey: "translation_provider"))
    ) ?? .openAi
    translation = TranslationSettings(
      mode: mode,
      provider: provider,
      endpoint: defaults.string(forKey: "translation_endpoint")
        ?? provider.defaultEndpoint,
      apiKey: defaults.string(forKey: "translation_api_key") ?? "",
      appID: defaults.string(forKey: "translation_app_id") ?? "",
      appSecret: defaults.string(forKey: "translation_app_secret") ?? "",
      model: defaults.string(forKey: "translation_model")
        ?? provider.defaultModel,
      sourceLanguage: defaults.string(forKey: "translation_source_language")
        ?? "日语",
      targetLanguage: defaults.string(forKey: "translation_target_language")
        ?? "简体中文"
    )
  }

  static var preview: SettingsStore {
    SettingsStore(defaults: UserDefaults(suiteName: "Art3m1sNativePreview") ?? .standard)
  }

  func activateDebugMode() {
    ProfilerSession.shared.setEnabled(debugModeEnabled)
    CoreBridge.shared.setDebugEnabled(debugModeEnabled)
  }

  var availableBackends: [BackendOption] {
    [
      BackendOption(value: 3, label: "原生 Metal"),
      BackendOption(value: 6, label: "ANGLE / Metal"),
      BackendOption(value: 1, label: "ANGLE / OpenGL ES"),
    ]
  }

  private func saveTranslation() {
    defaults.set(translation.mode.rawValue, forKey: "translation_mode")
    defaults.set(translation.provider.rawValue, forKey: "translation_provider")
    defaults.set(translation.endpoint, forKey: "translation_endpoint")
    defaults.set(translation.apiKey, forKey: "translation_api_key")
    defaults.set(translation.appID, forKey: "translation_app_id")
    defaults.set(translation.appSecret, forKey: "translation_app_secret")
    defaults.set(translation.model, forKey: "translation_model")
    defaults.set(
      translation.sourceLanguage,
      forKey: "translation_source_language"
    )
    defaults.set(
      translation.targetLanguage,
      forKey: "translation_target_language"
    )
  }

  private static func providerKey(_ value: String?) -> String {
    switch value {
    case "openai": "openAi"
    case "deepl": "deepL"
    default: value ?? ""
    }
  }
}

struct ProfilerReport: Codable {
  let generatedAt: Date
  let processUptimeSeconds: Double
  let frameSamples: Int
  let frameTimeMilliseconds: FrameTimeStatistics
  let memory: MemoryStatistics
}

struct FrameTimeStatistics: Codable {
  let minimum: Double
  let average: Double
  let p50: Double
  let p95: Double
  let p99: Double
  let maximum: Double
  let estimatedFPS: Double
}

struct MemoryStatistics: Codable {
  let residentBytes: UInt64
  let virtualBytes: UInt64
  let residentMiB: Double
  let virtualMiB: Double
}

@MainActor
final class ProfilerSession: NSObject {
  static let shared = ProfilerSession()

  private var displayLink: CADisplayLink?
  private var lastTimestamp: CFTimeInterval?
  private var frameTimes: [Double] = []
  private let maximumSamples = 600

  private override init() {
    super.init()
  }

  func start() {
    guard displayLink == nil else { return }
    let link = CADisplayLink(target: self, selector: #selector(handleFrame))
    link.preferredFrameRateRange = CAFrameRateRange(
      minimum: 30,
      maximum: 120,
      preferred: 120
    )
    link.add(to: .main, forMode: .common)
    displayLink = link
  }

  func setEnabled(_ enabled: Bool) {
    if enabled {
      start()
    } else {
      stop()
    }
  }

  func stop() {
    displayLink?.invalidate()
    displayLink = nil
    lastTimestamp = nil
    frameTimes.removeAll()
  }

  func makeReport() -> ProfilerReport {
    let values = frameTimes
    let sorted = values.sorted()
    let average = sorted.isEmpty
      ? 0
      : sorted.reduce(0, +) / Double(sorted.count)
    let memory = Self.memorySnapshot()

    return ProfilerReport(
      generatedAt: .now,
      processUptimeSeconds: ProcessInfo.processInfo.systemUptime,
      frameSamples: sorted.count,
      frameTimeMilliseconds: FrameTimeStatistics(
        minimum: sorted.first ?? 0,
        average: average,
        p50: Self.percentile(sorted, 0.50),
        p95: Self.percentile(sorted, 0.95),
        p99: Self.percentile(sorted, 0.99),
        maximum: sorted.last ?? 0,
        estimatedFPS: average > 0 ? 1_000 / average : 0
      ),
      memory: MemoryStatistics(
        residentBytes: memory.resident,
        virtualBytes: memory.virtual,
        residentMiB: Double(memory.resident) / 1_048_576,
        virtualMiB: Double(memory.virtual) / 1_048_576
      )
    )
  }

  @objc
  private func handleFrame(_ link: CADisplayLink) {
    defer { lastTimestamp = link.timestamp }
    guard let lastTimestamp else { return }
    let milliseconds = (link.timestamp - lastTimestamp) * 1_000
    guard milliseconds > 0 else { return }
    frameTimes.append(milliseconds)
    if frameTimes.count > maximumSamples {
      frameTimes.removeFirst(frameTimes.count - maximumSamples)
    }
  }

  private static func percentile(_ sorted: [Double], _ percentile: Double) -> Double {
    guard !sorted.isEmpty else { return 0 }
    let index = Int((Double(sorted.count - 1) * percentile).rounded(.down))
    return sorted[index]
  }

  private static func memorySnapshot() -> (
    resident: UInt64,
    virtual: UInt64
  ) {
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
      return (0, 0)
    }
    return (info.resident_size, info.virtual_size)
  }
}

@MainActor
enum AppDiagnostics {
  static func exportProfilerReport() throws -> URL {
    try AppDataPaths.ensureInitialized()
    let report = ProfilerSession.shared.makeReport()
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(report)
    let url = AppDataPaths.exports.appendingPathComponent(
      "profiler-\(Self.timestamp()).json"
    )
    try data.write(to: url, options: .atomic)
    return url
  }

  static func exportDebugLogs() async throws -> URL {
    try AppDataPaths.ensureInitialized()
    let store = try OSLogStore(scope: .currentProcessIdentifier)
    let start = Date().addingTimeInterval(-24 * 60 * 60)
    let entries = try store.getEntries(at: store.position(date: start))
    let lines = entries.compactMap { entry -> String? in
      guard let log = entry as? OSLogEntryLog,
            log.subsystem == "moe.alphaly.art3m1s"
      else {
        return nil
      }
      return "\(ISO8601DateFormatter().string(from: log.date)) "
        + "[\(log.category)] \(log.composedMessage)"
    }
    let url = AppDataPaths.exports.appendingPathComponent(
      "debug-\(Self.timestamp()).log"
    )
    try lines.joined(separator: "\n").write(
      to: url,
      atomically: true,
      encoding: .utf8
    )
    return url
  }

  private static func timestamp() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: .now)
  }
}
