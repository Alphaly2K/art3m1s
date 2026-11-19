import Accelerate
import AVFoundation
import CoreVideo
import FlutterMacOS
import Foundation

private enum ArtemisFlutterError: Error {
    case invalidArguments
    case closedSession
    case staleReply
}

/// Keep one instance on the macOS Runner for the lifetime of the Flutter engine.
@MainActor final class ArtemisFlutterHost {
    static let channelName = "moe.alphaly.art3m1s/artemis_v2"

    private let corePath: String
    private let metalPath: String
    private let mediaPath: String?
    private var mediaLibrary: ArtemisLegacyMediaLibrary?
    private let registry: FlutterTextureRegistry
    private var channel: FlutterMethodChannel?
    private var sessions: [String: Session] = [:]

    init(registry: FlutterTextureRegistry, corePath: String, metalPath: String, mediaPath: String? = nil) {
        self.corePath = corePath
        self.metalPath = metalPath
        self.mediaPath = mediaPath
        self.registry = registry
    }

    func register(messenger: FlutterBinaryMessenger) {
        let channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
        channel.setMethodCallHandler { [weak self] call, result in
            MainActor.assumeIsolated {
                guard let self else {
                    result(FlutterError(code: "closed_host", message: nil, details: nil))
                    return
                }
                do {
                    result(try self.handle(call))
                } catch ArtemisFlutterError.closedSession {
                    result(FlutterError(code: "closed_session", message: nil, details: nil))
                } catch ArtemisFlutterError.staleReply {
                    result(FlutterError(code: "stale_reply", message: nil, details: nil))
                } catch ArtemisMacError.status(_, let status, _)
                    where status == ArtSwiftStale {
                    result(FlutterError(code: "stale_reply", message: nil, details: nil))
                } catch {
                    result(FlutterError(code: "artemis_v2", message: String(describing: error), details: nil))
                }
            }
        }
        self.channel = channel
    }

    func close() {
        channel?.setMethodCallHandler(nil)
        channel = nil
        for session in sessions.values { try? close(session) }
        sessions.removeAll()
    }

