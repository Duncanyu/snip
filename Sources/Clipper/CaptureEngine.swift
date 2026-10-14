import AppKit
import AVFoundation
import CoreImage
import CoreMedia
import ScreenCaptureKit
import VideoToolbox

struct VideoPacket {
    let sample: CMSampleBuffer
    let time: CMTime
    let bytes: Int
    let isKeyframe: Bool
}

struct AudioPacket {
    let sample: CMSampleBuffer
    let time: CMTime
    let bytes: Int
}

struct ClipSnapshot {
    let video: [VideoPacket]
    let audio: [AudioPacket]
    let duration: Double
    let endTime: CMTime
}

/// Holds compressed samples only. Video is trimmed at keyframes so every saved clip can decode.
final class RollingBuffer {
    private let lock = NSLock()
    private var video: [VideoPacket] = []
    private var audio: [AudioPacket] = []
    private var audioHead = 0
    private var staleAudioBytes = 0
    private var totalBytes = 0
    private let seconds: Double
    private let maxBytes: Int

    init(seconds: Int, maxBytes: Int) {
        self.seconds = Double(seconds)
        self.maxBytes = maxBytes
    }

    func addVideo(_ sample: CMSampleBuffer) {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [NSDictionary]
        let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        let packet = VideoPacket(sample: sample, time: CMSampleBufferGetPresentationTimeStamp(sample),
                                 bytes: CMSampleBufferGetTotalSampleSize(sample), isKeyframe: !notSync)
        lock.lock()
        video.append(packet)
        totalBytes += packet.bytes
        trim()
        lock.unlock()
    }

