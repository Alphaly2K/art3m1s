import Accelerate
import AVFoundation
import CoreMedia
import CoreVideo
import Darwin
import Foundation

@MainActor protocol ArtemisVideoSource: AnyObject {
    var terminalState: String? { get }
    func frame() -> CVPixelBuffer?
    func setVolume(_ volume: Float)
    func setSuspended(_ suspended: Bool)
    func close()
}

final class ArtemisLegacyMediaLibrary: @unchecked Sendable {
    private let handle: UnsafeMutableRawPointer
    let api: ArtMediaHostApiV1

    init(path: String) throws {
        typealias GetAPI = @convention(c) () -> UnsafePointer<ArtMediaHostApiV1>?
        guard let handle = dlopen(path, RTLD_NOW | RTLD_LOCAL) else {
            throw ArtemisMacError.loader("Unable to load the Artemis media Host")
        }
        guard let symbol = dlsym(handle, "art3m1s_artemis_media_get_api_v1"),
              let table = unsafeBitCast(symbol, to: GetAPI.self)(),
              table.pointee.abi_version == 1, table.pointee.size >= MemoryLayout<ArtMediaHostApiV1>.size else {
            dlclose(handle)
            throw ArtemisMacError.protocolError("Incompatible Artemis media Host ABI")
        }
        self.handle = handle
        api = table.pointee
    }

    deinit { dlclose(handle) }
}

@MainActor final class ArtemisLegacyVideoSource: ArtemisVideoSource {
    private let library: ArtemisLegacyMediaLibrary
    private let path: String
    private let loop: Bool
    private let delayMargin: Double?
    private let renderer = AVSampleBufferAudioRenderer()
    private let clock = AVSampleBufferRenderSynchronizer()
    private var reader: LegacyReader?
    private var generation = 0
    private var opening = false
    private var readingVideo = false
    private var readingAudio = false
    private var videoEnded = false
    private var audioEnded = false
    private var videoUntil = 0.0
    private var audioUntil = 0.0
    private var frames: [LegacyVideoFrame] = []
    private var hasFrame = false
    private var running = false
    private var suspended: Bool
    private(set) var terminalState: String?

    init(library: ArtemisLegacyMediaLibrary, path: String, loop: Bool, delayMarginMS: Int?,
         suspended: Bool, volume: Float) {
        self.library = library
        self.path = path
        self.loop = loop
        delayMargin = delayMarginMS.map { max(0, Double($0) / 1_000) }
        self.suspended = suspended
        renderer.volume = volume
        clock.delaysRateChangeUntilHasSufficientMediaData = false
        clock.addRenderer(renderer)
        open()
    }

    private func open() {
        let reader = LegacyReader(library: library, path: path)
        self.reader = reader
        opening = true
        let generation = generation
        Task { [weak self] in
            do {
                let hasAudio = try await reader.open()
                guard let self, self.generation == generation else { return }
                self.audioEnded = !hasAudio
                self.opening = false
            } catch {
                guard let self, self.generation == generation else { return }
                self.terminalState = "failed"
            }
        }
    }

    var playbackTime: Double { running ? max(0, clock.currentTime().seconds) : 0 }

    func frame() -> CVPixelBuffer? { nextFrame()?.buffer }

    func nextFrame() -> LegacyVideoFrame? {
        guard !suspended, !opening, terminalState == nil, let reader else { return nil }
        if renderer.status == .failed {
            terminalState = "failed"
            return nil
        }
        let now = playbackTime
        fetchVideo(reader)
        fetchAudio(reader, now: now)
        if !running {
            guard !frames.isEmpty, audioEnded || audioUntil >= 0.1 else {
                if videoEnded && frames.isEmpty { terminalState = "failed" }
                return nil
            }
            running = true
            clock.setRate(1, time: .zero)
        }
        if let first = frames.first, first.pts <= now {
            var next = frames.removeFirst()
            if let delayMargin {
                while next.pts < now - delayMargin, let ahead = frames.first, ahead.pts <= now {
                    next = frames.removeFirst()
                }
                if next.pts < now - delayMargin, frames.isEmpty, !videoEnded {
                    // After a stall, the entire decoded batch can be behind the clock.
                    fetchVideo(reader)
                    return nil
                }
            }
            videoUntil = max(videoUntil, next.pts + next.duration)
            hasFrame = true
            return next
        }
        if videoEnded && audioEnded && frames.isEmpty && now >= max(videoUntil, audioUntil) {
            if loop && hasFrame {
                retire()
                open()
            } else {
                terminalState = hasFrame ? "ended" : "failed"
            }
        }
        return nil
    }