    func handle(_ call: FlutterMethodCall) throws -> Any? {
        guard let args = call.arguments as? [String: Any] else {
            throw ArtemisFlutterError.invalidArguments
        }
        if call.method == "open" {
            guard let ini = bytes(args["ini"]),
                  let platform = args["platform"] as? String else { throw ArtemisFlutterError.invalidArguments }
            let caps = try number(args["hostCaps"], as: UInt64.self)
            let core = try ArtemisMacSession(corePath: corePath, metalPath: metalPath, hostCaps: caps,
                                             screenshots: args["screenshots"] as? Bool ?? false)
            do {
                try core.openProject(ini, platform: platform, reportedOS: args["reportedOS"] as? String)
                let id = UUID().uuidString
                var result = try state(core)
                result["session"] = id
                sessions[id] = Session(core)
                return result
            } catch {
                try? core.close()
                throw error
            }
        }
        guard let id = args["session"] as? String else { throw ArtemisFlutterError.invalidArguments }
        if call.method == "close" {
            if let session = sessions.removeValue(forKey: id) { try close(session) }
            return nil
        }
        guard let session = sessions[id] else { throw ArtemisFlutterError.closedSession }
        switch call.method {
        case "surface":
            guard let width = args["width"] as? Int, let height = args["height"] as? Int,
                  (1...16384).contains(width), (1...16384).contains(height) else {
                throw ArtemisFlutterError.invalidArguments
            }
            try detach(session)
            let texture = try Texture(width: width, height: height)
            try session.core.setSurface(texture.buffer)
            let textureID = registry.register(texture)
            session.texture = (textureID, texture)
            return textureID
        case "detach":
            try detach(session)
            return nil
        case "submit":
            guard let batch = args["batch"] as? [[String: Any]] else { throw ArtemisFlutterError.invalidArguments }
            return try submit(batch, to: session, owner: id)
        case "videoOpen":
            let epoch = try number(args["epoch"], as: UInt64.self)
            guard try session.core.state().session_epoch == epoch else { throw ArtemisFlutterError.staleReply }
            let playback = try number(args["playback"], as: UInt64.self)
            let volume = args["volume"] as? Double ?? 1
            guard let path = args["path"] as? String, path.hasPrefix("/"),
                  session.videos[playback] == nil, (0...1).contains(volume) else {
                throw ArtemisFlutterError.invalidArguments
            }
            let url = URL(fileURLWithPath: path)
            let loop = args["loop"] as? Bool == true
            let source: ArtemisVideoSource
            if ["asf", "wmv", "ogv", "ogg"].contains(url.pathExtension.lowercased()), let mediaPath {
                let library = try mediaLibrary ?? ArtemisLegacyMediaLibrary(path: mediaPath)
                mediaLibrary = library
                source = ArtemisLegacyVideoSource(library: library, path: path, loop: loop,
                    delayMarginMS: args["delayMarginMs"] as? Int,
                    suspended: session.videoSuspended, volume: Float(volume))
            } else {
                source = AVVideoSource(url: url, loop: loop, suspended: session.videoSuspended, volume: Float(volume))
            }
            session.videos[playback] = ArtemisFlutterVideo(epoch: epoch, fullscreen: args["fullscreen"] as? Bool == true, source: source)
            return nil
        case "videoClose":
            if let video = session.videos.removeValue(forKey: try number(args["playback"], as: UInt64.self)) {
                video.close(registry)
            }
            return nil
        case "videoSuspend":
            session.videoSuspended = args["suspended"] as? Bool == true
            for video in session.videos.values { video.setSuspended(session.videoSuspended) }
            return nil
        case "videoVolume":
            guard let volume = args["volume"] as? Double, (0...1).contains(volume) else {
                throw ArtemisFlutterError.invalidArguments
            }
            for video in session.videos.values { video.setVolume(Float(volume)) }
            return nil
        case "videoPoll":
            return try pollVideos(session)
        case "step":
            let (backpressured, step) = try session.core.step(
                frameID: number(args["frame"], as: UInt64.self),
                monotonicNS: number(args["monotonicNS"], as: UInt64.self),
                unixMS: number(args["unixMS"], as: Int64.self),
                utcOffsetMinutes: number(args["utcOffsetMinutes"], as: Int32.self))
            var result = try state(session.core)
            result["backpressured"] = backpressured
            result["stepFlags"] = Int(step.flags)
            return result
        case "poll":
            return try session.core.pollEvents().map { event -> [String: Any] in
                if event.domain == UInt16(ArtSwiftRuntime),
                   event.kind == UInt32(ArtSwiftSessionChanged) || event.kind == UInt32(ArtSwiftRuntimeClosed) {
                    session.requests.removeAll()
                }
                if event.requiresReply { session.requests[event.requestID] = event }
                if event.domain == UInt16(ArtSwiftUI), event.kind == UInt32(ArtSwiftHttpCancel),
                   let metadata = (try? JSONSerialization.jsonObject(with: event.metadata)) as? [String: Any],
                   let request = (metadata["request_id"] as? String).flatMap(UInt64.init),
                   let original = session.requests[request], original.epoch == event.epoch,
                   original.domain == event.domain, original.kind == UInt32(ArtSwiftHttpRequest) {
                    session.requests.removeValue(forKey: request)
                }
                return ["owner": id, "domain": Int(event.domain), "kind": Int(event.kind), "epoch": String(event.epoch),
                        "sequence": String(event.sequence), "request": String(event.requestID),
                        "metadata": FlutterStandardTypedData(bytes: event.metadata),
                        "blob": FlutterStandardTypedData(bytes: event.blob)]
            }
        case "present":
            guard let textureID = session.texture?.id, let frameID = try session.core.present() else { return nil }
            registry.textureFrameAvailable(textureID)
            return String(frameID)
        case "capture":
            let frame = try session.core.capture(frameID: number(args["frame"], as: UInt64.self))
            return ["width": Int(frame.width), "height": Int(frame.height),
                    "rgba": FlutterStandardTypedData(bytes: frame.rgba)]
        default:
            throw ArtemisFlutterError.invalidArguments
        }
    }

    private func submit(_ batch: [[String: Any]], to session: Session, owner: String) throws -> Bool {
        var acceptedRequests: [UInt64] = []
        let messages = try batch.map { args -> ArtemisMacMessage in
            let domain = try number(args["domain"], as: UInt16.self)
            let kind = try number(args["kind"], as: UInt32.self)
            let epoch = try number(args["epoch"], as: UInt64.self)
            let request = try number(args["request"], as: UInt64.self)
            guard let metadata = bytes(args["metadata"]) else { throw ArtemisFlutterError.invalidArguments }
            let blob = bytes(args["blob"]) ?? Data()
            if request == 0 {
                if let source = args["owner"] as? String, source != owner {
                    throw ArtemisFlutterError.staleReply
                }
                return ArtemisMacMessage(domain: domain, kind: kind, epoch: epoch, metadata: metadata, blob: blob)
            }
            guard args["owner"] as? String == owner,
                  let original = session.requests[request], original.domain == domain,
                  original.kind == kind, original.epoch == epoch else { throw ArtemisFlutterError.staleReply }
            acceptedRequests.append(request)
            return try original.reply(metadata: metadata, blob: blob)
        }
        do {
            guard try session.core.submit(messages) else { return false }
        } catch ArtemisMacError.status(_, let status, _) where status == ArtSwiftStale {
            if messages.count == 1, let request = acceptedRequests.first {
                session.requests.removeValue(forKey: request)
            }
            throw ArtemisFlutterError.staleReply
        }
        for request in acceptedRequests { session.requests.removeValue(forKey: request) }
        return true
    }

