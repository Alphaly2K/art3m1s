import CoreVideo
import Darwin
import Foundation

enum ArtemisMacError: Error, CustomStringConvertible {
    case loader(String)
    case protocolError(String)
    case status(String, ArtStatus, String)
    case closed
    case wrongSession

    var description: String {
        switch self {
        case let .loader(message), let .protocolError(message): return message
        case let .status(operation, status, detail):
            return "Artemis \(operation) (\(status))\(detail.isEmpty ? "" : ": \(detail)")"
        case .closed: return "Artemis session is closed"
        case .wrongSession: return "The request belongs to another Artemis session"
        }
    }
}

struct ArtemisMacMessage: Sendable {
    let domain: UInt16
    let kind: UInt32
    let epoch: UInt64
    let metadata: Data
    let blob: Data
    fileprivate let requestID: UInt64
    fileprivate let sessionID: UUID?

    init(domain: UInt16, kind: UInt32, epoch: UInt64, metadata: Data, blob: Data = Data()) {
        self.init(domain: domain, kind: kind, epoch: epoch, metadata: metadata, blob: blob,
                  requestID: 0, sessionID: nil)
    }

    fileprivate init(domain: UInt16, kind: UInt32, epoch: UInt64, metadata: Data, blob: Data,
                     requestID: UInt64, sessionID: UUID?) {
        self.domain = domain
        self.kind = kind
        self.epoch = epoch
        self.metadata = metadata
        self.blob = blob
        self.requestID = requestID
        self.sessionID = sessionID
    }
}

struct ArtemisMacEvent: Sendable {
    let domain: UInt16
    let kind: UInt32
    let epoch: UInt64
    let sequence: UInt64
    let requestID: UInt64
    let metadata: Data
    let blob: Data
    fileprivate let sessionID: UUID

    var requiresReply: Bool { requestID != 0 }

    func reply(metadata: Data, blob: Data = Data()) throws -> ArtemisMacMessage {
        guard requiresReply else { throw ArtemisMacError.protocolError("Event is not a request") }
        return ArtemisMacMessage(domain: domain, kind: kind, epoch: epoch, metadata: metadata,
                                 blob: blob, requestID: requestID, sessionID: sessionID)
    }
}

private final class ArtemisMacLibrary {
    private let handle: UnsafeMutableRawPointer

    init(path: String) throws {
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw ArtemisMacError.loader(dlerror().map { String(cString: $0) } ?? "Cannot open \(path)")
        }
        self.handle = handle
    }

    func symbol<T>(_ name: String, as type: T.Type) throws -> T {
        guard let address = dlsym(handle, name) else {
            throw ArtemisMacError.loader("Missing symbol \(name)")
        }
        return unsafeBitCast(address, to: type)
    }

    deinit { dlclose(handle) }
}

private struct ArtemisMacMetal {
    let create: ArtSwiftMetalCreate
    let destroy: ArtSwiftMetalDestroy
    let attach: ArtSwiftMetalSurface
    let present: ArtSwiftMetalPresent
    let capture: ArtSwiftMetalCapture

    init(_ library: ArtemisMacLibrary) throws {
        create = try library.symbol("art3m1s_metal_host_v1_create", as: ArtSwiftMetalCreate.self)
        destroy = try library.symbol("art3m1s_metal_host_v1_destroy", as: ArtSwiftMetalDestroy.self)
        attach = try library.symbol("art3m1s_metal_host_v1_set_surface", as: ArtSwiftMetalSurface.self)
        present = try library.symbol("art3m1s_metal_host_v1_present", as: ArtSwiftMetalPresent.self)
        capture = try library.symbol("art3m1s_metal_host_v1_capture", as: ArtSwiftMetalCapture.self)
    }
}

private struct ArtemisMacRenderer {
    let library: ArtemisMacLibrary
    let metal: ArtemisMacMetal
    let handle: OpaquePointer
}

// Cleanup can move to the main queue once, after the last session reference goes away.
private struct ArtemisMacNative: @unchecked Sendable {
    let coreLibrary: ArtemisMacLibrary
    let root: UnsafePointer<ArtRootApiV2>
    let api: ArtRuntimeApiV2
    let handle: ArtRuntimeHandle
    let renderer: ArtemisMacRenderer?
    var surface: CVPixelBuffer?