    func addAudio(_ sample: CMSampleBuffer) -> Bool {
        // ScreenCaptureKit reuses audio buffers. Retaining its CMSampleBuffer stalls capture
        // after the small framework pool fills, so copy the PCM bytes before buffering.
        guard let source = CMSampleBufferGetDataBuffer(sample),
              let format = CMSampleBufferGetFormatDescription(sample) else { return false }
        let length = CMBlockBufferGetDataLength(source)
        var data: CMBlockBuffer?
        guard CMBlockBufferCreateContiguous(allocator: kCFAllocatorDefault, sourceBuffer: source,
                                            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                                            offsetToData: 0, dataLength: length,
                                            flags: UInt32(kCMBlockBufferAlwaysCopyDataFlag),
                                            blockBufferOut: &data) == noErr,
              let data else { return false }
        var timing = CMSampleTimingInfo()
        guard CMSampleBufferGetSampleTimingInfo(sample, at: 0, timingInfoOut: &timing) == noErr else { return false }
        var owned: CMSampleBuffer?
        let bytesPerSample = length / max(1, CMSampleBufferGetNumSamples(sample))
        let isPlanar = CMAudioFormatDescriptionGetStreamBasicDescription(format).map {
            $0.pointee.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        } ?? false
        var sampleSizes = isPlanar ? [] : [bytesPerSample]
        let result = sampleSizes.withUnsafeMutableBufferPointer { sizes in
            CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: data,
                                      formatDescription: format,
                                      sampleCount: CMSampleBufferGetNumSamples(sample),
                                      sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                      sampleSizeEntryCount: sizes.count, sampleSizeArray: sizes.baseAddress,
                                      sampleBufferOut: &owned)
        }
        guard result == noErr,
              let owned else { return false }
        let packet = AudioPacket(sample: owned, time: CMSampleBufferGetPresentationTimeStamp(owned), bytes: length)
        lock.lock()
        audio.append(packet)
        totalBytes += packet.bytes
        trim()
        lock.unlock()
        return true
    }

    private func trim() {
        if let newestAudio = audio.last {
            discardAudio(olderThan: newestAudio.time.seconds - seconds)
        }
        if let newestVideo = video.last {
            let cutoff = newestVideo.time.seconds - seconds
            // Retain the last keyframe at or before the requested start time.
            if let keep = video.indices.last(where: { video[$0].isKeyframe && video[$0].time.seconds <= cutoff }), keep > 0 {
                discardVideo(keep)
            }
        }
        // If the byte budget is tighter than the time budget, evict complete GOPs.
        while totalBytes > maxBytes, let nextKeyframe = video.dropFirst().firstIndex(where: \.isKeyframe) {
            discardVideo(nextKeyframe)
        }
        if let firstTime = video.first?.time.seconds {
            discardAudio(olderThan: firstTime)
        }
        while totalBytes > maxBytes, audioHead < audio.count {
            discardOldestAudio()
        }
        if totalBytes > maxBytes {
            totalBytes -= video.reduce(0) { $0 + $1.bytes }
            video.removeAll()
        }
        // Audio arrives much more often than video. Move the head instead of
        // copying the entire packet array for every expired audio callback.
        if audioHead > 0 && (audioHead * 2 >= audio.count || staleAudioBytes >= 8 * 1_048_576) {
            audio.removeFirst(audioHead)
            audioHead = 0
            staleAudioBytes = 0
        }
    }

    private func discardAudio(olderThan cutoff: Double) {
        while audioHead < audio.count && audio[audioHead].time.seconds < cutoff {
            discardOldestAudio()
        }
    }

    private func discardOldestAudio() {
        let bytes = audio[audioHead].bytes
        totalBytes -= bytes
        staleAudioBytes += bytes
        audioHead += 1
    }

    private func discardVideo(_ count: Int) {
        totalBytes -= video.prefix(count).reduce(0) { $0 + $1.bytes }
        video.removeFirst(count)
    }

    func snapshot(seconds: Int) throws -> ClipSnapshot {
        lock.lock()
        defer { lock.unlock() }
        guard let last = video.last, !video.isEmpty else {
            throw CaptureError.noFrames
        }
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        let wanted = now.seconds - Double(seconds)
        if last.time.seconds < wanted {
            guard let keyframe = video.last(where: \.isKeyframe) else { throw CaptureError.noFrames }
            let startTime = CMTimeSubtract(now, CMTime(seconds: Double(seconds), preferredTimescale: 600))
            var timing = CMSampleTimingInfo(duration: CMTimeSubtract(now, startTime),
                                            presentationTimeStamp: startTime, decodeTimeStamp: .invalid)
            var held: CMSampleBuffer?
            let result = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                                                sampleBuffer: keyframe.sample,
                                                                sampleTimingEntryCount: 1,
                                                                sampleTimingArray: &timing,
                                                                sampleBufferOut: &held)
            guard result == noErr, let held else { throw CaptureError.writer("Could not hold the last frame") }
            let still = VideoPacket(sample: held, time: startTime, bytes: keyframe.bytes, isKeyframe: true)
            let recentAudio = audio[audioHead...].filter { $0.time.seconds >= wanted && $0.time.seconds <= now.seconds }
            return ClipSnapshot(video: [still], audio: recentAudio, duration: Double(seconds), endTime: now)
        }
        let start = video.indices.last(where: { video[$0].isKeyframe && video[$0].time.seconds <= wanted })
            ?? video.firstIndex(where: \.isKeyframe)
        guard let start else { throw CaptureError.noFrames }
        var selected = Array(video[start...])
        let firstTime = selected[0].time.seconds
        // ScreenCaptureKit stops delivering image buffers while a display is unchanged.
        // Extend the last compressed sample so a quiet scene still reaches the hotkey time.
        var timing = CMSampleTimingInfo(duration: CMTimeSubtract(now, last.time),
                                        presentationTimeStamp: last.time, decodeTimeStamp: .invalid)
        var heldSample: CMSampleBuffer?
        if timing.duration.isValid, timing.duration.seconds > 0,
           CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault,
                                                  sampleBuffer: last.sample,
                                                  sampleTimingEntryCount: 1,
                                                  sampleTimingArray: &timing,
                                                  sampleBufferOut: &heldSample) == noErr,
           let heldSample {
            selected[selected.count - 1] = VideoPacket(sample: heldSample, time: last.time,
                                                       bytes: last.bytes, isKeyframe: last.isKeyframe)
        }
        let audioSamples = audio[audioHead...].filter { $0.time.seconds >= firstTime && $0.time.seconds <= now.seconds }
        return ClipSnapshot(video: selected, audio: audioSamples, duration: now.seconds - firstTime, endTime: now)
    }
}

