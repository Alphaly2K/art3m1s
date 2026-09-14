import Foundation

enum EnvironmentPatch {
  static let virtualFiles: [String: Data] = [
    "system/dmm.lua": script(
      "-- Art3m1s environment compatibility patch\n"
    ),
    "system/dmm.lub": script(
      "-- Art3m1s environment compatibility patch\n"
    ),
    "system/dmmck.lua": script(
      """
      -- Art3m1s environment compatibility patch
      function init_dmmck() end
      """
    ),
    "system/extend/auth.lua": script(
      """
      -- Art3m1s environment compatibility patch
      function authentication() end
      """
    ),
    "system/extend/auth/dmmck.lua": script(
      """
      -- Art3m1s environment compatibility patch
      function init_dmmck() end
      function dmmck_login() end
      function dmmck_logincheck() end
      """
    ),
  ]

  static func normalizePath(_ path: String) -> String {
    var parts: [String] = []
    for raw in path.replacingOccurrences(of: "\\", with: "/")
      .split(separator: "/", omittingEmptySubsequences: false) {
      let part = String(raw)
      if part.isEmpty || part == "." { continue }
      if part == ".." { return "" }
      parts.append(part)
    }
    return parts.joined(separator: "/").lowercased()
  }

  static func canTransform(_ path: String) -> Bool {
    normalizePath(path) == "system/first.iet"
  }

  static func transform(path: String, original: Data) -> Data {
    guard canTransform(path),
          let text = String(data: original, encoding: .isoLatin1)
    else {
      return original
    }
    let lower = text.lowercased()
    let luaStart = lower.range(of: "[lua]")?.lowerBound
      ?? text.endIndex
    let prefix = String(text[..<luaStart])
    let suffix = String(text[luaStart...])
    let expression = try? NSRegularExpression(
      pattern: #"/\*([\s\S]*?)\*/"#,
      options: []
    )
    guard let expression else { return original }
    let range = NSRange(prefix.startIndex..<prefix.endIndex, in: prefix)
    let matches = expression.matches(in: prefix, options: [], range: range)
    guard !matches.isEmpty else { return original }

    var patched = prefix as NSString
    for match in matches.reversed() {
      let block = patched.substring(with: match.range)
      let replacement = block
        .components(separatedBy: .newlines)
        .map { line -> String in
          let trimmed = line.trimmingCharacters(in: .whitespaces)
          if trimmed.isEmpty || trimmed.hasPrefix("//") {
            return line
          }
          let indent = String(line.prefix { $0 == " " || $0 == "\t" })
          return "\(indent)// \(trimmed)"
        }
        .joined(separator: "\n")
      patched = patched.replacingCharacters(
        in: match.range,
        with: replacement
      ) as NSString
    }
    guard let data = "\(patched)\(suffix)".data(using: .isoLatin1) else {
      return original
    }
    return data
  }

  private static func script(_ source: String) -> Data {
    Data(source.utf8)
  }
}
