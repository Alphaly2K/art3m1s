import Foundation

// Directory-service tests must never load a native archive library.
enum PFSReader {
  static func read(archivePath: String, entryPath: String, encoding: String) throws -> Data {
    throw CocoaError(.featureUnsupported)
  }
  static func listEntries(archivePath: String, encoding: String) throws -> [String] {
    throw CocoaError(.featureUnsupported)
  }
}

@main
struct HostTests {
  @MainActor
  static func main() async throws {
    let manager = FileManager.default
    let temporary = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    let suite = "Art3m1sHostTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer {
      try? manager.removeItem(at: temporary)
      defaults.removePersistentDomain(forName: suite)
    }
    let source = temporary.appendingPathComponent("source/Game")
    let games = temporary.appendingPathComponent("Games")
    try manager.createDirectory(at: source, withIntermediateDirectories: true)
    try manager.createDirectory(at: games, withIntermediateDirectories: true)
    try Data("[WINDOWS]".utf8).write(to: source.appendingPathComponent("system.ini"))

    let first = try GameImporter.copyIntoGamesDirectory(source, gamesDirectory: games)
    try Data("new content".utf8).write(to: source.appendingPathComponent("system.ini"))
    let second = try GameImporter.copyIntoGamesDirectory(source, gamesDirectory: games)
    precondition(first != second, "Same-name imports must have distinct destinations")
    let firstBytes = try Data(contentsOf: first.appendingPathComponent("system.ini"))
    let secondBytes = try Data(contentsOf: second.appendingPathComponent("system.ini"))
    precondition(firstBytes != secondBytes, "Imports must retain their own bytes")

    let linkedSource = temporary.appendingPathComponent("linked-source")
    try manager.createSymbolicLink(at: linkedSource, withDestinationURL: source)
    let linkedGames = temporary.appendingPathComponent("linked-imports")
    try manager.createDirectory(at: linkedGames, withIntermediateDirectories: true)
    let linkedCopy = try GameImporter.copyIntoGamesDirectory(linkedSource, gamesDirectory: linkedGames)
    let copiedValues = try linkedCopy.resourceValues(forKeys: [.isSymbolicLinkKey])
    precondition(copiedValues.isSymbolicLink != true)

    let library = LibraryStore(defaults: defaults)
    await library.scanAppFolder(in: games)
    precondition(library.games.count == 2)
    var game = library.games[0]
    game.displayName = "Custom title"
    game.translationEnabled = true
    game.environmentPatchEnabled = true
    game.coverPath = "cover.png"
    library.markPlayed(game)
    precondition(library.update(game))
    let played = library.games.first { $0.id == game.id }!.lastPlayedAt
    await library.scanAppFolder(in: games)
    let rescanned = library.games.first { $0.id == game.id }!
    precondition(rescanned.displayName == "Custom title" && rescanned.coverPath == "cover.png")
    precondition(rescanned.lastPlayedAt == played && played != nil)
    let loaded = GameManifest.loadEntrySettings(rescanned)
    precondition(loaded.translationEnabled && loaded.environmentPatchEnabled)
    precondition(loaded.displayNameOrName == "Custom title")

    let legacy: [Any] = [
      ["name": "Old", "path": first.path, "source": "directory", "addedAt": "2026-01-01T00:00:00.000"],
      ["name": "Broken", "source": "directory"],
      "invalid row",
    ]
    let raw = try JSONSerialization.data(withJSONObject: legacy)
    defaults.set(raw, forKey: "game_library")
    let restored = LibraryStore(defaults: defaults)
    precondition(restored.games.count == 1, "A damaged row must not discard valid games")
    precondition(restored.games[0].id == GameEntry.legacySaveId(for: first.path))
    precondition(defaults.data(forKey: "game_library_recovery") == raw)
    precondition(GameEntry.normalizeId("..", path: first.path).hasPrefix("legacy_"))
    precondition(GameEntry.legacySaveId(for: "/games/样本") == "__")

    let outside = temporary.appendingPathComponent("outside.txt")
    try Data([7]).write(to: outside)
    try manager.createSymbolicLink(at: first.appendingPathComponent("escape.txt"), withDestinationURL: outside)
    let vfs = ProjectVFS(game: GameEntry(name: "Game", path: first.path, source: .directory), encoding: "UTF-8")
    precondition(vfs.read("system.ini") != nil)
    precondition(vfs.read("escape.txt") == nil)
    try manager.createSymbolicLink(at: games.appendingPathComponent("cycle"), withDestinationURL: games)
    precondition(GameImporter.discover(in: games).count == 2, "Discovery must not follow directory cycles")

    let siglus = temporary.appendingPathComponent("Siglus")
    try manager.createDirectory(at: siglus, withIntermediateDirectories: true)
    try Data().write(to: siglus.appendingPathComponent("SCENE.PCK"))
    precondition(GameImporter.discover(in: siglus).isEmpty)
    try Data().write(to: siglus.appendingPathComponent("Gameexe.ini"))
    precondition(GameImporter.discover(in: siglus).count == 1)
    precondition(GameImporter.detectEngine(in: siglus.path) == .siglus)

    let cacheURL = temporary.appendingPathComponent("cache.pb")
    let off = NativeTranslationService(settings: TranslationSettings(), patchData: Data("{\"a\":\"b\"}".utf8), patchPath: "patch.json", cacheURL: cacheURL)
    var offResult: String? = "unexpected"
    off.enqueue(source: "a", ruby: nil) { offResult = $0 }
    precondition(offResult == nil, "Disabled translation must not apply a patch")
    off.dispose()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [HTTPFixture.self]
    let http = ScriptHTTPClient(configuration: configuration)
    let response: (Int32, Data) = await withCheckedContinuation { done in
      http.start([
        "serial": 1, "url": "https://fixture.invalid/form", "method": "POST",
        "data": [["text", "a & b"]], "file_data": [["file", "body.txt"]],
      ], readFile: { _ in Data("file body".utf8) }) { status, body in
        done.resume(returning: (status, body))
      }
    }
    precondition(response.0 == 201 && response.1 == Data("reply".utf8))
    var staleReplies = 0
    http.start(["serial": 2, "url": "https://fixture.invalid/stall", "method": "GET"],
      readFile: { _ in nil }, onComplete: { _, _ in staleReplies += 1 })
    await Task.yield()
    let replacement: Int32 = await withCheckedContinuation { done in
      http.start(["serial": 3, "url": "file:///invalid", "method": "GET"],
        readFile: { _ in nil }, onComplete: { status, _ in done.resume(returning: status) })
      http.cancel(2)
    }
    precondition(replacement == 0 && staleReplies == 0)
    http.cancel()
    print("Native host service checks passed")
  }
}

final class HTTPFixture: URLProtocol {
  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
  override func startLoading() {
    if request.url!.path == "/stall" { return }
    precondition(request.httpMethod == "POST")
    var bytes = request.httpBody ?? Data()
    if let stream = request.httpBodyStream {
      stream.open()
      defer { stream.close() }
      var buffer = [UInt8](repeating: 0, count: 1024)
      while true {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        bytes.append(contentsOf: buffer.prefix(count))
      }
    }
    let form = String(decoding: bytes, as: UTF8.self)
    precondition(form.contains("text=a%20%26%20b") && form.contains("file=file%20body"))
    let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: Data("reply".utf8))
    client?.urlProtocolDidFinishLoading(self)
  }
  override func stopLoading() {}
}