private enum CaptureError: LocalizedError {
    case noFrames
    case hardwareEncoder(OSStatus)
    case encoderProperty(OSStatus)
    case writer(String)
    case permission
    case noDisplay
    case audioCopy
    case pixelTransfer(OSStatus)
    case colorBuffer(CVReturn)
    case noSelectedApps(String)
    case selectedAppsNotRunning(String)

    var errorDescription: String? {
        switch self {
        case .noFrames: "No complete frames are buffered yet."
        case .hardwareEncoder(let code): "Hardware video encoder unavailable (\(code)). Try a lower resolution or frame rate."
        case .encoderProperty(let code): "Could not configure the video encoder (\(code))."
        case .writer(let detail): "Could not save the clip: \(detail)"
        case .permission: "Allow Screen Recording in System Settings, then restart this app."
        case .noDisplay: "No display is available for capture."
        case .audioCopy: "Could not copy a system audio sample."
        case .pixelTransfer(let code): "Could not resize a captured frame (\(code))."
        case .colorBuffer(let code): "Could not prepare a color-edited frame (\(code))."
        case .noSelectedApps(let kind): "Choose at least one app for \(kind), or select All apps."
        case .selectedAppsNotRunning(let kind): "Open a window in a selected \(kind) app, then start capture."
        }
    }
}

private final class CapturePipeline: NSObject, SCStreamOutput, SCStreamDelegate {
    let buffer: RollingBuffer
    let targetBitrate: Int
    private var encoder: VTCompressionSession?
    private var transfer: VTPixelTransferSession?
    private var transferPool: CVPixelBufferPool?
    private var transferAllocation: CFDictionary?
    private let colorContext: CIContext?
    private let colorValues: (brightness: Double, contrast: Double, saturation: Double)?
    private var colorPool: CVPixelBufferPool?
    private var colorAllocation: CFDictionary?
    private let onFirstFrame: (Int, Int, Int) -> Void
    private let onFailure: (Error) -> Void
    private let failureLock = NSLock()
    private var failureReported = false
    private var loggedFirstFrame = false

    init(width: Int, height: Int, fps: Int, duration: Int, memoryLimitMB: Int,
         bitrateMbps: Int, resizeFromFullResolution: Bool, colorSettings: CaptureSettings,
         onFirstFrame: @escaping (Int, Int, Int) -> Void,
         onFailure: @escaping (Error) -> Void) throws {
        buffer = RollingBuffer(seconds: duration, maxBytes: memoryLimitMB * 1_048_576)
        let pixelsPerSecond = Double(width) * Double(height) * Double(fps)
        let automaticBitrate = min(200_000_000, max(8_000_000, Int(pixelsPerSecond * 0.11)))
        targetBitrate = bitrateMbps > 0 ? min(bitrateMbps, 200) * 1_000_000 : automaticBitrate
        self.onFirstFrame = onFirstFrame
        self.onFailure = onFailure
        colorContext = colorSettings.hasColorEdit ? CIContext(options: [.useSoftwareRenderer: false]) : nil
        colorValues = colorSettings.hasColorEdit
            ? (colorSettings.brightness, colorSettings.contrast, colorSettings.saturation) : nil
        super.init()

        if resizeFromFullResolution {
            var transferSession: VTPixelTransferSession?
            let result = VTPixelTransferSessionCreate(allocator: kCFAllocatorDefault,
                                                      pixelTransferSessionOut: &transferSession)
            guard result == noErr, let transferSession else { throw CaptureError.pixelTransfer(result) }
            transfer = transferSession
            let scaling = [kVTPixelTransferPropertyKey_ScalingMode as String: kVTScalingMode_Letterbox] as CFDictionary
            let scalingResult = VTSessionSetProperties(transferSession, propertyDictionary: scaling)
            guard scalingResult == noErr else { throw CaptureError.pixelTransfer(scalingResult) }

            let frameBytes = width * height * 3 / 2
            let poolLimit = max(2, min(6, 256 * 1_048_576 / max(frameBytes, 1)))
            transferAllocation = [kCVPixelBufferPoolAllocationThresholdKey as String: poolLimit] as CFDictionary
            let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: poolLimit] as CFDictionary
            let imageAttributes: [String: Any] = [
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            var pool: CVPixelBufferPool?
            let poolResult = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes,
                                                     imageAttributes as CFDictionary, &pool)
            guard poolResult == kCVReturnSuccess, let pool else { throw CaptureError.pixelTransfer(poolResult) }
            transferPool = pool
        }

