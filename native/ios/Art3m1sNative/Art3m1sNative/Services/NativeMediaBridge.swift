import AVFoundation
import Foundation

@MainActor
final class NativeMediaBridge: NSObject {
  typealias AssetReader = (String) -> Data?

  var assetReader: AssetReader?
  var onVideoFinished: ((String?) -> Void)?
  var onSoundFinished: ((String?) -> Void)?

  private struct OperationTicket {
    let key: String
    let epoch: Int
    let generation: Int
  }

  private final class OperationGate {
    private var epoch = 0
    private var generations: [String: Int] = [:]

    func begin(_ key: String) -> OperationTicket {
      let generation = (generations[key] ?? 0) + 1
      generations[key] = generation
      return OperationTicket(key: key, epoch: epoch, generation: generation)
    }

    func invalidate(_ key: String) {
      generations[key] = (generations[key] ?? 0) + 1
    }

    func invalidateAll() {
      epoch += 1
      generations.removeAll()
    }

    func isCurrent(_ ticket: OperationTicket) -> Bool {
      ticket.epoch == epoch
        && generations[ticket.key] == ticket.generation
    }
  }

  private var channelVolumes: [String: Double] = [
    "master": 1,
    "bgm": 1,
    "se": 1,
    "voice": 1,
    "video": 1,
  ]
  private let operations = OperationGate()
  private var bgm: NativeAudioHandle?
  private var sounds: [String: NativeAudioHandle] = [:]
  private var videoAudio: NativeAudioHandle?
  private var disposed = false
  private var suspended = false