    private func state(_ core: ArtemisMacSession) throws -> [String: Any] {
        let state = try core.state()
        return ["epoch": String(state.session_epoch), "frame": String(state.host_frame_id),
                "width": Int(state.stage_width), "height": Int(state.stage_height),
                "phase": Int(state.state), "waitFlags": Int(state.wait_flags), "exitRequested": state.exit_requested != 0]
    }

    private func pollVideos(_ session: Session) throws -> [[String: Any]] {
        let state = try session.core.state()
        var events: [[String: Any]] = []
        for (id, video) in Array(session.videos) {
            if state.session_epoch != video.epoch || state.state == 4 {
                session.videos.removeValue(forKey: id)?.close(registry)
                continue
            }
            if let terminal = video.terminalState(after: state.host_frame_id) {
                events.append(["playback": String(id), "status": terminal])
                session.videos.removeValue(forKey: id)?.close(registry)
                continue
            }
            guard !session.videoSuspended else { continue }
            var event: [String: Any] = ["playback": String(id), "status": "started"]
            if video.fullscreen {
                guard let pixelBuffer = video.frame() else { continue }
                video.texture.publish(pixelBuffer)
                if video.textureID == nil { video.textureID = registry.register(video.texture) }
                guard let textureID = video.textureID else { continue }
                registry.textureFrameAvailable(textureID)
                event["texture"] = textureID
                event["width"] = CVPixelBufferGetWidth(pixelBuffer)
                event["height"] = CVPixelBufferGetHeight(pixelBuffer)
            } else {
                do {
                    let delivered = try video.deliverLayerFrame(playbackID: id, hostFrameID: state.host_frame_id) {
                        try session.core.submit([$0])
                    }
                    guard delivered else { continue }
                } catch ArtemisMacError.status(_, let status, _) where status == ArtSwiftStale {
                    session.videos.removeValue(forKey: id)?.close(registry)
                    continue
                } catch {
                    events.append(["playback": String(id), "status": "failed"])
                    session.videos.removeValue(forKey: id)?.close(registry)
                    continue
                }
            }
            if !video.started {
                video.started = true
                events.append(event)
            }
        }
        return events
    }

    private func detach(_ session: Session) throws {
        guard let textureID = session.texture?.id else { return }
        try session.core.setSurface(nil)
        session.texture = nil
        registry.unregisterTexture(textureID)
    }

    private func close(_ session: Session) throws {
        let textureID = session.texture?.id
        for video in session.videos.values { video.close(registry) }
        session.videos.removeAll()
        defer {
            if let textureID { registry.unregisterTexture(textureID) }
            session.texture = nil
        }
        try session.core.close()
    }
}

private extension ArtemisFlutterHost {
    final class Session {
        let core: ArtemisMacSession
        var texture: (id: Int64, texture: Texture)?
        var requests: [UInt64: ArtemisMacEvent] = [:]
        var videos: [UInt64: ArtemisFlutterVideo] = [:]
        var videoSuspended = false

        init(_ core: ArtemisMacSession) { self.core = core }
    }

    final class Texture: NSObject, FlutterTexture {
        let buffer: CVPixelBuffer

        init(width: Int, height: Int) throws {
            let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:],
                                              kCVPixelBufferMetalCompatibilityKey: true]
            var buffer: CVPixelBuffer?
            let status = CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA,
                                             attributes as CFDictionary, &buffer)
            guard status == kCVReturnSuccess, let buffer else {
                throw ArtemisMacError.status("create pixel buffer", status, "")
            }
            self.buffer = buffer
        }

        func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? { .passRetained(buffer) }
    }
}

@MainActor final class ArtemisFlutterVideo {
    let epoch: UInt64
    let fullscreen: Bool
    fileprivate let texture = VideoTexture()
    var textureID: Int64?
    var started = false
    private let source: ArtemisVideoSource
    private var frameID: UInt64 = 0
    private var pendingLayerFrame: ArtemisMacMessage?
    private var submittedOnHostFrame: UInt64?

    init(epoch: UInt64, fullscreen: Bool, source: ArtemisVideoSource) {
        self.epoch = epoch
        self.fullscreen = fullscreen
        self.source = source
    }

    func terminalState(after hostFrameID: UInt64) -> String? {
        let status = source.terminalState
        if status == "ended", !fullscreen {
            if pendingLayerFrame != nil { return nil }
            // End clears the layer, so let Core apply the last submitted frame first.
            if let submittedOnHostFrame, submittedOnHostFrame >= hostFrameID { return nil }
        }
        return status
    }