        if colorContext != nil {
            let frameBytes = width * height * 4
            let poolLimit = max(2, min(3, 192 * 1_048_576 / max(frameBytes, 1)))
            colorAllocation = [kCVPixelBufferPoolAllocationThresholdKey as String: poolLimit] as CFDictionary
            let poolAttributes = [kCVPixelBufferPoolMinimumBufferCountKey as String: poolLimit] as CFDictionary
            let imageAttributes: [String: Any] = [
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferIOSurfacePropertiesKey as String: [:]
            ]
            var pool: CVPixelBufferPool?
            let result = CVPixelBufferPoolCreate(kCFAllocatorDefault, poolAttributes,
                                                 imageAttributes as CFDictionary, &pool)
            guard result == kCVReturnSuccess, let pool else { throw CaptureError.colorBuffer(result) }
            colorPool = pool
        }

        let encoderOptions = [
            kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true,
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
        ] as CFDictionary
        var session: VTCompressionSession?
        let code = VTCompressionSessionCreate(allocator: kCFAllocatorDefault,
                                              width: Int32(width), height: Int32(height),
                                              codecType: kCMVideoCodecType_HEVC,
                                              encoderSpecification: encoderOptions,
                                              imageBufferAttributes: nil,
                                              compressedDataAllocator: nil,
                                              outputCallback: { refcon, _, status, _, sample in
            guard status == noErr, let refcon, let sample else { return }
            Unmanaged<CapturePipeline>.fromOpaque(refcon).takeUnretainedValue().buffer.addVideo(sample)
        }, refcon: Unmanaged.passUnretained(self).toOpaque(), compressionSessionOut: &session)
        guard code == noErr, let session else { throw CaptureError.hardwareEncoder(code) }
        encoder = session

