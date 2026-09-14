import Foundation

struct InputGatePolicy: Codable, Hashable, Sendable {
  var keyboard = true
  var mouseButtons = true
  var mouseMove = true
  var touch = true
  var wheelToKeys = true
  var twoFingerRightClick = true
  var twoFingerScrollWheel = false
  var blockedKeys: Set<Int> = []
  var keyRemap: [Int: Int] = [:]

  static let full = InputGatePolicy()
  static let touchOnly = InputGatePolicy(
    keyboard: false,
    twoFingerScrollWheel: true
  )

  enum CodingKeys: String, CodingKey {
    case keyboard
    case mouseButtons
    case mouseMove
    case touch
    case wheelToKeys
    case twoFingerRightClick
    case twoFingerScrollWheel
    case blockedKeys
    case keyRemap
  }

  init(
    keyboard: Bool = true,
    mouseButtons: Bool = true,
    mouseMove: Bool = true,
    touch: Bool = true,
    wheelToKeys: Bool = true,
    twoFingerRightClick: Bool = true,
    twoFingerScrollWheel: Bool = false,
    blockedKeys: Set<Int> = [],
    keyRemap: [Int: Int] = [:]
  ) {
    self.keyboard = keyboard
    self.mouseButtons = mouseButtons
    self.mouseMove = mouseMove
    self.touch = touch
    self.wheelToKeys = wheelToKeys
    self.twoFingerRightClick = twoFingerRightClick
    self.twoFingerScrollWheel = twoFingerScrollWheel
    self.blockedKeys = blockedKeys
    self.keyRemap = keyRemap
  }

  init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    keyboard = try values.decodeIfPresent(Bool.self, forKey: .keyboard) ?? true
    mouseButtons = try values.decodeIfPresent(Bool.self, forKey: .mouseButtons)
      ?? true
    mouseMove = try values.decodeIfPresent(Bool.self, forKey: .mouseMove) ?? true
    touch = try values.decodeIfPresent(Bool.self, forKey: .touch) ?? true
    wheelToKeys = try values.decodeIfPresent(Bool.self, forKey: .wheelToKeys)
      ?? true
    twoFingerRightClick = try values.decodeIfPresent(
      Bool.self,
      forKey: .twoFingerRightClick
    ) ?? true
    twoFingerScrollWheel = try values.decodeIfPresent(
      Bool.self,
      forKey: .twoFingerScrollWheel
    ) ?? false
    blockedKeys = Set(
      try values.decodeIfPresent([Int].self, forKey: .blockedKeys) ?? []
    )
    let remap = try values.decodeIfPresent(
      [String: Int].self,
      forKey: .keyRemap
    ) ?? [:]
    keyRemap = Dictionary(
      uniqueKeysWithValues: remap.compactMap { key, value in
        guard let key = Int(key) else { return nil }
        return (key, value)
      }
    )
  }

  func filterKey(_ virtualKey: Int) -> Int? {
    guard keyboard, !blockedKeys.contains(virtualKey) else { return nil }
    return keyRemap[virtualKey] ?? virtualKey
  }

  func filterForwardedKey(_ virtualKey: Int) -> Int? {
    guard !blockedKeys.contains(virtualKey) else { return nil }
    return keyRemap[virtualKey] ?? virtualKey
  }

  var isFull: Bool {
    self == Self.full
  }
}