    func close() throws {
        defer { withExtendedLifetime((coreLibrary, renderer, surface)) {} }
        let rendererStatus = renderer.map { $0.metal.destroy($0.handle) } ?? ArtStatus(ArtSwiftOK)
        let coreStatus = api.destroy(handle)
        try check(rendererStatus, "destroy renderer")
        try check(coreStatus, "destroy", root: root)
    }
}

private final class ArtemisMacLifetime {
    var native: ArtemisMacNative?

    init(_ native: ArtemisMacNative) { self.native = native }

    deinit {
        guard let native else { return }
        if Thread.isMainThread {
            try? native.close()
        } else {
            DispatchQueue.main.async { try? native.close() }
        }
    }
}

/// The application owns scheduling, IO and texture registration. Core and Metal calls use the main thread.
@MainActor final class ArtemisMacSession {
    private let lifetime: ArtemisMacLifetime
    private let sessionID = UUID()
    private var presented: UInt64 = 0
    private var pollCapacity = 4096

    init(corePath: String, metalPath: String?, hostCaps: UInt64, screenshots: Bool = false,
         randomSeed: UInt64 = 0, angleDirectory: String? = nil, dxvkDirectory: String? = nil) throws {
        let core = try ArtemisMacLibrary(path: corePath)
        let getAPI = try core.symbol("art3m1s_get_api_v2", as: ArtSwiftGetAPI.self)
        let rootSize = UInt32(MemoryLayout<ArtRootApiV2>.size)
        var rootPointer: UnsafePointer<ArtRootApiV2>?
        try check(getAPI(UInt32(ArtSwiftMajor), rootSize, &rootPointer), "get API")
        guard let root = rootPointer, art_swift_header_valid(root.pointee.header, 0, rootSize) != 0,
              let query = root.pointee.query_interface, root.pointee.copy_last_error != nil else {
            throw ArtemisMacError.protocolError("Invalid Artemis root table")
        }
        func queryTable<T>(_ id: UInt32, _ type: T.Type) throws -> UnsafePointer<T> {
            var table: UnsafeRawPointer?
            try check(query(id, UInt32(ArtSwiftMajor), UInt32(MemoryLayout<T>.size), &table),
                      "query interface", root: root)
            guard let table else { throw ArtemisMacError.protocolError("Missing Artemis interface table") }
            return table.assumingMemoryBound(to: type)
        }
        let runtimeID = UInt32(ArtSwiftRuntime)
        let api = try queryTable(runtimeID, ArtRuntimeApiV2.self).pointee
        guard art_swift_header_valid(api.header, runtimeID, UInt32(MemoryLayout<ArtRuntimeApiV2>.size)) != 0,
              api.create != nil, api.destroy != nil, api.open_project != nil, api.step != nil,
              api.get_state != nil, api.poll_events != nil, api.submit != nil else {
            throw ArtemisMacError.protocolError("Invalid Artemis runtime table")
        }
        let rendererCaps: UInt64 = if metalPath == nil {
            0
        } else if angleDirectory != nil && dxvkDirectory != nil {
            art_swift_mixed_renderer_caps(screenshots ? 1 : 0)
        } else if angleDirectory != nil {
            art_swift_angle_renderer_caps(screenshots ? 1 : 0)
        } else {
            art_swift_renderer_caps(screenshots ? 1 : 0)
        }
        var config = ArtCreateInfo(struct_size: UInt32(MemoryLayout<ArtCreateInfo>.size), flags: 0,
                                   host_service_caps: hostCaps,
                                   renderer_caps: rendererCaps,
                                   random_seed: randomSeed)
        var handle: ArtRuntimeHandle = 0
        try check(api.create(&config, &handle), "create", root: root)
        do {
            var display: ArtemisMacRenderer?
            if let metalPath {
                let frames = try queryTable(UInt32(ArtSwiftFrame), ArtFrameApiV2.self)
                let metalLibrary = try ArtemisMacLibrary(path: metalPath)
                let metal = try ArtemisMacMetal(metalLibrary)
                var renderer: OpaquePointer?
                if let angleDirectory, let dxvkDirectory {
                    let create = try metalLibrary.symbol("art3m1s_metal_host_v1_create_mixed", as: ArtSwiftMixedCreate.self)
                    try check(dxvkDirectory.withCString { dxvk in
                        angleDirectory.withCString { angle in create(frames, handle, dxvk, angle, &renderer) }
                    }, "create mixed renderer")
                } else if let angleDirectory {
                    let create = try metalLibrary.symbol("art3m1s_metal_host_v1_create_angle", as: ArtSwiftAngleCreate.self)
                    try check(angleDirectory.withCString { create(frames, handle, $0, &renderer) }, "create ANGLE renderer")
                } else if let dxvkDirectory {
                    let create = try metalLibrary.symbol("art3m1s_metal_host_v1_create_dxvk", as: ArtSwiftDxvkCreate.self)
                    try check(dxvkDirectory.withCString { create(frames, handle, $0, &renderer) }, "create DXVK renderer")
                } else {
                    try check(metal.create(frames, handle, &renderer), "create renderer")
                }
                guard let renderer else { throw ArtemisMacError.protocolError("Missing Metal renderer") }
                display = ArtemisMacRenderer(library: metalLibrary, metal: metal, handle: renderer)
            }
            lifetime = ArtemisMacLifetime(ArtemisMacNative(coreLibrary: core,
                root: root, api: api, handle: handle, renderer: display))
        } catch {
            _ = api.destroy(handle)
            throw error
        }
    }