        // A one-second closed GOP bounds both clip start error and buffer eviction size.
        let properties: [(CFString, CFTypeRef)] = [
            (kVTCompressionPropertyKey_RealTime, kCFBooleanTrue),
            (kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse),
            (kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 1.0 as CFNumber),
            (kVTCompressionPropertyKey_ExpectedFrameRate, fps as CFNumber),
            (kVTCompressionPropertyKey_AverageBitRate, targetBitrate as CFNumber)
        ]
        for (key, value) in properties {
            let result = VTSessionSetProperty(session, key: key, value: value)
            guard result == noErr else { throw CaptureError.encoderProperty(result) }
        }
        let prepared = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepared == noErr else { throw CaptureError.encoderProperty(prepared) }
    }

    deinit {
        if let encoder { VTCompressionSessionInvalidate(encoder) }
        if let transfer { VTPixelTransferSessionInvalidate(transfer) }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard CMSampleBufferIsValid(sampleBuffer) else { return }
        switch type {
        case .screen:
            guard let image = CMSampleBufferGetImageBuffer(sampleBuffer), let encoder else { return }
            if !loggedFirstFrame {
                loggedFirstFrame = true
                NSLog("Capture source frames: %d × %d pixels at %.3f", CVPixelBufferGetWidth(image), CVPixelBufferGetHeight(image), CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds)
                onFirstFrame(CVPixelBufferGetWidth(image), CVPixelBufferGetHeight(image), targetBitrate)
            }
            var frame = image
            if let transfer, let transferPool, let transferAllocation {
                var resized: CVPixelBuffer?
                let allocation = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault,
                                                                                      transferPool, transferAllocation, &resized)
                if allocation == kCVReturnWouldExceedAllocationThreshold { return }
                guard allocation == kCVReturnSuccess, let resized else {
                    reportFailure(CaptureError.pixelTransfer(allocation))
                    return
                }
                let result = VTPixelTransferSessionTransferImage(transfer, from: image, to: resized)
                guard result == noErr else {
                    reportFailure(CaptureError.pixelTransfer(result))
                    return
                }
                frame = resized
            }
            if let colorContext, let colorValues, let colorPool, let colorAllocation {
                var output: CVPixelBuffer?
                let allocation = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
                    kCFAllocatorDefault, colorPool, colorAllocation, &output)
                if allocation == kCVReturnWouldExceedAllocationThreshold { return }
                guard allocation == kCVReturnSuccess, let output else {
                    reportFailure(CaptureError.colorBuffer(allocation))
                    return
                }
                let edited = CIImage(cvPixelBuffer: frame).applyingFilter("CIColorControls", parameters: [
                    "inputBrightness": colorValues.brightness,
                    "inputContrast": colorValues.contrast,
                    "inputSaturation": colorValues.saturation
                ])
                colorContext.render(edited, to: output)
                frame = output
            }
            let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            var flags = VTEncodeInfoFlags()
            let result = VTCompressionSessionEncodeFrame(encoder, imageBuffer: frame,
                                                         presentationTimeStamp: time,
                                                         duration: CMSampleBufferGetDuration(sampleBuffer),
                                                         frameProperties: nil, sourceFrameRefcon: nil,
                                                         infoFlagsOut: &flags)
            if result != noErr { reportFailure(CaptureError.hardwareEncoder(result)) }
        case .audio:
            if !buffer.addAudio(sampleBuffer) { reportFailure(CaptureError.audioCopy) }
        default:
            break
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        reportFailure(error)
    }

    private func reportFailure(_ error: Error) {
        failureLock.lock()
        let shouldReport = !failureReported
        failureReported = true
        failureLock.unlock()
        if shouldReport { onFailure(error) }
    }

    func finish() {
        guard let encoder else { return }
        VTCompressionSessionCompleteFrames(encoder, untilPresentationTimeStamp: .invalid)
        VTCompressionSessionInvalidate(encoder)
        self.encoder = nil
    }
}

@MainActor
final class CaptureEngine: ObservableObject {
    static let shared = CaptureEngine()

    @Published private(set) var isRunning = false
    @Published private(set) var status = "Ready" {
        didSet { NSLog("Capture status: %@", status) }
    }
    @Published private(set) var captureDetails = ""
    @Published private(set) var availableDisplays: [SCDisplay] = []
    @Published private(set) var availableApplications: [SCRunningApplication] = []
    private(set) var activeSettings: CaptureSettings?

    private var stream: SCStream?
    private var audioStream: SCStream?
    private var pipeline: CapturePipeline?
    private var startTask: Task<Void, Never>?
    private var isSaving = false
    private lazy var clipSound = Bundle.main.url(forResource: "clip", withExtension: "wav")
        .flatMap { NSSound(contentsOf: $0, byReference: false) }
    private let videoQueue = DispatchQueue(label: "capture.video", qos: .userInitiated)
    private let audioQueue = DispatchQueue(label: "capture.audio", qos: .userInitiated)