    func deliverLayerFrame(playbackID: UInt64, hostFrameID: UInt64,
                           submit: (ArtemisMacMessage) throws -> Bool) throws -> Bool {
        let message: ArtemisMacMessage
        if let pending = pendingLayerFrame {
            message = pending
        } else {
            guard source.terminalState == nil, let pixels = source.frame() else { return false }
            let width = CVPixelBufferGetWidth(pixels), height = CVPixelBufferGetHeight(pixels)
            let metadata = try JSONSerialization.data(withJSONObject: [
                "playback_id": String(playbackID), "frame_id": String(frameID + 1), "width": width, "height": height,
            ])
            message = ArtemisMacMessage(domain: UInt16(ArtSwiftMedia), kind: UInt32(ArtSwiftVideoFrame), epoch: epoch,
                                        metadata: metadata, blob: try rgbaPixels(pixels, width: width, height: height))
            pendingLayerFrame = message
        }
        guard try submit(message) else { return false }
        frameID += 1
        submittedOnHostFrame = hostFrameID
        pendingLayerFrame = nil
        return true
    }

    func frame() -> CVPixelBuffer? { source.frame() }
    func setVolume(_ volume: Float) { source.setVolume(volume) }
    func setSuspended(_ suspended: Bool) { source.setSuspended(suspended) }

    func close(_ registry: FlutterTextureRegistry) {
        source.close()
        pendingLayerFrame = nil
        texture.publish(nil)
        if let textureID { registry.unregisterTexture(textureID) }
        textureID = nil
    }
}

@MainActor private final class AVVideoSource: ArtemisVideoSource {
    private let player: AVPlayer
    private let item: AVPlayerItem
    private let output: AVPlayerItemVideoOutput
    private var finished: String?
    private var suspended: Bool
    private var hasFrame = false
    private var observers: [NSObjectProtocol] = []

    init(url: URL, loop: Bool, suspended: Bool, volume: Float) {
        self.suspended = suspended
        item = AVPlayerItem(url: url)
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ])
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.volume = volume
        player.actionAtItemEnd = .pause
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if loop && self.hasFrame {
                    self.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                    if !self.suspended { self.player.play() }
                } else {
                    self.finished = self.hasFrame ? "ended" : "failed"
                }
            }
        })
        observers.append(center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.finished = "failed" }
        })
        if !suspended { player.play() }
    }

    var terminalState: String? { item.status == .failed ? "failed" : finished }

    func setVolume(_ volume: Float) { player.volume = volume }

    func frame() -> CVPixelBuffer? {
        guard !suspended else { return nil }
        let time = item.currentTime()
        guard output.hasNewPixelBuffer(forItemTime: time) else { return nil }
        let frame = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil)
        if frame != nil { hasFrame = true }
        return frame
    }

    func setSuspended(_ value: Bool) {
        guard suspended != value else { return }
        suspended = value
        if value { player.pause() } else if terminalState == nil { player.play() }
    }

    func close() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

private final class VideoTexture: NSObject, FlutterTexture {
    private let lock = NSLock()
    private var buffer: CVPixelBuffer?

    func publish(_ buffer: CVPixelBuffer?) { lock.withLock { self.buffer = buffer } }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? { lock.withLock { buffer.map { .passRetained($0) } } }
}

private func rgbaPixels(_ buffer: CVPixelBuffer, width: Int, height: Int) throws -> Data {
    guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA,
          (1...16384).contains(width), (1...16384).contains(height), width * height * 4 <= 64 * 1024 * 1024,
          CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else {
        throw ArtemisFlutterError.invalidArguments
    }
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw ArtemisFlutterError.invalidArguments }
    var data = Data(count: width * height * 4)
    let status = data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
        var source = vImage_Buffer(data: base, height: vImagePixelCount(height), width: vImagePixelCount(width),
                                   rowBytes: CVPixelBufferGetBytesPerRow(buffer))
        var destination = vImage_Buffer(data: bytes.baseAddress, height: vImagePixelCount(height),
                                        width: vImagePixelCount(width), rowBytes: width * 4)
        return vImagePermuteChannels_ARGB8888(&source, &destination, [2, 1, 0, 3], vImage_Flags(kvImageNoFlags))
    }
    guard status == kvImageNoError else { throw ArtemisFlutterError.invalidArguments }
    return data
}

private func bytes(_ value: Any?) -> Data? { (value as? FlutterStandardTypedData)?.data }

private func number<T: FixedWidthInteger>(_ value: Any?, as type: T.Type) throws -> T {
    if let text = value as? String, let number = T(text) { return number }
    if let value = value as? Int, let number = T(exactly: value) { return number }
    throw ArtemisFlutterError.invalidArguments
}