    func close() throws {
        guard let native = lifetime.native else { return }
        lifetime.native = nil
        try native.close()
    }

    private func live() throws -> ArtemisMacNative {
        guard let native = lifetime.native else { throw ArtemisMacError.closed }
        return native
    }

    var hasRenderer: Bool { lifetime.native?.renderer != nil }

    private func liveRenderer() throws -> ArtemisMacRenderer {
        guard let renderer = try live().renderer else {
            throw ArtemisMacError.protocolError("The Artemis session has no renderer")
        }
        return renderer
    }

    func prepareADE2(source: Data, artifact: Data) throws {
        let renderer = try liveRenderer()
        let prepare = try renderer.library.symbol("art3m1s_metal_host_v1_prepare_ade2", as: ArtSwiftPrepareADE2.self)
        try withBytes(source) { source in
            try withBytes(artifact) { artifact in
                try check(prepare(renderer.handle, source, artifact), "prepare DXVK effect")
            }
        }
    }

    func warmGLSL(_ sources: [Data], cacheDirectory: URL? = nil) throws {
        let renderer = try liveRenderer()
        if let cacheDirectory,
           let cache = try? renderer.library.symbol("art3m1s_metal_host_v1_set_glsl_cache", as: ArtSwiftGlslCache.self) {
            _ = cacheDirectory.path.withCString { cache(renderer.handle, $0) }
        }
        guard !sources.isEmpty,
              let prepare = try? renderer.library.symbol("art3m1s_metal_host_v1_prepare_glsl", as: ArtSwiftPrepareGlsl.self)
        else { return }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        for source in sources {
            if ProcessInfo.processInfo.systemUptime >= deadline { break }
            _ = withBytes(source) { prepare(renderer.handle, $0) }
        }
    }

    func openProject(_ ini: Data, platform: String, reportedOS: String? = nil) throws {
        let native = try live()
        try withBytes(ini) { iniBytes in
            try withBytes(Data(platform.utf8)) { platformBytes in
                try withBytes(Data((reportedOS ?? "").utf8)) { osBytes in
                    var info = ArtProjectInfo(struct_size: UInt32(MemoryLayout<ArtProjectInfo>.size),
                        flags: 0, ini_bytes: iniBytes, platform_utf8: platformBytes, reported_os_utf8: osBytes)
                    try check(native.api.open_project(native.handle, &info), "open project", root: native.root)
                }
            }
        }
        presented = 0
    }