    func refreshDisplays() async {
        do {
            let content = try await SCShareableContent.current
            availableDisplays = content.displays
            availableApplications = content.applications
        } catch {
            status = error.localizedDescription
        }
    }

    func refreshSourceFilters() async {
        guard let settings = activeSettings, let stream,
              settings.videoAppMode != .all || (settings.includeAudio && settings.audioAppMode != .all) else { return }
        do {
            let content = try await SCShareableContent.current
            availableApplications = content.applications
            guard let display = content.displays.first(where: { $0.displayID == settings.displayID })
                    ?? content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else { return }
            if settings.videoAppMode != .all,
               let filter = try? appFilter(display: display, mode: settings.videoAppMode,
                                           ids: settings.videoAppIDs, applications: content.applications,
                                           kind: "video") {
                try await stream.updateContentFilter(filter)
            }
            if settings.includeAudio && settings.audioAppMode != .all {
                let filter = try? appFilter(display: display, mode: settings.audioAppMode,
                                            ids: settings.audioAppIDs, applications: content.applications,
                                            kind: "audio")
                if let filter {
                    if let audioStream { try await audioStream.updateContentFilter(filter) }
                    else if settings.audioAppMode == settings.videoAppMode,
                            settings.audioAppIDs == settings.videoAppIDs {
                        try await stream.updateContentFilter(filter)
                    }
                }
            }
        } catch {
            status = error.localizedDescription
        }
    }

    func start(settings: CaptureSettings) async {
        guard !isRunning else { return }
        if let startTask { await startTask.value; return }
        let task = Task { await performStart(settings: settings) }
        startTask = task
        await task.value
        startTask = nil
    }

    private func performStart(settings: CaptureSettings) async {
        do {
            guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
                status = "Screen Recording permission required"
                throw CaptureError.permission
            }
            let content = try await SCShareableContent.current
            availableDisplays = content.displays
            availableApplications = content.applications
            guard let display = content.displays.first(where: { $0.displayID == settings.displayID })
                    ?? content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                    ?? content.displays.first else { throw CaptureError.noDisplay }
            let displayFPS = NSScreen.screens.first {
                ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == display.displayID
            }?.maximumFramesPerSecond ?? 0
            let effectiveFPS = displayFPS > 0 ? min(settings.fps, displayFPS) : settings.fps
            let filter = try appFilter(display: display, mode: settings.videoAppMode,
                                       ids: settings.videoAppIDs, applications: content.applications,
                                       kind: "video")
            let sharedAudioFilter = settings.audioAppMode == settings.videoAppMode &&
                settings.audioAppIDs == settings.videoAppIDs
            let scale = Double(filter.pointPixelScale)
            let points = filter.contentRect.size
            let nativeWidth = max(2, Int((points.width * scale).rounded()) & ~1)
            let nativeHeight = max(2, Int((points.height * scale).rounded()) & ~1)
            let factor: Double = switch settings.resolution {
                case .half: 0.5
                case .normal: 1
                case .retina: scale
                case .custom: scale
            }
            let width = settings.resolution == .custom
                ? min(8192, max(320, settings.customWidth)) & ~1
                : max(2, Int((points.width * factor).rounded()) & ~1)
            let height = settings.resolution == .custom
                ? min(8192, max(180, settings.customHeight)) & ~1
                : max(2, Int((points.height * factor).rounded()) & ~1)
            let resizeFromFullResolution = settings.resolution == .custom
                && (width != nativeWidth || height != nativeHeight)

            let configuration = SCStreamConfiguration()
            configuration.width = settings.resolution == .custom ? nativeWidth : width
            configuration.height = settings.resolution == .custom ? nativeHeight : height
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(effectiveFPS))
            configuration.queueDepth = 3
            configuration.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            configuration.showsCursor = true
            configuration.capturesAudio = settings.includeAudio && sharedAudioFilter
            configuration.excludesCurrentProcessAudio = settings.excludeAppAudio
            configuration.sampleRate = 48_000
            configuration.channelCount = 2

