import CryptoKit
import Foundation

@MainActor
final class NativeTranslationService {
  private struct Job {
    let key: String
    let source: String
    let ruby: String?
    var callbacks: [(String?) -> Void]
  }

  let settings: TranslationSettings
  private let cacheURL: URL
  private var patch: [String: String] = [:]
  private var cache: [String: String] = [:]
  private var pending: [String: Job] = [:]
  private var queue: [Job] = []
  private var activeJobs = 0
  private var pumpTask: Task<Void, Never>?
  private var cacheWriteTask: Task<Void, Never>?
  private var disposed = false

  init(
    settings: TranslationSettings,
    patchData: Data?,
    patchPath: String,
    cacheURL: URL
  ) {
    self.settings = settings
    self.cacheURL = cacheURL
    patch = Self.parsePatch(data: patchData, path: patchPath)
    cache = Self.readCache(cacheURL)
  }

  var hostTranslationEnabled: Bool {
    !disposed && settings.mode != .off
  }

  var hostOnlineEnabled: Bool {
    !disposed && settings.mode == .online
  }

  var hostReplacementTable: [String: String] {
    var result: [String: String] = [:]
    for (key, value) in cache {
      let source = key.split(separator: "\0").last.map(String.init) ?? key
      if !source.isEmpty {
        result[source] = value
      }
    }
    result.merge(patch) { _, new in new }
    return result
  }

  func enqueue(
    source: String,
    ruby: String?,
    onComplete: @escaping (String?) -> Void
  ) {
    guard !disposed else {
      onComplete(nil)
      return
    }
    let known = patch[source]
      ?? cache[cacheKey(source, ruby: ruby)]
      ?? cache[cacheKey(source, ruby: nil)]
      ?? cache[source]
    if let known {
      onComplete(known)
      return
    }
    guard settings.mode == .online else {
      onComplete(nil)
      return
    }
    let key = cacheKey(source, ruby: ruby)
    if pending[key] != nil {
      pending[key]?.callbacks.append(onComplete)
      return
    }
    guard pending.count < 512 else {
      AppLogger.warning("Translation queue full; keeping source text")
      onComplete(nil)
      return
    }
    let job = Job(
      key: key,
      source: source,
      ruby: ruby,
      callbacks: [onComplete]
    )
    pending[key] = job
    queue.append(job)
    scheduleQueuePump()
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    pumpTask?.cancel()
    pumpTask = nil
    cacheWriteTask?.cancel()
    writeCache()
    queue.removeAll()
    for item in pending.values {
      for callback in item.callbacks {
        callback(nil)
      }
    }
    pending.removeAll()
  }

  private var maxConcurrent: Int {
    switch settings.provider {
    case .baidu, .youdao:
      return 2
    case .openAi, .anthropic:
      return 3
    case .deepL, .google:
      return 4
    }
  }

  private var usesLLMBatch: Bool {
    settings.provider == .openAi || settings.provider == .anthropic
  }

