import Foundation

@MainActor
final class ScriptHTTPClient {
  private var task: Task<Void, Never>?
  private var serial: UInt64?
  private var generation = 0
  private let configuration: URLSessionConfiguration

  init(configuration: URLSessionConfiguration = .ephemeral) {
    self.configuration = configuration
    self.configuration.timeoutIntervalForRequest = 30
    self.configuration.timeoutIntervalForResource = 30
  }

  func start(
    _ payload: [String: Any],
    readFile: @escaping (String) -> Data?,
    onComplete: @escaping (Int32, Data) -> Void
  ) {
    cancel()
    let current = generation
    serial = (payload["serial"] as? NSNumber)?.uint64Value
    task = Task {
      var status: Int32 = 0
      var body = Data()
      let session = URLSession(configuration: configuration)
      defer { session.invalidateAndCancel() }
      do {
        guard let raw = payload["url"] as? String,
              let url = URL(string: raw),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false,
              let method = (payload["method"] as? String)?.uppercased(),
              ["GET", "POST"].contains(method) else {
          throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        for (name, value) in Self.pairs(payload["headers"]) {
          request.setValue(value, forHTTPHeaderField: name)
        }
        if method == "POST" {
          var fields = Self.pairs(payload["data"])
          for (name, path) in Self.pairs(payload["file_data"]) {
            guard let data = readFile(path) else { throw CocoaError(.fileReadNoSuchFile) }
            fields.append((name, String(decoding: data, as: UTF8.self)))
          }
          let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
          let form = fields.map { name, value in
            (name.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
              + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")
          }.joined(separator: "&")
          request.httpBody = Data(form.utf8)
          if request.value(forHTTPHeaderField: "Content-Type") == nil {
            request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
          }
        }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        var chunk = [UInt8]()
        chunk.reserveCapacity(16 * 1024)
        for try await byte in bytes {
          guard body.count + chunk.count < 32 * 1024 * 1024 else {
            throw URLError(.dataLengthExceedsMaximum)
          }
          chunk.append(byte)
          if chunk.count == 16 * 1024 {
            body.append(contentsOf: chunk)
            chunk.removeAll(keepingCapacity: true)
            try Task.checkCancellation()
            await Task.yield()
          }
        }
        body.append(contentsOf: chunk)
        status = Int32(response.statusCode)
      } catch {
        body = Data()
        if !Task.isCancelled { AppLogger.warning("HTTP request failed: \(error.localizedDescription)") }
      }
      guard !Task.isCancelled, generation == current else { return }
      task = nil
      serial = nil
      onComplete(status, body)
    }
  }

  func cancel(_ serial: UInt64? = nil) {
    guard serial == nil || serial == self.serial else { return }
    generation += 1
    task?.cancel()
    task = nil
    self.serial = nil
  }

  private static func pairs(_ value: Any?) -> [(String, String)] {
    (value as? [[String]] ?? []).compactMap { pair in
      pair.count == 2 ? (pair[0], pair[1]) : nil
    }
  }
}