            let pipeline = try CapturePipeline(width: width, height: height, fps: effectiveFPS,
                                               duration: max(1, min(settings.clipDuration, 3600)),
                                               memoryLimitMB: max(64, min(settings.memoryLimitMB, 8192)),
                                               bitrateMbps: max(0, min(settings.bitrateMbps, 200)),
                                               resizeFromFullResolution: resizeFromFullResolution,
                                               colorSettings: settings,
                                               onFirstFrame: { [weak self] sourceWidth, sourceHeight, targetBitrate in
                Task { @MainActor [weak self] in
                    self?.captureDetails = "\(width) × \(height) output from \(sourceWidth) × \(sourceHeight) source, up to \(effectiveFPS) fps, HEVC \(targetBitrate / 1_000_000) Mb/s target"
                }
            }) { [weak self] error in
                Task { @MainActor [weak self] in
                    await self?.stop()
                    self?.status = error.localizedDescription
                }
            }
            let stream = SCStream(filter: filter, configuration: configuration, delegate: pipeline)
            try stream.addStreamOutput(pipeline, type: .screen, sampleHandlerQueue: videoQueue)
            if settings.includeAudio && sharedAudioFilter {
                try stream.addStreamOutput(pipeline, type: .audio, sampleHandlerQueue: audioQueue)
            }
            var separateAudioStream: SCStream?
            if settings.includeAudio && !sharedAudioFilter {
                let audioFilter = try appFilter(display: display, mode: settings.audioAppMode,
                                                ids: settings.audioAppIDs, applications: content.applications,
                                                kind: "audio")
                let audioConfiguration = SCStreamConfiguration()
                audioConfiguration.capturesAudio = true
                audioConfiguration.excludesCurrentProcessAudio = settings.excludeAppAudio
                audioConfiguration.sampleRate = 48_000
                audioConfiguration.channelCount = 2
                audioConfiguration.width = 2
                audioConfiguration.height = 2
                audioConfiguration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                audioConfiguration.queueDepth = 1
                let separate = SCStream(filter: audioFilter, configuration: audioConfiguration, delegate: pipeline)
                try separate.addStreamOutput(pipeline, type: .audio, sampleHandlerQueue: audioQueue)
                separateAudioStream = separate
            }
            captureDetails = "Starting \(width) × \(height) output, up to \(effectiveFPS) fps, HEVC \(pipeline.targetBitrate / 1_000_000) Mb/s target"
            try await stream.startCapture()
            do {
                try await separateAudioStream?.startCapture()
            } catch {
                try? await stream.stopCapture()
                throw error
            }
            self.pipeline = pipeline
            self.stream = stream
            self.audioStream = separateAudioStream
            activeSettings = settings
            isRunning = true
            status = "Recording"
        } catch {
            captureDetails = ""
            status = error.localizedDescription
        }
    }

    func stop() async {
        if let startTask { await startTask.value }
        guard let stream, let pipeline else { return }
        if let audioStream { try? await audioStream.stopCapture() }
        do { try await stream.stopCapture() } catch { status = error.localizedDescription }
        pipeline.finish()
        self.stream = nil
        self.audioStream = nil
        self.pipeline = nil
        activeSettings = nil
        captureDetails = ""
        isRunning = false
        status = "Stopped"
    }

    private func appFilter(display: SCDisplay, mode: AppSourceMode, ids: [String],
                           applications: [SCRunningApplication], kind: String) throws -> SCContentFilter {
        let selected = applications.filter { ids.contains($0.bundleIdentifier) }
        switch mode {
        case .all:
            return SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        case .only:
            guard !ids.isEmpty else { throw CaptureError.noSelectedApps(kind) }
            guard !selected.isEmpty else { throw CaptureError.selectedAppsNotRunning(kind) }
            return SCContentFilter(display: display, including: selected, exceptingWindows: [])
        case .exclude:
            return SCContentFilter(display: display, excludingApplications: selected, exceptingWindows: [])
        }
    }

    func saveClip(seconds: Int) async {
        guard let pipeline else { status = "Start recording first"; return }
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let snapshot = try pipeline.buffer.snapshot(seconds: max(1, min(seconds, 3600)))
            let clipName = CaptureSettingsStore.shared.settings.clipName
            let clipDirectoryPath = CaptureSettingsStore.shared.settings.clipDirectoryPath
            let playSoundOnSave = CaptureSettingsStore.shared.settings.playSoundOnSave
            status = "Saving clip…"
            let url = try await Task.detached(priority: .utility) {
                try await ClipExporter.export(snapshot, name: clipName, directoryPath: clipDirectoryPath)
            }.value
            status = "Saved \(Int(snapshot.duration.rounded()))s to \(url.path)"
            if playSoundOnSave {
                clipSound?.stop()
                clipSound?.play()
            }
        } catch {
            status = error.localizedDescription
        }
    }
}

