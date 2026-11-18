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
    private let registry: FlutterTextureRegistry
    private var channel: FlutterMethodChannel?
    private var sessions: [String: Session] = [:]

    init(registry: FlutterTextureRegistry, corePath: String, metalPath: String) {
        self.corePath = corePath
        self.metalPath = metalPath
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
                    where call.method == "submit" && status == ArtSwiftStale {
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
                return ArtemisMacMessage(domain: domain, kind: kind, epoch: epoch, metadata: metadata, blob: blob)
            }
            guard args["owner"] as? String == owner,
                  let original = session.requests[request], original.domain == domain,
                  original.kind == kind, original.epoch == epoch else { throw ArtemisFlutterError.staleReply }
            acceptedRequests.append(request)
            return try original.reply(metadata: metadata, blob: blob)
        }
        guard try session.core.submit(messages) else { return false }
        for request in acceptedRequests { session.requests.removeValue(forKey: request) }
        return true
    }

    private func state(_ core: ArtemisMacSession) throws -> [String: Any] {
        let state = try core.state()
        return ["epoch": String(state.session_epoch), "frame": String(state.host_frame_id),
                "width": Int(state.stage_width), "height": Int(state.stage_height),
                "phase": Int(state.state), "waitFlags": Int(state.wait_flags), "exitRequested": state.exit_requested != 0]
    }

    private func detach(_ session: Session) throws {
        guard let textureID = session.texture?.id else { return }
        try session.core.setSurface(nil)
        session.texture = nil
        registry.unregisterTexture(textureID)
    }

    private func close(_ session: Session) throws {
        let textureID = session.texture?.id
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

private func bytes(_ value: Any?) -> Data? { (value as? FlutterStandardTypedData)?.data }

private func number<T: FixedWidthInteger>(_ value: Any?, as type: T.Type) throws -> T {
    if let text = value as? String, let number = T(text) { return number }
    if let value = value as? Int, let number = T(exactly: value) { return number }
    throw ArtemisFlutterError.invalidArguments
}