  override init() {
    super.init()
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .default)
    try? session.setActive(true)
  }

  func configure(assetReader: @escaping AssetReader) {
    self.assetReader = assetReader
  }

  func handleCommand(kind: String, payload: [String: Any]) {
    guard !disposed else { return }
    Task { [weak self] in
      guard let self else { return }
      switch kind {
      case "audio_set_volume":
        await self.setVolume(payload)
      case "audio_bgm_play":
        await self.playBgm(payload)
      case "audio_bgm_crossfade":
        await self.crossfadeBgm(payload)
      case "audio_bgm_stop":
        await self.stopBgm(fadeMs: self.int(payload["fade_ms"]))
      case "audio_bgm_fade":
        self.fadeBgm(payload)
      case "audio_bgm_pan":
        self.panBgm(payload)
      case "audio_se_play":
        await self.playSound(payload, channel: "se")
      case "audio_se_stop":
        await self.stopSound(
          self.string(payload["id"]),
          fadeMs: self.int(payload["fade_ms"])
        )
      case "audio_se_fade":
        self.fadeSound(
          self.string(payload["id"]),
          payload: payload,
          channel: "se"
        )
      case "audio_se_pan":
        self.panSound(
          self.string(payload["id"]),
          payload: payload,
          channel: "se"
        )
      case "audio_voice_play":
        await self.playSound(payload, channel: "voice")
      case "audio_stop_all":
        self.stopAll()
      case "video_audio_play":
        await self.playVideoAudio(payload)
      case "video_stop_all":
        self.stopVideoAudio()
      case "video_play":
        self.onVideoFinished?(self.string(payload["id"]))
      default:
        AppLogger.debug("Unhandled media command: \(kind)")
      }
    }
  }

  func setSuspended(_ value: Bool) {
    guard suspended != value else { return }
    suspended = value
    bgm?.setHostSuspended(value)
    for handle in sounds.values {
      handle.setHostSuspended(value)
    }
    videoAudio?.setHostSuspended(value)
  }

  func setMasterVolume(_ value: Double) {
    channelVolumes["master"] = min(max(value, 0), 1)
    if let bgm {
      bgm.setEffectiveVolume(effectiveVolume("bgm", bgm.gain))
    }
    for handle in sounds.values {
      handle.setEffectiveVolume(effectiveVolume(handle.channel, handle.gain))
    }
    if let videoAudio {
      videoAudio.setEffectiveVolume(
        effectiveVolume("video", videoAudio.gain)
      )
    }
  }

  func skipVideo() {
    stopVideoAudio()
    onVideoFinished?(nil)
  }

  func dispose() {
    guard !disposed else { return }
    disposed = true
    operations.invalidateAll()
    stopAll()
    sounds.removeAll()
    bgm = nil
    videoAudio = nil
    assetReader = nil
  }

  private func setVolume(_ payload: [String: Any]) async {
    guard let channel = string(payload["channel"]) else { return }
    channelVolumes[channel] = clamp(double(payload["value"], 1), 0, 1)
    if let bgm {
      bgm.setEffectiveVolume(effectiveVolume("bgm", bgm.gain))
    }
    for handle in sounds.values {
      handle.setEffectiveVolume(effectiveVolume(handle.channel, handle.gain))
    }
    if let videoAudio {
      videoAudio.setEffectiveVolume(
        effectiveVolume("video", videoAudio.gain)
      )
    }
  }

  private func playBgm(_ payload: [String: Any]) async {
    let ticket = operations.begin("bgm")
    guard let source = resolveAsset(payload),
          operations.isCurrent(ticket)
    else {
      onSoundFinished?(nil)
      return
    }
    let loopSource = resolveAsset(
      payload,
      fileKey: "loop_file",
      resolvedFileKey: "resolved_loop_file"
    )
    guard operations.isCurrent(ticket) else { return }

    let old = bgm
    bgm = nil
    old?.dispose()
    guard operations.isCurrent(ticket) else { return }

    let gain = gainValue(payload["gain"])
    guard let handle = await makeHandle(
      id: nil,
      source: source,
      loopSource: loopSource,
      channel: "bgm",
      gain: gain,
      pan: panValue(payload["pan"]),
      loop: bool(payload["loop"])
    ), operations.isCurrent(ticket) else {
      onSoundFinished?(nil)
      return
    }
    handle.onCompleted = { [weak self, weak handle] in
      guard let self, self.bgm === handle else { return }
      self.bgm = nil
      self.onSoundFinished?(nil)
    }
    bgm = handle
    handle.setHostSuspended(suspended)
    let fadeMs = int(payload["fade_ms"])
    handle.setEffectiveVolume(
      fadeMs > 0 ? 0 : effectiveVolume("bgm", gain)
    )
    handle.play()
    if fadeMs > 0 {
      handle.fadeTo(effectiveVolume("bgm", gain), durationMs: fadeMs)
    }
  }

  private func crossfadeBgm(_ payload: [String: Any]) async {
    let ticket = operations.begin("bgm")
    guard let source = resolveAsset(payload),
          operations.isCurrent(ticket)
    else {
      onSoundFinished?(nil)
      return
    }
    let loopSource = resolveAsset(
      payload,
      fileKey: "loop_file",
      resolvedFileKey: "resolved_loop_file"
    )
    guard operations.isCurrent(ticket) else { return }

    let gain = gainValue(payload["gain"])
    guard let handle = await makeHandle(
      id: nil,
      source: source,
      loopSource: loopSource,
      channel: "bgm",
      gain: gain,
      pan: panValue(payload["pan"]),
      loop: bool(payload["loop"])
    ), operations.isCurrent(ticket) else {
      onSoundFinished?(nil)
      return
    }

    let previous = bgm
    bgm = handle
    handle.onCompleted = { [weak self, weak handle] in
      guard let self, self.bgm === handle else { return }
      self.bgm = nil
      self.onSoundFinished?(nil)
    }
    handle.setHostSuspended(suspended)
    let duration = int(payload["time_ms"])
    handle.setEffectiveVolume(
      duration > 0 ? 0 : effectiveVolume("bgm", gain)
    )
    handle.play()
    if duration > 0 {
      handle.fadeTo(effectiveVolume("bgm", gain), durationMs: duration)
      previous?.fadeTo(0, durationMs: duration)
    }
    previous?.dispose(afterMilliseconds: max(duration, 0))
  }

  private func stopBgm(fadeMs: Int) async {
    operations.invalidate("bgm")
    guard let bgm else { return }
    self.bgm = nil
    if fadeMs > 0 {
      bgm.fadeTo(0, durationMs: fadeMs)
      bgm.dispose(afterMilliseconds: fadeMs)
    } else {
      bgm.dispose()
    }
  }

  private func fadeBgm(_ payload: [String: Any]) {
    guard let bgm else { return }
    bgm.gain = gainValue(payload["gain"], fallback: bgm.gain)
    bgm.fadeTo(
      effectiveVolume("bgm", bgm.gain),
      durationMs: int(payload["time_ms"])
    )
  }

  private func panBgm(_ payload: [String: Any]) {
    bgm?.panTo(
      panValue(payload["pan"]),
      durationMs: int(payload["time_ms"])
    )
  }

  private func playSound(
    _ payload: [String: Any],
    channel: String
  ) async {
    let id = string(payload["id"]) ?? ""
    let key = soundKey(channel, id)
    let ticket = operations.begin(key)
    guard let source = resolveAsset(payload),
          operations.isCurrent(ticket)
    else {
      onSoundFinished?(id)
      return
    }

    sounds.removeValue(forKey: key)?.dispose()
    guard operations.isCurrent(ticket) else { return }

    let gain = gainValue(payload["gain"])
    guard let handle = await makeHandle(
      id: id,
      source: source,
      loopSource: nil,
      channel: channel,
      gain: gain,
      pan: panValue(payload["pan"]),
      loop: bool(payload["loop"])
    ), operations.isCurrent(ticket) else {
      onSoundFinished?(id)
      return
    }
    handle.onCompleted = { [weak self, weak handle] in
      guard let self, self.sounds[key] === handle else { return }
      self.sounds.removeValue(forKey: key)
      self.onSoundFinished?(id)
    }
    sounds[key] = handle
    handle.setHostSuspended(suspended)
    let fadeMs = int(payload["fade_ms"])
    handle.setEffectiveVolume(
      fadeMs > 0 ? 0 : effectiveVolume(channel, gain)
    )
    handle.play()
    if fadeMs > 0 {
      handle.fadeTo(effectiveVolume(channel, gain), durationMs: fadeMs)
    }
  }

  private func playVideoAudio(_ payload: [String: Any]) async {
    guard let path = string(payload["path"]) else { return }
    let ticket = operations.begin("video_audio")
    let decoded = await Task.detached(priority: .userInitiated) {
      let url = URL(fileURLWithPath: path)
      guard let data = try? Data(contentsOf: url) else {
        return Data?.none
      }
      try? FileManager.default.removeItem(at: url)
      return try? NativeAudioDecoder.playableData(data)
    }.value
    guard operations.isCurrent(ticket), let decoded else { return }

    let previous = videoAudio
    videoAudio = nil
    previous?.dispose()
    guard operations.isCurrent(ticket) else { return }
    do {
      let handle = try NativeAudioHandle(
        id: string(payload["id"]),
        source: decoded,
        loopSource: nil,
        channel: "video",
        gain: 1,
        pan: 0,
        loop: bool(payload["loop"])
      )
      handle.onCompleted = { [weak self, weak handle] in
        guard let self, self.videoAudio === handle else { return }
        self.videoAudio = nil
      }
      videoAudio = handle
      handle.setHostSuspended(suspended)
      handle.setEffectiveVolume(
        effectiveVolume("video", handle.gain)
      )
      handle.play()
    } catch {
      AppLogger.warning(
        "Video audio decode failed: \(error.localizedDescription)"
      )
    }
  }

  private func stopVideoAudio() {
    operations.invalidate("video_audio")
    videoAudio?.dispose()
    videoAudio = nil
  }

  private func stopSound(_ id: String?, fadeMs: Int) async {
    guard let id else { return }
    let keys = [soundKey("se", id), soundKey("voice", id)]
    for key in keys {
      operations.invalidate(key)
    }
    var handles: [NativeAudioHandle] = []
    for key in keys {
      if let handle = sounds.removeValue(forKey: key) {
        handles.append(handle)
      }
    }
    for handle in handles {
      if fadeMs > 0 {
        handle.fadeTo(0, durationMs: fadeMs)
        handle.dispose(afterMilliseconds: fadeMs)
      } else {
        handle.dispose()
      }
    }
  }

  private func fadeSound(
    _ id: String?,
    payload: [String: Any],
    channel: String
  ) {
    guard let id,
          let handle = controlledSound(id, preferredChannel: channel)
    else {
      return
    }
    handle.gain = gainValue(payload["gain"], fallback: handle.gain)
    handle.fadeTo(
      effectiveVolume(channel, handle.gain),
      durationMs: int(payload["time_ms"])
    )
  }

  private func panSound(
    _ id: String?,
    payload: [String: Any],
    channel: String
  ) {
    guard let id,
          let handle = controlledSound(id, preferredChannel: channel)
    else {
      return
    }
    handle.panTo(
      panValue(payload["pan"]),
      durationMs: int(payload["time_ms"])
    )
  }

  private func stopAll() {
    operations.invalidateAll()
    bgm?.dispose()
    bgm = nil
    for handle in sounds.values {
      handle.dispose()
    }
    videoAudio?.dispose()
    videoAudio = nil
    sounds.removeAll()
  }

  private func controlledSound(
    _ id: String,
    preferredChannel: String
  ) -> NativeAudioHandle? {
    if let handle = sounds[soundKey(preferredChannel, id)] {
      return handle
    }
    let alternate = preferredChannel == "voice" ? "se" : "voice"
    return sounds[soundKey(alternate, id)]
  }

  private func makeHandle(
    id: String?,
    source: Data,
    loopSource: Data?,
    channel: String,
    gain: Double,
    pan: Double,
    loop: Bool
  ) async -> NativeAudioHandle? {
    do {
      let playable = try await Task.detached(priority: .userInitiated) {
        try NativeAudioDecoder.playableData(source)
      }.value
      let loopPlayable = try await Task.detached(priority: .userInitiated) {
        try loopSource.map(NativeAudioDecoder.playableData)
      }.value
      return try NativeAudioHandle(
        id: id,
        source: playable,
        loopSource: loopPlayable,
        channel: channel,
        gain: gain,
        pan: pan,
        loop: loop
      )
    } catch {
      AppLogger.warning(
        "Audio decode failed id=\(id ?? "bgm"): \(error.localizedDescription)"
      )
      return nil
    }
  }

  private func resolveAsset(
    _ payload: [String: Any],
    fileKey: String = "file",
    resolvedFileKey: String = "resolved_file"
  ) -> Data? {
    let path = string(payload[fileKey])
    let resolved = string(payload[resolvedFileKey])
    var candidates: [String] = []
    if let resolved, !resolved.isEmpty {
      candidates.append(resolved)
    }
    if let path, !path.isEmpty, path != resolved {
      candidates.append(path)
    }
    for candidate in expandCandidates(candidates) {
      if let data = assetReader?(candidate) {
        return data
      }
    }
    AppLogger.warning(
      "Media asset not found: \(candidates.joined(separator: " -> "))"
    )
    return nil
  }

  private func expandCandidates(_ paths: [String]) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for path in paths {
      let normalized = path.replacingOccurrences(of: "\\", with: "/")
      let candidates = [
        normalized,
        hasExtension(normalized) ? nil : "\(normalized).ogg",
        hasExtension(normalized) ? nil : "\(normalized).oga",
        hasExtension(normalized) ? nil : "\(normalized).wav",
        hasExtension(normalized) ? nil : "\(normalized).mp3",
        hasExtension(normalized) ? nil : "\(normalized).m4a",
      ].compactMap { $0 }
      for candidate in candidates where seen.insert(candidate).inserted {
        result.append(candidate)
      }
    }
    return result
  }

  private func hasExtension(_ path: String) -> Bool {
    guard let name = path.split(separator: "/").last,
          let dot = name.lastIndex(of: ".")
    else {
      return false
    }
    return dot > name.startIndex && dot < name.index(before: name.endIndex)
  }

  private func effectiveVolume(_ channel: String, _ gain: Double) -> Double {
    clamp(
      (channelVolumes["master"] ?? 1)
        * (channelVolumes[channel] ?? 1)
        * gain,
      0,
      1
    )
  }

  private func finishFailedCommand(
    _ kind: String,
    payload: [String: Any]
  ) {
    if kind == "video_play" {
      onVideoFinished?(string(payload["id"]))
    } else if kind == "audio_bgm_play" || kind == "audio_bgm_crossfade" {
      onSoundFinished?(nil)
    } else if kind == "audio_se_play" || kind == "audio_voice_play" {
      onSoundFinished?(string(payload["id"]))
    }
  }

  private func string(_ value: Any?) -> String? {
    value as? String
  }

  private func int(_ value: Any?) -> Int {
    (value as? NSNumber)?.intValue ?? 0
  }

  private func double(_ value: Any?, _ fallback: Double) -> Double {
    (value as? NSNumber)?.doubleValue ?? fallback
  }

  private func gainValue(
    _ value: Any?,
    fallback: Double = 1
  ) -> Double {
    guard let raw = value as? NSNumber else { return fallback }
    let value = raw.doubleValue
    return value > 1 ? value / 1_000 : value
  }

  private func panValue(_ value: Any?) -> Double {
    guard let raw = value as? NSNumber else { return 0 }
    let value = raw.doubleValue
    return clamp(abs(value) > 1 ? value / 1_000 : value, -1, 1)
  }

  private func bool(_ value: Any?) -> Bool {
    (value as? Bool) == true
  }

  private func soundKey(_ channel: String, _ id: String) -> String {
    "\(channel):\(id)"
  }

  private func clamp<T: Comparable>(_ value: T, _ lower: T, _ upper: T) -> T {
    min(max(value, lower), upper)
  }
}