    private func fetchVideo(_ reader: LegacyReader) {
        guard !readingVideo, !videoEnded, frames.count < 3 else { return }
        readingVideo = true
        let generation = generation
        let count = 3 - frames.count
        Task { [weak self] in
            do {
                let result = try await reader.readVideo(count: count)
                guard let self, self.generation == generation else { return }
                self.frames.append(contentsOf: result.frames)
                if let end = result.holdEnd {
                    self.videoEnded = true
                    self.videoUntil = max(self.videoUntil, end)
                }
                self.readingVideo = false
            } catch {
                guard let self, self.generation == generation else { return }
                self.terminalState = "failed"
            }
        }
    }

    private func fetchAudio(_ reader: LegacyReader, now: Double) {
        guard !readingAudio, !audioEnded, audioUntil < now + 0.2,
              renderer.isReadyForMoreMediaData else { return }
        readingAudio = true
        let generation = generation
        Task { [weak self] in
            do {
                let result = try await reader.readAudio(until: now + 0.2)
                guard let self, self.generation == generation else { return }
                for block in result.blocks {
                    self.renderer.enqueue(block.sample)
                    self.audioUntil = block.end
                }
                self.audioEnded = result.eof
                self.readingAudio = false
            } catch {
                guard let self, self.generation == generation else { return }
                self.terminalState = "failed"
            }
        }
    }

    func setVolume(_ volume: Float) { renderer.volume = volume }

    func setSuspended(_ suspended: Bool) {
        guard self.suspended != suspended else { return }
        self.suspended = suspended
        if running { clock.rate = suspended ? 0 : 1 }
    }

    private func retire() {
        generation += 1
        clock.setRate(0, time: .zero)
        renderer.flush()
        reader?.close()
        reader = nil
        frames.removeAll()
        readingVideo = false
        readingAudio = false
        videoEnded = false
        audioEnded = false
        videoUntil = 0
        audioUntil = 0
        hasFrame = false
        running = false
    }

    func close() {
        retire()
        clock.removeRenderer(renderer, at: .zero)
    }
}

struct LegacyVideoFrame: @unchecked Sendable {
    let buffer: CVPixelBuffer
    let pts: Double
    let duration: Double
}

private struct LegacyAudioBlock: @unchecked Sendable {
    let sample: CMSampleBuffer
    let end: Double
}

private final class LegacyReader: @unchecked Sendable {
    private let library: ArtemisLegacyMediaLibrary
    private let path: String
    private let queue = DispatchQueue(label: "artemis.legacy-video", qos: .userInitiated)
    private var video: OpaquePointer?
    private var audio: OpaquePointer?
    private var audioFormat: CMAudioFormatDescription?

    init(library: ArtemisLegacyMediaLibrary, path: String) {
        self.library = library
        self.path = path
    }

    func open() async throws -> Bool {
        try await onQueue {
            self.video = self.path.withCString { self.library.api.open_video($0) }
            guard self.video != nil else { throw LegacyError.decode }
            let status = self.path.withCString { self.library.api.open_audio($0, &self.audio) }
            guard status >= 0 else { throw LegacyError.decode }
            if status == 1 {
                var description = AudioStreamBasicDescription(
                    mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
                    mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                    mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
                    mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0
                )
                let result = CMAudioFormatDescriptionCreate(
                    allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0,
                    layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil,
                    formatDescriptionOut: &self.audioFormat
                )
                guard result == noErr else { throw LegacyError.decode }
            }
            return status == 1
        }
    }