    func step(frameID: UInt64, monotonicNS: UInt64, unixMS: Int64, utcOffsetMinutes: Int32,
              backgroundAutosave: Bool = false)
        throws -> (backpressured: Bool, result: ArtStepResult) {
        let native = try live()
        let flags: UInt32 = backgroundAutosave ? UInt32(ArtSwiftBackgroundAutosave) : 0
        var info = ArtStepInfo(struct_size: UInt32(MemoryLayout<ArtStepInfo>.size), flags: flags,
                               host_frame_id: frameID, monotonic_ns: monotonicNS, utc_unix_ms: unixMS,
                               utc_offset_minutes: utcOffsetMinutes, reserved: 0)
        var result = ArtStepResult()
        result.struct_size = UInt32(MemoryLayout<ArtStepResult>.size)
        let status = native.api.step(native.handle, &info, &result)
        if status != ArtSwiftWouldBlock { try check(status, "step", root: native.root) }
        return (status == ArtSwiftWouldBlock, result)
    }

    func state() throws -> ArtRuntimeState {
        let native = try live()
        var result = ArtRuntimeState()
        result.struct_size = UInt32(MemoryLayout<ArtRuntimeState>.size)
        try check(native.api.get_state(native.handle, &result), "state", root: native.root)
        return result
    }

    /// Returns false when Core has not accepted the batch. The original batch can be retried.
    func submit(_ batch: [ArtemisMacMessage]) throws -> Bool {
        let native = try live()
        guard !batch.isEmpty else { return true }
        guard let count = UInt32(exactly: batch.count) else {
            throw ArtemisMacError.protocolError("Too many Artemis messages")
        }
        var data = Data()
        for message in batch {
            if let id = message.sessionID, id != sessionID { throw ArtemisMacError.wrongSession }
            data.append(message.metadata)
            data.append(message.blob)
        }
        let status = data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let base = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self)
            var offset = 0
            func take(_ length: Int) -> ArtBytes {
                defer { offset += length }
                return ArtBytes(data: length == 0 ? nil : base?.advanced(by: offset), size: UInt64(length))
            }
            let messages = batch.map { message in
                ArtMessage(struct_size: UInt32(MemoryLayout<ArtMessage>.size), domain: message.domain,
                           schema_version: UInt16(ArtSwiftSubmitVersion), kind: message.kind, flags: 0,
                           session_epoch: message.epoch, request_id: message.requestID,
                           metadata_utf8: take(message.metadata.count), blob: take(message.blob.count))
            }
            return messages.withUnsafeBufferPointer { native.api.submit(native.handle, $0.baseAddress, count) }
        }
        if status == ArtSwiftWouldBlock { return false }
        try check(status, "submit", root: native.root)
        return true
    }

    /// Returns one batch of owned events. Poll until empty when draining the queue.
    func pollEvents() throws -> [ArtemisMacEvent] {
        let native = try live()
        var buffer = Data(count: pollCapacity)
        var result = ArtPollResult()
        func poll() -> ArtStatus {
            result.struct_size = UInt32(MemoryLayout<ArtPollResult>.size)
            return buffer.withUnsafeMutableBytes { bytes in
                native.api.poll_events(native.handle, bytes.bindMemory(to: UInt8.self).baseAddress,
                                       UInt64(bytes.count), &result)
            }
        }
        var status = poll()
        if status == ArtSwiftBuffer {
            guard let required = Int(exactly: result.required_next_bytes), required > buffer.count else {
                throw ArtemisMacError.protocolError("Invalid Artemis poll buffer size")
            }
            pollCapacity = required
            buffer = Data(count: required)
            status = poll()
        }
        if status == ArtSwiftNoData { return [] }
        try check(status, "poll events", root: native.root)
        guard result.written_bytes <= UInt64(buffer.count) else {
            throw ArtemisMacError.protocolError("Invalid Artemis event batch size")
        }
        return try decodeEvents(buffer, end: Int(result.written_bytes), count: result.record_count,
                                runtime: native.handle, sessionID: sessionID)
    }

    func setSurface(_ buffer: CVPixelBuffer?) throws {
        let renderer = try liveRenderer()
        let surface = buffer.flatMap { CVPixelBufferGetIOSurface($0)?.takeUnretainedValue() }
        if buffer != nil && surface == nil { throw ArtemisMacError.protocolError("Pixel buffer has no IOSurface") }
        let status = renderer.metal.attach(renderer.handle, surface)
        lifetime.native?.surface = status == ArtSwiftOK ? buffer : nil
        presented = 0
        try check(status, "attach surface")
    }

    /// Notify the texture consumer only when this returns a frame ID.
    func present() throws -> UInt64? {
        let renderer = try liveRenderer()
        var id: UInt64 = 0
        let status = renderer.metal.present(renderer.handle, presented, &id)
        if status == ArtSwiftNoData || status == ArtSwiftWouldBlock { return nil }
        try check(status, "present")
        presented = id
        return id
    }

    func capture(frameID: UInt64) throws -> (width: UInt32, height: UInt32, rgba: Data) {
        let renderer = try liveRenderer()
        let state = try state()
        let (width, height) = (state.stage_width, state.stage_height)
        let (count, overflow) = (UInt64(width) * UInt64(height)).multipliedReportingOverflow(by: 4)
        guard !overflow, let length = Int(exactly: count), length > 0 else {
            throw ArtemisMacError.protocolError("Invalid Artemis stage size")
        }
        var rgba = Data(count: length)
        let status = rgba.withUnsafeMutableBytes { bytes in
            renderer.metal.capture(renderer.handle, frameID, width, height,
                                 bytes.bindMemory(to: UInt8.self).baseAddress, UInt64(bytes.count))
        }
        try check(status, "capture")
        return (width, height, rgba)
    }
}