enum NativeAudioDecoder {
  static func playableData(_ input: Data) throws -> Data {
    guard !input.isEmpty else {
      throw AudioDecodeError.empty
    }
    if isOgg(input) {
      return try decodeVorbis(input)
    }
    if isMP3(input) {
      return try decodeMP3(input)
    }

    // WAV and AAC/M4A are handled directly by AVAudioPlayer.
    do {
      _ = try AVAudioPlayer(data: input)
      return input
    } catch {
      throw error
    }
  }

  private static func isOgg(_ data: Data) -> Bool {
    data.count >= 4 && Array(data.prefix(4)) == [0x4F, 0x67, 0x67, 0x53]
  }

  private static func isMP3(_ data: Data) -> Bool {
    if data.count >= 3, Array(data.prefix(3)) == [0x49, 0x44, 0x33] {
      return true
    }
    guard data.count >= 2 else { return false }
    return data[data.startIndex] == 0xFF
      && (data[data.startIndex + 1] & 0xE0) == 0xE0
  }

  private static func decodeVorbis(_ input: Data) throws -> Data {
    var channels: Int32 = 0
    var rate: Int32 = 0
    var frames: Int32 = 0
    var samples: UnsafeMutablePointer<Int16>?
    let result = input.withUnsafeBytes { raw -> Int32 in
      ad_decode_vorbis(
        raw.bindMemory(to: UInt8.self).baseAddress,
        Int32(input.count),
        &channels,
        &rate,
        &frames,
        &samples
      )
    }
    guard result == 0, let samples else {
      throw AudioDecodeError.decodeFailed("Ogg Vorbis")
    }
    defer { ad_free(samples) }
    return try wav(
      samples: samples,
      samplesPerChannel: Int(frames),
      channels: Int(channels),
      sampleRate: Int(rate)
    )
  }