  private func scheduleQueuePump() {
    guard !disposed, pumpTask == nil else { return }
    pumpTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(12))
      guard !Task.isCancelled, let self else { return }
      self.pumpTask = nil
      self.pumpQueue()
    }
  }

  private func pumpQueue() {
    guard !disposed else { return }
    while activeJobs < maxConcurrent, !queue.isEmpty {
      let count = usesLLMBatch ? min(12, queue.count) : 1
      let jobs = Array(queue.prefix(count))
      queue.removeFirst(jobs.count)
      activeJobs += 1
      Task { [weak self] in
        await self?.run(jobs)
      }
    }
  }

  private func run(_ jobs: [Job]) async {
    var results = Array<String?>(repeating: nil, count: jobs.count)
    do {
      results = try await translateRemoteBatch(jobs)
      guard !disposed else { return }
      for index in jobs.indices {
        if let value = results[index], !value.isEmpty {
          cache[jobs[index].key] = value
        }
      }
      scheduleCacheWrite()
    } catch {
      AppLogger.error(
        "Online translation failed (\(settings.provider.label)): "
          + error.localizedDescription
      )
    }
    activeJobs = max(activeJobs - 1, 0)
    for index in jobs.indices {
      guard let job = pending.removeValue(forKey: jobs[index].key) else {
        continue
      }
      for callback in job.callbacks {
        callback(results[index])
      }
    }
    pumpQueue()
  }

  private func cacheKey(_ source: String, ruby: String?) -> String {
    [
      "v3",
      settings.provider.rawValue,
      settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
      settings.model.trimmingCharacters(in: .whitespacesAndNewlines),
      settings.sourceLanguage,
      settings.targetLanguage,
      ruby ?? "",
      source,
    ].joined(separator: "\0")
  }

  private func scheduleCacheWrite() {
    cacheWriteTask?.cancel()
    cacheWriteTask = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled, let self else { return }
      self.writeCache()
    }
  }

  private func writeCache() {
    do {
      try FileManager.default.createDirectory(
        at: cacheURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Self.encodeCache(cache).write(to: cacheURL, options: .atomic)
    } catch {
      AppLogger.warning("Translation cache write failed: \(error.localizedDescription)")
    }
  }

  private func translateRemoteBatch(_ jobs: [Job]) async throws -> [String?] {
    if jobs.isEmpty { return [] }
    if usesLLMBatch {
      return try await withRetry {
        switch settings.provider {
        case .openAi:
          return try await translateOpenAIBatch(jobs)
        case .anthropic:
          return try await translateAnthropicBatch(jobs)
        default:
          throw TranslationError.api("unreachable LLM provider")
        }
      }
    }
    return await withTaskGroup(of: (Int, String?).self) { group in
      for (index, job) in jobs.enumerated() {
        group.addTask { @MainActor [self] in
          (index, await self.translateRemote(source: job.source, ruby: job.ruby))
        }
      }
      var values = Array<String?>(repeating: nil, count: jobs.count)
      for await (index, value) in group {
        values[index] = value
      }
      return values
    }
  }

  private func translateOpenAIBatch(_ jobs: [Job]) async throws -> [String?] {
    let endpoint = try endpointURL()
    let model = try required(settings.model, "Model")
    let useResponses = endpoint.path.hasSuffix("/responses")
    let system = batchSystemPrompt(jobs.count)
    let input = batchInput(jobs)
    let maxTokens = max(
      1024,
      min(jobs.reduce(0) { $0 + $1.source.count } * 4 + 512, 8192)
    )
    var body: [String: Any] = useResponses
      ? [
        "model": model,
        "instructions": system,
        "input": input,
        "max_output_tokens": maxTokens,
      ]
      : [
        "model": model,
        "temperature": 0,
        "max_tokens": maxTokens,
        "messages": [
          ["role": "system", "content": system],
          ["role": "user", "content": input],
        ],
      ]
    if isDeepSeek(endpoint) {
      body["thinking"] = ["type": "disabled"]
      body["response_format"] = ["type": "json_object"]
    }
    var headers: [String: String] = [:]
    let apiKey = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    if !apiKey.isEmpty {
      headers["Authorization"] = "Bearer \(apiKey)"
    }
    let root = try jsonObject(
      try await postJSON(endpoint, body: body, headers: headers)
    )
    if let error = root["error"] {
      throw TranslationError.api(String(describing: error))
    }
    if useResponses {
      if let status = root["status"] as? String,
         status == "incomplete" || status == "failed" {
        throw TranslationError.incomplete("Responses status=\(status)")
      }
    } else if let choices = root["choices"] as? [[String: Any]],
              let reason = choices.first?["finish_reason"] as? String,
              reason != "stop" {
      throw TranslationError.incomplete(
        "Chat Completions finish_reason=\(reason)"
      )
    }
    return try parseBatchResponse(extractOpenAIText(root), jobs: jobs)
  }

  private func translateAnthropicBatch(_ jobs: [Job]) async throws -> [String?] {
    let root = try jsonObject(
      try await postJSON(
        try endpointURL(),
        body: [
          "model": try required(settings.model, "Model"),
          "max_tokens": max(
            1024,
            min(jobs.reduce(0) { $0 + $1.source.count } * 4 + 512, 8192)
          ),
          "system": batchSystemPrompt(jobs.count),
          "messages": [
            ["role": "user", "content": batchInput(jobs)],
          ],
        ],
        headers: [
          "x-api-key": try required(settings.apiKey, "API Key"),
          "anthropic-version": "2023-06-01",
        ]
      )
    )
    if let error = root["error"] {
      throw TranslationError.api(String(describing: error))
    }
    if let stop = root["stop_reason"] as? String,
       stop != "end_turn", stop != "stop_sequence" {
      throw TranslationError.incomplete("Anthropic stop_reason=\(stop)")
    }
    let text = (root["content"] as? [[String: Any]])?
      .compactMap { block -> String? in
        guard block["type"] as? String == "text" else { return nil }
        return block["text"] as? String
      }
      .joined()
    return try parseBatchResponse(text, jobs: jobs)
  }

  private func batchSystemPrompt(_ count: Int) -> String {
    """
    Translate \(count) ordered visual-novel text segment(s) from \
    \(settings.sourceLanguage) to \(settings.targetLanguage). Neighboring \
    segments belong to the same passage, so use all segments as context, but \
    return one translation for every input id without merging, omitting, or \
    reordering them. Preserve names, punctuation, line breaks, formatting \
    markers, and control-like tokens. Ruby is reading context only; do not \
    repeat it. Return JSON only in exactly this shape: \
    {"translations":[{"id":0,"translation":"..."}]}. Do not add notes, \
    alternatives, arrows, or markdown.
    """
  }

  private func batchInput(_ jobs: [Job]) -> String {
    let segments: [[String: Any]] = jobs.enumerated().map { index, job in
      var item: [String: Any] = [
        "id": index,
        "text": job.source,
      ]
      if let ruby = job.ruby, !ruby.isEmpty {
        item["ruby"] = ruby
      }
      return item
    }
    let data = try? JSONSerialization.data(
      withJSONObject: ["segments": segments]
    )
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
  }

  private func parseBatchResponse(
    _ raw: String?,
    jobs: [Job]
  ) throws -> [String?] {
    guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty
    else {
      throw TranslationError.invalidResponse
    }
    if value.hasPrefix("```") {
      value = value.replacingOccurrences(
        of: #"^```(?:json)?\s*|\s*```$"#,
        with: "",
        options: .regularExpression
      )
    }
    guard let data = value.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data)
    else {
      if jobs.count == 1 {
        return [validateTranslation(jobs[0].source, value)]
      }
      throw TranslationError.invalidResponse
    }
    var values = Array<String?>(repeating: nil, count: jobs.count)
    if let dictionary = object as? [String: Any],
       jobs.count == 1,
       let translation = dictionary["translation"] as? String {
      values[0] = validateTranslation(jobs[0].source, translation)
    } else {
      let translations = (object as? [String: Any])?["translations"]
        ?? object
      guard let entries = translations as? [Any] else {
        throw TranslationError.invalidResponse
      }
      for (index, entry) in entries.enumerated() {
        var id = index
        var text: String?
        if let dictionary = entry as? [String: Any] {
          id = Int(String(describing: dictionary["id"] ?? index)) ?? index
          text = dictionary["translation"] as? String
        } else {
          text = entry as? String
        }
        guard id >= 0, id < values.count, let text else { continue }
        values[id] = validateTranslation(jobs[id].source, text)
      }
    }
    guard values.contains(where: { $0 != nil }) else {
      throw TranslationError.invalidResponse
    }
    return values
  }

  private func validateTranslation(
    _ source: String,
    _ translated: String
  ) -> String? {
    let value = translated.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return nil }
    let target = Self.canonicalLanguage(settings.targetLanguage)
    if value == source.trimmingCharacters(in: .whitespacesAndNewlines),
       target.hasPrefix("zh"),
       source.range(of: #"[\u3040-\u30ff]"#, options: .regularExpression) != nil {
      AppLogger.warning(
        "Translation model returned Japanese source unchanged"
      )
      return nil
    }
    return value
  }

  private func isDeepSeek(_ endpoint: URL) -> Bool {
    endpoint.host?.lowercased().hasSuffix("deepseek.com") == true
      || settings.model.lowercased().hasPrefix("deepseek-")
  }

  private func withRetry<T>(
    _ operation: () async throws -> T
  ) async throws -> T {
    var lastError: Error?
    for attempt in 0..<3 {
      do {
        return try await operation()
      } catch {
        lastError = error
        guard attempt < 2, isRetryable(error) else { throw error }
        try? await Task.sleep(for: .milliseconds(250 * (attempt + 1)))
      }
    }
    throw lastError ?? TranslationError.invalidResponse
  }

  private func isRetryable(_ error: Error) -> Bool {
    if error is URLError {
      return true
    }
    guard let translationError = error as? TranslationError else {
      return false
    }
    switch translationError {
    case .incomplete:
      return true
    case .http(let status, _):
      return status == 408
        || status == 409
        || status == 429
        || status >= 500
    default:
      return false
    }
  }

  private func translateRemote(
    source: String,
    ruby: String?
  ) async -> String? {
    do {
      let value: String?
      switch settings.provider {
      case .openAi:
        value = try await translateOpenAI(source: source, ruby: ruby)
      case .anthropic:
        value = try await translateAnthropic(source: source, ruby: ruby)
      case .deepL:
        value = try await translateDeepL(source: source, ruby: ruby)
      case .google:
        value = try await translateGoogle(source)
      case .baidu:
        value = try await translateBaidu(source)
      case .youdao:
        value = try await translateYoudao(source)
      }
      return value?.trimmingCharacters(in: .whitespacesAndNewlines)
    } catch {
      AppLogger.error(
        "Online translation failed (\(settings.provider.label)): \(error.localizedDescription)"
      )
      return nil
    }
  }

  private func translateOpenAI(
    source: String,
    ruby: String?
  ) async throws -> String? {
    let endpoint = try endpointURL()
    let model = try required(settings.model, "Model")
    let useResponses = endpoint.path.hasSuffix("/responses")
    let system = systemPrompt
    let input = inputJSON(source: source, ruby: ruby)
    let maxTokens = max(1024, min(source.count * 4 + 512, 8192))
    let body: [String: Any] = useResponses
      ? [
        "model": model,
        "instructions": system,
        "input": input,
        "max_output_tokens": maxTokens,
      ]
      : [
        "model": model,
        "temperature": 0,
        "max_tokens": maxTokens,
        "messages": [
          ["role": "system", "content": system],
          ["role": "user", "content": input],
        ],
      ]
    var headers: [String: String] = [:]
    if !settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      headers["Authorization"] = "Bearer \(settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))"
    }
    let data = try await postJSON(endpoint, body: body, headers: headers)
    let root = try jsonObject(data)
    if let error = root["error"] {
      throw TranslationError.api(String(describing: error))
    }
    let text = extractOpenAIText(root)
    return text.flatMap(parseSingleTranslation)
  }

  private func translateAnthropic(
    source: String,
    ruby: String?
  ) async throws -> String? {
    let endpoint = try endpointURL()
    var body: [String: Any] = [
      "model": try required(settings.model, "Model"),
      "max_tokens": max(1024, min(source.count * 4 + 512, 8192)),
      "system": systemPrompt,
      "messages": [
        ["role": "user", "content": inputJSON(source: source, ruby: ruby)],
      ],
    ]
    body["temperature"] = 0
    let data = try await postJSON(
      endpoint,
      body: body,
      headers: [
        "x-api-key": try required(settings.apiKey, "API Key"),
        "anthropic-version": "2023-06-01",
      ]
    )
    let root = try jsonObject(data)
    if let error = root["error"] {
      throw TranslationError.api(String(describing: error))
    }
    guard let content = root["content"] as? [[String: Any]] else {
      return nil
    }
    let text = content.compactMap { block -> String? in
      guard block["type"] as? String == "text" else { return nil }
      return block["text"] as? String
    }.joined()
    return parseSingleTranslation(text)
  }

  private func translateDeepL(
    source: String,
    ruby: String?
  ) async throws -> String? {
    var body: [String: Any] = [
      "text": [source],
      "target_lang": providerLanguage(settings.targetLanguage, target: true),
      "preserve_formatting": true,
    ]
    if let ruby, !ruby.isEmpty {
      body["context"] = "Ruby reading: \(ruby)"
    }
    let sourceLanguage = providerLanguage(
      settings.sourceLanguage,
      target: false
    )
    if sourceLanguage != "AUTO" {
      body["source_lang"] = sourceLanguage
    }
    let data = try await postJSON(
      try endpointURL(),
      body: body,
      headers: [
        "Authorization": "DeepL-Auth-Key \(try required(settings.apiKey, "API Key"))",
      ]
    )
    let root = try jsonObject(data)
    let translations = root["translations"] as? [[String: Any]]
    return translations?.first?["text"] as? String
  }

  private func translateGoogle(_ source: String) async throws -> String? {
    var components = URLComponents(
      url: try endpointURL(),
      resolvingAgainstBaseURL: false
    )
    var query = components?.queryItems ?? []
    query.append(
      URLQueryItem(
        name: "key",
        value: try required(settings.apiKey, "API Key")
      )
    )
    components?.queryItems = query
    guard let endpoint = components?.url else {
      throw TranslationError.invalidEndpoint
    }
    var body: [String: Any] = [
      "q": source,
      "target": providerLanguage(settings.targetLanguage, target: true),
      "format": "text",
    ]
    let sourceLanguage = providerLanguage(
      settings.sourceLanguage,
      target: false
    )
    if sourceLanguage != "auto" {
      body["source"] = sourceLanguage
    }
    let root = try jsonObject(try await postJSON(endpoint, body: body))
    let data = root["data"] as? [String: Any]
    let translations = data?["translations"] as? [[String: Any]]
    guard let text = translations?.first?["translatedText"] as? String else {
      return nil
    }
    return Self.decodeHTMLEntities(text)
  }

  private func translateBaidu(_ source: String) async throws -> String? {
    let appID = try required(settings.appID, "APP ID")
    let secret = try required(settings.appSecret, "密钥")
    let salt = String(Int(Date().timeIntervalSince1970 * 1_000_000))
    let signature = Insecure.MD5.hash(
      data: Data("\(appID)\(source)\(salt)\(secret)".utf8)
    ).map { String(format: "%02x", $0) }.joined()
    let fields = [
      "q": source,
      "from": providerLanguage(settings.sourceLanguage, target: false),
      "to": providerLanguage(settings.targetLanguage, target: true),
      "appid": appID,
      "salt": salt,
      "sign": signature,
    ]
    let root = try jsonObject(
      try await postForm(try endpointURL(), fields: fields)
    )
    if let error = root["error_code"] {
      throw TranslationError.api(String(describing: error))
    }
    let results = root["trans_result"] as? [[String: Any]]
    return results?
      .compactMap { $0["dst"] as? String }
      .joined(separator: "\n")
  }

  private func translateYoudao(_ source: String) async throws -> String? {
    let appID = try required(settings.appID, "应用 ID")
    let secret = try required(settings.appSecret, "应用密钥")
    let now = Date()
    let salt = String(Int(now.timeIntervalSince1970 * 1_000_000))
    let currentTime = String(Int(now.timeIntervalSince1970))
    let input = source.count <= 20
      ? source
      : "\(source.prefix(10))\(source.count)\(source.suffix(10))"
    let signature = SHA256.hash(
      data: Data("\(appID)\(input)\(salt)\(currentTime)\(secret)".utf8)
    ).map { String(format: "%02x", $0) }.joined()
    let fields = [
      "q": source,
      "from": providerLanguage(settings.sourceLanguage, target: false),
      "to": providerLanguage(settings.targetLanguage, target: true),
      "appKey": appID,
      "salt": salt,
      "sign": signature,
      "signType": "v3",
      "curtime": currentTime,
    ]
    let root = try jsonObject(
      try await postForm(try endpointURL(), fields: fields)
    )
    if let rawCode = root["errorCode"],
       String(describing: rawCode) != "0" {
      let code = String(describing: rawCode)
      throw TranslationError.api("Youdao error \(code)")
    }
    return (root["translation"] as? [Any])?
      .map { String(describing: $0) }
      .joined(separator: "\n")
  }

  private var systemPrompt: String {
    """
    Translate one ordered visual-novel text segment from \(settings.sourceLanguage) \
    to \(settings.targetLanguage). Preserve names, punctuation, line breaks, \
    formatting markers, and control-like tokens. Ruby is reading context only; \
    do not repeat it. Return JSON only as {"translation":"..."}. Do not add notes, \
    alternatives, arrows, or markdown.
    """
  }

  private func inputJSON(source: String, ruby: String?) -> String {
    var item: [String: Any] = ["text": source]
    if let ruby, !ruby.isEmpty {
      item["ruby"] = ruby
    }
    let data = try? JSONSerialization.data(withJSONObject: ["segment": item])
    return data.flatMap { String(data: $0, encoding: .utf8) } ?? source
  }

  private func parseSingleTranslation(_ raw: String?) -> String? {
    guard var raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty
    else {
      return nil
    }
    if raw.hasPrefix("```") {
      raw = raw.replacingOccurrences(
        of: #"^```(?:json)?\s*|\s*```$"#,
        with: "",
        options: .regularExpression
      )
    }
    guard let data = raw.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data)
    else {
      return raw
    }
    if let dictionary = object as? [String: Any] {
      if let value = dictionary["translation"] as? String {
        return value
      }
      if let values = dictionary["translations"] as? [[String: Any]] {
        return values.first?["translation"] as? String
      }
    }
    return raw
  }

  private func endpointURL() throws -> URL {
    let raw = settings.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    let value = raw.isEmpty ? settings.provider.defaultEndpoint : raw
    guard let url = URL(string: value),
          url.scheme != nil,
          url.host != nil
    else {
      throw TranslationError.invalidEndpoint
    }
    return url
  }

  private func providerLanguage(_ raw: String, target: Bool) -> String {
    let canonical = Self.canonicalLanguage(raw)
    switch settings.provider {
    case .deepL:
      switch canonical {
      case "auto": return "AUTO"
      case "zh-CN": return target ? "ZH-HANS" : "ZH"
      case "zh-TW": return target ? "ZH-HANT" : "ZH"
      case "en": return target ? "EN-US" : "EN"
      default: return canonical.uppercased()
      }
    case .baidu:
      switch canonical {
      case "ja": return "jp"
      case "zh-CN": return "zh"
      case "zh-TW": return "cht"
      default: return canonical
      }
    case .youdao:
      switch canonical {
      case "zh-CN": return "zh-CHS"
      case "zh-TW": return "zh-CHT"
      default: return canonical
      }
    default:
      return canonical
    }
  }

  private static func canonicalLanguage(_ raw: String) -> String {
    switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "auto", "自动", "自动检测": return "auto"
    case "ja", "jp", "日语", "日本語", "japanese": return "ja"
    case "zh", "zh-cn", "zh-hans", "zh-chs", "中文", "简体中文", "chinese":
      return "zh-CN"
    case "zh-tw", "zh-hant", "zh-cht", "繁体中文": return "zh-TW"
    case "en", "英语", "英文", "english": return "en"
    case "ko", "韩语", "朝鲜语", "korean": return "ko"
    case "fr", "法语", "french": return "fr"
    case "de", "德语", "german": return "de"
    case "es", "西班牙语", "spanish": return "es"
    case "ru", "俄语", "russian": return "ru"
    case "pt", "葡萄牙语", "portuguese": return "pt"
    default: return raw
    }
  }

  private static func decodeHTMLEntities(_ value: String) -> String {
    var result = value
    if let expression = try? NSRegularExpression(
      pattern: #"&#(x?[0-9A-Fa-f]+);"#
    ) {
      let matches = expression.matches(
        in: result,
        range: NSRange(result.startIndex..<result.endIndex, in: result)
      )
      for match in matches.reversed() {
        guard let range = Range(match.range, in: result),
              let rawRange = Range(match.range(at: 1), in: result)
        else {
          continue
        }
        let raw = String(result[rawRange])
        let radix = raw.hasPrefix("x") ? 16 : 10
        let digits = raw.hasPrefix("x") ? String(raw.dropFirst()) : raw
        guard let codePoint = Int(digits, radix: radix),
              let scalar = UnicodeScalar(codePoint)
        else {
          continue
        }
        result.replaceSubrange(range, with: String(scalar))
      }
    }
    return result
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .replacingOccurrences(of: "&apos;", with: "'")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&amp;", with: "&")
  }

  private func required(_ value: String, _ name: String) throws -> String {
    let result = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !result.isEmpty else {
      throw TranslationError.missingField(name)
    }
    return result
  }

  private func postJSON(
    _ url: URL,
    body: [String: Any],
    headers: [String: String] = [:]
  ) async throws -> Data {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    for (key, value) in headers {
      request.setValue(value, forHTTPHeaderField: key)
    }
    request.httpBody = try JSONSerialization.data(withJSONObject: body)
    return try await responseData(request)
  }

  private func postForm(
    _ url: URL,
    fields: [String: String]
  ) async throws -> Data {
    var components = URLComponents()
    components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = 60
    request.setValue(
      "application/x-www-form-urlencoded; charset=utf-8",
      forHTTPHeaderField: "Content-Type"
    )
    request.httpBody = components.percentEncodedQuery?.data(using: .utf8)
    return try await responseData(request)
  }

  private func responseData(_ request: URLRequest) async throws -> Data {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw TranslationError.api("missing HTTP response")
    }
    guard (200..<300).contains(response.statusCode) else {
      let body = String(data: data.prefix(400), encoding: .utf8) ?? ""
      throw TranslationError.http(response.statusCode, body)
    }
    return data
  }

  private func jsonObject(_ data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data)
      as? [String: Any]
    else {
      throw TranslationError.invalidResponse
    }
    return object
  }

  private func extractOpenAIText(_ root: [String: Any]) -> String? {
    if let direct = root["output_text"] as? String {
      return direct
    }
    if let choices = root["choices"] as? [[String: Any]],
       let choice = choices.first {
      if let text = choice["text"] as? String {
        return text
      }
      if let message = choice["message"] as? [String: Any] {
        if let content = message["content"] as? String {
          return content
        }
        if let content = message["content"] as? [[String: Any]] {
          return content.compactMap { $0["text"] as? String }.joined()
        }
      }
    }
    if let output = root["output"] as? [[String: Any]] {
      let parts = output.flatMap { item -> [String] in
        guard let content = item["content"] as? [[String: Any]] else {
          return []
        }
        return content.compactMap { $0["text"] as? String }
      }
      if !parts.isEmpty {
        return parts.joined()
      }
    }
    return nil
  }

  private static func parsePatch(
    data: Data?,
    path: String
  ) -> [String: String] {
    guard let data, let content = String(data: data, encoding: .utf8) else {
      return [:]
    }
    let lower = path.lowercased()
    if lower.hasSuffix(".tsv") {
      var result: [String: String] = [:]
      for line in content.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
        guard let tab = line.firstIndex(of: "\t") else { continue }
        let source = String(line[..<tab])
        let target = String(line[line.index(after: tab)...])
        if !source.isEmpty { result[source] = target }
      }
      return result
    }
    if lower.hasSuffix(".jsonl") {
      var result: [String: String] = [:]
      for line in content.components(separatedBy: .newlines) {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data)
                as? [String: Any],
              let source = object["source"] as? String
        else {
          continue
        }
        if let target = object["translation"] as? String
          ?? object["target"] as? String {
          result[source] = target
        }
      }
      return result
    }
    guard let data = content.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data)
    else {
      return [:]
    }
    if let dictionary = object as? [String: String] {
      return dictionary
    }
    if let items = object as? [[String: Any]] {
      var result: [String: String] = [:]
      for item in items {
        guard let source = item["source"] as? String,
              let target = item["translation"] as? String
                ?? item["target"] as? String
        else {
          continue
        }
        result[source] = target
      }
      return result
    }
    return [:]
  }

  private static func readCache(_ url: URL) -> [String: String] {
    guard let data = try? Data(contentsOf: url) else { return [:] }
    return decodeCache(data)
  }

  private static func encodeCache(_ entries: [String: String]) -> Data {
    var output = Data()
    for (key, value) in entries {
      var entry = Data()
      appendProtobuf(field: 1, string: key, to: &entry)
      appendProtobuf(field: 2, string: value, to: &entry)
      output.append(0x0A)
      appendVarint(UInt64(entry.count), to: &output)
      output.append(entry)
    }
    return output
  }

  private static func decodeCache(_ data: Data) -> [String: String] {
    var result: [String: String] = [:]
    var index = 0
    while index < data.count {
      guard let tag = readVarint(data, index: &index),
            tag >> 3 == 1,
            tag & 7 == 2,
            let length = readVarint(data, index: &index),
            index + Int(length) <= data.count
      else {
        break
      }
      let end = index + Int(length)
      var key: String?
      var value: String?
      while index < end {
        guard let field = readVarint(data, index: &index),
              let size = readVarint(data, index: &index),
              index + Int(size) <= end
        else {
          break
        }
        let payload = data[index..<(index + Int(size))]
        if field >> 3 == 1 {
          key = String(data: payload, encoding: .utf8)
        } else if field >> 3 == 2 {
          value = String(data: payload, encoding: .utf8)
        }
        index += Int(size)
      }
      if let key, let value {
        result[key] = value
      }
      index = end
    }
    return result
  }

  private static func appendProtobuf(
    field: UInt64,
    string: String,
    to data: inout Data
  ) {
    data.append(UInt8((field << 3) | 2))
    let bytes = Data(string.utf8)
    appendVarint(UInt64(bytes.count), to: &data)
    data.append(bytes)
  }

  private static func appendVarint(_ value: UInt64, to data: inout Data) {
    var value = value
    repeat {
      var byte = UInt8(value & 0x7F)
      value >>= 7
      if value != 0 { byte |= 0x80 }
      data.append(byte)
    } while value != 0
  }

  private static func readVarint(
    _ data: Data,
    index: inout Int
  ) -> UInt64? {
    var result: UInt64 = 0
    var shift: UInt64 = 0
    while index < data.count, shift < 64 {
      let byte = data[index]
      index += 1
      result |= UInt64(byte & 0x7F) << shift
      if byte & 0x80 == 0 {
        return result
      }
      shift += 7
    }
    return nil
  }
}

private enum TranslationError: LocalizedError {
  case invalidEndpoint
  case missingField(String)
  case invalidResponse
  case incomplete(String)
  case api(String)
  case http(Int, String)

  var errorDescription: String? {
    switch self {
    case .invalidEndpoint:
      return "翻译 API 地址无效"
    case .missingField(let field):
      return "\(field) 未填写"
    case .invalidResponse:
      return "翻译 API 返回的不是 JSON 对象"
    case .incomplete(let message):
      return message
    case .api(let message):
      return message
    case .http(let status, let body):
      return "HTTP \(status): \(body)"
    }
  }
}