private func check(_ status: ArtStatus, _ operation: String, root: UnsafePointer<ArtRootApiV2>? = nil) throws {
    guard status != ArtSwiftOK else { return }
    var detail = ""
    if let copy = root?.pointee.copy_last_error {
        var size: UInt64 = 0
        if copy(nil, 0, &size) == ArtSwiftBuffer, let count = Int(exactly: size), count > 0 {
            var buffer = [UInt8](repeating: 0, count: count)
            if copy(&buffer, size, &size) == ArtSwiftOK, size <= UInt64(count) {
                detail = String(decoding: buffer.prefix(Int(size)), as: UTF8.self)
            }
        }
    }
    throw ArtemisMacError.status(operation, status, detail)
}

private func withBytes<T>(_ data: Data, _ body: (ArtBytes) throws -> T) rethrows -> T {
    try data.withUnsafeBytes { bytes in
        try body(ArtBytes(data: bytes.bindMemory(to: UInt8.self).baseAddress, size: UInt64(bytes.count)))
    }
}

private func decodeEvents(_ data: Data, end: Int, count: UInt32, runtime: ArtRuntimeHandle,
                          sessionID: UUID) throws -> [ArtemisMacEvent] {
    let headerSize = 64
    return try data.withUnsafeBytes { bytes in
        var offset = 0
        var events: [ArtemisMacEvent] = []
        func uint<T: FixedWidthInteger>(_ position: Int, as type: T.Type) -> T {
            T(littleEndian: bytes.loadUnaligned(fromByteOffset: offset + position, as: type))
        }
        while offset < end {
            guard end - offset >= headerSize else {
                throw ArtemisMacError.protocolError("Truncated Artemis event")
            }
            let recordSize = Int(uint(0, as: UInt32.self))
            let metaSize = Int(uint(56, as: UInt32.self))
            let blobSize = Int(uint(60, as: UInt32.self))
            guard recordSize == headerSize + metaSize + blobSize, recordSize <= end - offset,
                  uint(4, as: UInt16.self) == 2, uint(16, as: UInt64.self) == runtime,
                  uint(48, as: UInt32.self) == UInt32(recordSize - 56) else {
                throw ArtemisMacError.protocolError("Invalid Artemis event envelope")
            }
            let metaStart = offset + headerSize
            let blobStart = metaStart + metaSize
            events.append(ArtemisMacEvent(domain: uint(6, as: UInt16.self), kind: uint(8, as: UInt32.self),
                epoch: uint(24, as: UInt64.self), sequence: uint(32, as: UInt64.self), requestID: uint(40, as: UInt64.self),
                metadata: data.subdata(in: metaStart..<blobStart), blob: data.subdata(in: blobStart..<(offset + recordSize)),
                sessionID: sessionID))
            offset += recordSize
        }
        guard events.count == Int(count) else { throw ArtemisMacError.protocolError("Invalid Artemis event count") }
        return events
    }
}