  private static func decodeMP3(_ input: Data) throws -> Data {
    var channels: Int32 = 0
    var rate: Int32 = 0
    var frames: Int32 = 0
    var samples: UnsafeMutablePointer<Int16>?
    let result = input.withUnsafeBytes { raw -> Int32 in
      ad_decode_mp3(
        raw.bindMemory(to: UInt8.self).baseAddress,
        Int32(input.count),
        &channels,
        &rate,
        &frames,
        &samples
      )
    }
    guard result == 0, let samples else {
      throw AudioDecodeError.decodeFailed("MP3")
    }
    defer { ad_free(samples) }
    return try wav(
      samples: samples,
      samplesPerChannel: Int(frames),
      channels: Int(channels),
      sampleRate: Int(rate)
    )
  }

  private static func wav(
    samples: UnsafeMutablePointer<Int16>,
    samplesPerChannel: Int,
    channels: Int,
    sampleRate: Int
  ) throws -> Data {
    guard channels > 0, sampleRate > 0, samplesPerChannel > 0 else {
      throw AudioDecodeError.empty
    }
    let totalSamples = samplesPerChannel * channels
    let dataBytes = totalSamples * MemoryLayout<Int16>.size
    let byteRate = sampleRate * channels * MemoryLayout<Int16>.size
    let blockAlign = channels * MemoryLayout<Int16>.size

    var output = Data(capacity: 44 + dataBytes)
    output.append(contentsOf: Array("RIFF".utf8))
    appendUInt32(UInt32(36 + dataBytes), to: &output)
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
    appendUInt32(UInt32(dataBytes), to: &output)
    UnsafeBufferPointer(start: samples, count: totalSamples)
      .withMemoryRebound(to: UInt8.self) { output.append(contentsOf: $0) }
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

private enum AudioDecodeError: LocalizedError {
  case empty
  case decodeFailed(String)

  var errorDescription: String? {
    switch self {
    case .empty:
      "音频数据为空"
    case .decodeFailed(let format):
      "无法解码 \(format) 音频"
    }
  }
}

@MainActor
final class NativeAudioHandle: NSObject, AVAudioPlayerDelegate {
  let id: String?
  let channel: String
  var gain: Double
  var onCompleted: (() -> Void)?

  private let player: AVAudioPlayer
  private let loopPlayer: AVAudioPlayer?
  private let loop: Bool
  private var pan: Double
  private var effectiveVolume = 1.0
  private var fadeTimer: Timer?
  private var panTimer: Timer?
  private var hostSuspended = false
  private var resumePrimaryAfterSuspend = false
  private var resumeLoopAfterSuspend = false
  private var loopSegmentStarted = false
  private var completed = false
  private var disposed = false

  init(
    id: String?,
    source: Data,
    loopSource: Data?,
    channel: String,
    gain: Double,
    pan: Double,
    loop: Bool
  ) throws {
    self.id = id
    self.channel = channel
    self.gain = gain
    self.pan = pan
    self.loop = loop
    player = try AVAudioPlayer(data: source)
    loopPlayer = try loopSource.map { try AVAudioPlayer(data: $0) }
    super.init()
    player.delegate = self
    player.numberOfLoops = loop && loopSource == nil ? -1 : 0
    player.prepareToPlay()
    player.pan = Float(pan)
    if let loopPlayer {
      loopPlayer.numberOfLoops = -1
      loopPlayer.prepareToPlay()
      loopPlayer.pan = Float(pan)
    }
  }

  func play() {
    guard !disposed else { return }
    if hostSuspended {
      resumePrimaryAfterSuspend = true
      return
    }
    player.play()
  }

  func pause() {
    resumePrimaryAfterSuspend = false
    guard !disposed else { return }
    player.pause()
  }

  func setHostSuspended(_ value: Bool) {
    guard !disposed, hostSuspended != value else { return }
    hostSuspended = value
    if value {
      resumePrimaryAfterSuspend = resumePrimaryAfterSuspend || player.isPlaying
      resumeLoopAfterSuspend = resumeLoopAfterSuspend
        || loopPlayer?.isPlaying == true
      player.pause()
      loopPlayer?.pause()
      return
    }
    let resumePrimary = resumePrimaryAfterSuspend
    let resumeLoop = resumeLoopAfterSuspend
    resumePrimaryAfterSuspend = false
    resumeLoopAfterSuspend = false
    if resumePrimary, !completed {
      player.play()
    }
    if resumeLoop, !completed, let loopPlayer {
      loopPlayer.play()
    }
  }

  func setEffectiveVolume(_ value: Double) {
    effectiveVolume = min(max(value, 0), 1)
    player.volume = Float(effectiveVolume)
    loopPlayer?.volume = Float(effectiveVolume)
  }

  func panTo(_ target: Double, durationMs: Int) {
    panTimer?.invalidate()
    panTimer = nil
    let target = min(max(target, -1), 1)
    guard durationMs > 0 else {
      pan = target
      player.pan = Float(target)
      loopPlayer?.pan = Float(target)
      return
    }
    let start = pan
    let started = CACurrentMediaTime()
    panTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) {
      [weak self] timer in
      Task { @MainActor [weak self] in
        self?.stepPan(
          timer,
          target: target,
          start: start,
          started: started,
          durationMs: durationMs
        )
      }
    }
  }

  func fadeTo(_ target: Double, durationMs: Int) {
    fadeTimer?.invalidate()
    fadeTimer = nil
    guard durationMs > 0 else {
      setEffectiveVolume(target)
      return
    }
    let start = effectiveVolume
    let started = CACurrentMediaTime()
    fadeTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) {
      [weak self] timer in
      Task { @MainActor [weak self] in
        self?.stepFade(
          timer,
          target: target,
          start: start,
          started: started,
          durationMs: durationMs
        )
      }
    }
  }