    func readVideo(count: Int) async throws -> (frames: [LegacyVideoFrame], holdEnd: Double?) {
        try await onQueue {
            guard let video = self.video else { throw LegacyError.decode }
            var frames: [LegacyVideoFrame] = []
            for _ in 0..<count {
                var frame = ArtMediaFrame()
                let status = self.library.api.next_video(video, &frame)
                if status == 0 { return (frames, Double(frame.pts_us) / 1_000_000) }
                guard status == 1 else { throw LegacyError.decode }
                frames.append(LegacyVideoFrame(
                    buffer: try makePixelBuffer(frame), pts: Double(frame.pts_us) / 1_000_000,
                    duration: frame.duration_us > 0 ? Double(frame.duration_us) / 1_000_000 : 1.0 / 30
                ))
            }
            return (frames, nil)
        }
    }

    func readAudio(until limit: Double) async throws -> (blocks: [LegacyAudioBlock], eof: Bool) {
        try await onQueue {
            guard let audio = self.audio, let format = self.audioFormat else { throw LegacyError.decode }
            var blocks: [LegacyAudioBlock] = []
            for _ in 0..<16 {
                var block = ArtMediaPcm()
                let status = self.library.api.next_audio(audio, &block)
                if status == 0 { return (blocks, true) }
                guard status == 1 else { throw LegacyError.decode }
                let sample = try makeAudioBuffer(block, format: format)
                let end = sample.presentationTimeStamp.seconds + sample.duration.seconds
                blocks.append(LegacyAudioBlock(sample: sample, end: end))
                if end >= limit { break }
            }
            return (blocks, false)
        }
    }

    func close() { queue.async { self.closeHandles() } }

    private func closeHandles() {
        if let video { library.api.close_video(video) }
        if let audio { library.api.close_audio(audio) }
        video = nil
        audio = nil
    }

    deinit { closeHandles() }

    private func onQueue<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result(catching: work)) }
        }
    }
}

private enum LegacyError: Error { case decode }

private func makePixelBuffer(_ frame: ArtMediaFrame) throws -> CVPixelBuffer {
    let width = Int(frame.width), height = Int(frame.height)
    guard let rgba = frame.rgba, (1...16384).contains(width), (1...16384).contains(height),
          frame.bytes == width * height * 4, frame.bytes <= 64 * 1024 * 1024 else { throw LegacyError.decode }
    let attributes: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:], kCVPixelBufferMetalCompatibilityKey: true]
    var buffer: CVPixelBuffer?
    guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &buffer) == kCVReturnSuccess,
          let buffer, CVPixelBufferLockBaseAddress(buffer, []) == kCVReturnSuccess else { throw LegacyError.decode }
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    var source = vImage_Buffer(data: UnsafeMutableRawPointer(mutating: rgba), height: vImagePixelCount(height),
                               width: vImagePixelCount(width), rowBytes: width * 4)
    var destination = vImage_Buffer(data: CVPixelBufferGetBaseAddress(buffer), height: vImagePixelCount(height),
                                    width: vImagePixelCount(width), rowBytes: CVPixelBufferGetBytesPerRow(buffer))
    guard vImagePermuteChannels_ARGB8888(&source, &destination, [2, 1, 0, 3], vImage_Flags(kvImageNoFlags)) == kvImageNoError else {
        throw LegacyError.decode
    }
    return buffer
}

private func makeAudioBuffer(_ block: ArtMediaPcm, format: CMAudioFormatDescription) throws -> CMSampleBuffer {
    guard let pcm = block.stereo_i16, block.frames > 0, block.pts_us <= UInt64(Int64.max) else { throw LegacyError.decode }
    let bytes = Int(block.frames) * 4
    var storage: CMBlockBuffer?
    guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
        blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: bytes,
        flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &storage) == noErr, let storage,
        CMBlockBufferReplaceDataBytes(with: pcm, blockBuffer: storage, offsetIntoDestination: 0, dataLength: bytes) == noErr
    else { throw LegacyError.decode }
    var sample: CMSampleBuffer?
    let stamp = CMTime(value: Int64(block.pts_us), timescale: 1_000_000)
    guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: kCFAllocatorDefault,
        dataBuffer: storage, formatDescription: format, sampleCount: Int(block.frames), presentationTimeStamp: stamp,
        packetDescriptions: nil, sampleBufferOut: &sample) == noErr, let sample else { throw LegacyError.decode }
    return sample
}
