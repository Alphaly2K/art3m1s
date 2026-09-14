import CryptoKit
import Foundation

enum GameSource: String, Codable, Sendable {
  case directory
  case pfsArchive
}

enum GameEngineKind: String, Codable, CaseIterable, Sendable {
  case art3m1s
  case rfvp
  case krkr

  var label: String {
    switch self {
    case .art3m1s: "Artemis"
    case .rfvp: "FVP"
    case .krkr: "Kirikiri"
    }
  }

  init(id: String?) {
    switch id?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "rfvp", "fvp":
      self = .rfvp
    case "krkr", "kirikiri":
      self = .krkr
    default:
      self = .art3m1s
    }
  }
}

struct GameEntry: Identifiable, Codable, Hashable, Sendable {
  let id: String
  var name: String
  var path: String
  var source: GameSource
  var engine: GameEngineKind
  var addedAt: Date
  var lastPlayedAt: Date?
  var displayName: String?
  var coverPath: String?
  var screenshotPath: String?
  var translationEnabled: Bool
  var translationPatchPath: String
  var environmentPatchEnabled: Bool
  var experimentalElunaEnabled: Bool
  var inputGate: InputGatePolicy?
  var vndbId: String
  var fontOverridePath: String
  var fontOverrideFilePath: String
  var reportedOs: String
  var runtimePlatform: String
  var manifestPath: String?

  var displayNameOrName: String {
    displayName?.isEmpty == false ? displayName! : name
  }

  init(
    id: String? = nil,
    name: String,
    path: String,
    source: GameSource,
    engine: GameEngineKind = .art3m1s,
    addedAt: Date = .now,
    lastPlayedAt: Date? = nil,
    displayName: String? = nil,
    coverPath: String? = nil,
    screenshotPath: String? = nil,
    translationEnabled: Bool = false,
    translationPatchPath: String = "",
    environmentPatchEnabled: Bool = false,
    experimentalElunaEnabled: Bool = false,
    inputGate: InputGatePolicy? = nil,
    vndbId: String = "",
    fontOverridePath: String = "",
    fontOverrideFilePath: String = "",
    reportedOs: String = "",
    runtimePlatform: String = "WINDOWS",
    manifestPath: String? = nil
  ) {
    self.id = Self.normalizeId(id, path: path)
    self.name = name
    self.path = path
    self.source = source
    self.engine = engine
    self.addedAt = addedAt
    self.lastPlayedAt = lastPlayedAt
    self.displayName = displayName
    self.coverPath = coverPath
    self.screenshotPath = screenshotPath
    self.translationEnabled = translationEnabled
    self.translationPatchPath = translationPatchPath
    self.environmentPatchEnabled = environmentPatchEnabled
    self.experimentalElunaEnabled = experimentalElunaEnabled
    self.inputGate = inputGate
    self.vndbId = vndbId
    self.fontOverridePath = fontOverridePath
    self.fontOverrideFilePath = fontOverrideFilePath
    self.reportedOs = reportedOs
    self.runtimePlatform = runtimePlatform
    self.manifestPath = manifestPath
  }

  static func normalizeId(_ id: String?, path: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    let cleaned = (id ?? "").unicodeScalars
      .filter { allowed.contains($0) }
      .map(String.init)
      .joined()
    return cleaned.isEmpty ? legacyId(for: path) : cleaned
  }

  static func legacySaveId(for path: String) -> String {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    let basename = normalized.split(separator: "/").last.map(String.init) ?? ""
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
    let cleaned = basename.unicodeScalars
      .map { allowed.contains($0) ? String($0) : "_" }
      .joined()
    return cleaned.isEmpty ? legacyId(for: path) : cleaned
  }

  static func legacyId(for path: String) -> String {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    let digest = SHA256.hash(data: Data(normalized.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return "legacy_\(hex.prefix(16))"
  }
}

enum TranslationMode: String, Codable, CaseIterable, Sendable {
  case off
  case patch
  case online

  var label: String {
    switch self {
    case .off: "关闭"
    case .patch: "对照文件"
    case .online: "在线翻译"
    }
  }
}

enum TranslationProvider: String, Codable, CaseIterable, Sendable {
  case openAi
  case anthropic
  case deepL
  case google
  case baidu
  case youdao

  var label: String {
    switch self {
    case .openAi: "LLM Web API（OpenAI 兼容）"
    case .anthropic: "Anthropic"
    case .deepL: "DeepL"
    case .google: "Google 翻译"
    case .baidu: "百度翻译"
    case .youdao: "有道翻译"
    }
  }

  var defaultEndpoint: String {
    switch self {
    case .openAi: "https://api.openai.com/v1/responses"
    case .anthropic: "https://api.anthropic.com/v1/messages"
    case .deepL: "https://api-free.deepl.com/v2/translate"
    case .google: "https://translation.googleapis.com/language/translate/v2"
    case .baidu: "https://fanyi-api.baidu.com/api/trans/vip/translate"
    case .youdao: "https://openapi.youdao.com/api"
    }
  }

  var defaultModel: String {
    switch self {
    case .openAi: "gpt-4.1-mini"
    case .anthropic: "claude-sonnet-4-20250514"
    default: ""
    }
  }
}

struct TranslationSettings: Codable, Hashable, Sendable {
  var mode: TranslationMode = .off
  var provider: TranslationProvider = .openAi
  var endpoint: String = TranslationProvider.openAi.defaultEndpoint
  var apiKey: String = ""
  var appID: String = ""
  var appSecret: String = ""
  var model: String = TranslationProvider.openAi.defaultModel
  var sourceLanguage: String = "日语"
  var targetLanguage: String = "简体中文"
}

let translationLanguages = [
  "自动检测", "日语", "简体中文", "繁体中文", "英语", "韩语",
  "法语", "德语", "西班牙语", "俄语", "葡萄牙语",
]

struct BackendOption: Hashable, Sendable {
  let value: Int
  let label: String
}