  private func stepPan(
    _ timer: Timer,
    target: Double,
    start: Double,
    started: CFTimeInterval,
    durationMs: Int
  ) {
    guard !disposed else {
      timer.invalidate()
      panTimer = nil
      return
    }
    let progress = min(
      (CACurrentMediaTime() - started) / (Double(durationMs) / 1_000),
      1
    )
    pan = start + (target - start) * progress
    player.pan = Float(pan)
    loopPlayer?.pan = Float(pan)
    if progress >= 1 {
      timer.invalidate()
      panTimer = nil
    }
  }

  private func stepFade(
    _ timer: Timer,
    target: Double,
    start: Double,
    started: CFTimeInterval,
    durationMs: Int
  ) {
    guard !disposed else {
      timer.invalidate()
      fadeTimer = nil
      return
    }
    let progress = min(
      (CACurrentMediaTime() - started) / (Double(durationMs) / 1_000),
      1
    )
    setEffectiveVolume(start + (target - start) * progress)
    if progress >= 1 {
      timer.invalidate()
      fadeTimer = nil
    }
  }

  func dispose(afterMilliseconds delay: Int = 0) {
    guard !disposed else { return }
    if delay > 0 {
      DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
        self.dispose()
      }
      return
    }
    disposed = true
    completed = true
    fadeTimer?.invalidate()
    fadeTimer = nil
    panTimer?.invalidate()
    panTimer = nil
    player.stop()
    loopPlayer?.stop()
    player.delegate = nil
  }

  nonisolated func audioPlayerDidFinishPlaying(
    _ player: AVAudioPlayer,
    successfully flag: Bool
  ) {
    Task { @MainActor [weak self] in
      guard let self, !self.disposed, !self.completed else { return }
      if self.loop, let loopPlayer, !self.loopSegmentStarted {
        self.loopSegmentStarted = true
        if self.hostSuspended {
          self.resumeLoopAfterSuspend = true
        } else {
          loopPlayer.currentTime = 0
          loopPlayer.play()
        }
        return
      }
      self.completed = true
      self.onCompleted?()
    }
  }
}