private enum ClipExporter {
    static func export(_ clip: ClipSnapshot, name: String, directoryPath: String) async throws -> URL {
        let folder = URL(fileURLWithPath: directoryPath, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH-mm-ss"
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_"))
        let prefix = String(name.unicodeScalars.filter { allowed.contains($0) }.prefix(60))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let safeName = prefix.isEmpty ? "Clip" : prefix
        let url = folder.appendingPathComponent("\(safeName) \(formatter.string(from: Date())) \(UUID().uuidString.prefix(6)).mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        var completed = false
        defer {
            if !completed {
                if writer.status == .writing { writer.cancelWriting() }
                try? FileManager.default.removeItem(at: url)
            }
        }
        writer.shouldOptimizeForNetworkUse = false
        guard let videoFormat = CMSampleBufferGetFormatDescription(clip.video[0].sample) else {
            throw CaptureError.writer("Missing video format")
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        videoInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if !clip.audio.isEmpty {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ])
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }
        guard writer.startWriting() else {
            throw CaptureError.writer(writer.error?.localizedDescription ?? "Writer did not start")
        }
        writer.startSession(atSourceTime: clip.video[0].time)

        var videoIndex = 0
        var audioIndex = 0
        var videoFinished = false
        var audioFinished = audioInput == nil
        while videoIndex < clip.video.count || audioIndex < clip.audio.count {
            if writer.status == .failed {
                throw CaptureError.writer(writer.error?.localizedDescription ?? "Writer failed")
            }
            var appended = false
            if videoIndex < clip.video.count && videoInput.isReadyForMoreMediaData {
                guard videoInput.append(clip.video[videoIndex].sample) else {
                    throw CaptureError.writer(writer.error?.localizedDescription ?? "Could not append video")
                }
                videoIndex += 1
                appended = true
            }
            if let audioInput, audioIndex < clip.audio.count, audioInput.isReadyForMoreMediaData {
                guard audioInput.append(clip.audio[audioIndex].sample) else {
                    throw CaptureError.writer(writer.error?.localizedDescription ?? "Could not append audio")
                }
                audioIndex += 1
                appended = true
            }
            if !videoFinished && videoIndex == clip.video.count {
                videoInput.markAsFinished()
                videoFinished = true
            }
            if !audioFinished && audioIndex == clip.audio.count {
                audioInput?.markAsFinished()
                audioFinished = true
            }
            if !appended { try await Task.sleep(for: .milliseconds(2)) }
        }
        writer.endSession(atSourceTime: clip.endTime)
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw CaptureError.writer(writer.error?.localizedDescription ?? "Unknown writer failure")
        }
        completed = true
        return url
    }
}
