import AVFoundation
import CoreMedia

/// Mixes buffered system and microphone PCM after capture, leaving the live video path untouched.
final class AudioMixer {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
    private let chunkFrames: AVAudioFrameCount = 4096
    private let start: CMTime
    private let frameCount: Int64
    private var rendered: Int64 = 0
    private var players: [AVAudioPlayerNode] = []
    private let sampleFormat: CMAudioFormatDescription

    init(system: [AudioPacket], microphone: [AudioPacket], start: CMTime, end: CMTime) throws {
        self.start = start
        frameCount = max(0, Int64(((end.seconds - start.seconds) * 48_000).rounded()))
        var asbd = AudioStreamBasicDescription(mSampleRate: 48_000,
                                               mFormatID: kAudioFormatLinearPCM,
                                               mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
                                               mBytesPerPacket: 8, mFramesPerPacket: 1,
                                               mBytesPerFrame: 8, mChannelsPerFrame: 2,
                                               mBitsPerChannel: 32, mReserved: 0)
        var description: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &asbd,
                                              layoutSize: 0, layout: nil, magicCookieSize: 0,
                                              magicCookie: nil, extensions: nil,
                                              formatDescriptionOut: &description) == noErr,
              let description else { throw AudioMixError.format }
        sampleFormat = description

        for packets in [system, microphone] where !packets.isEmpty {
            guard let firstDescription = CMSampleBufferGetFormatDescription(packets[0].sample) else {
                throw AudioMixError.format
            }
            let inputFormat = AVAudioFormat(cmAudioFormatDescription: firstDescription)
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: inputFormat)
            players.append(player)
            for packet in packets {
                let frames = CMSampleBufferGetNumSamples(packet.sample)
                guard frames > 0, let pcm = AVAudioPCMBuffer(pcmFormat: inputFormat,
                                                             frameCapacity: AVAudioFrameCount(frames)) else { continue }
                pcm.frameLength = AVAudioFrameCount(frames)
                let result = CMSampleBufferCopyPCMDataIntoAudioBufferList(packet.sample, at: 0,
                                                                           frameCount: Int32(frames),
                                                                           into: pcm.mutableAudioBufferList)
                guard result == noErr else { throw AudioMixError.copy(result) }
                let offset = max(0, Int64(((packet.time.seconds - start.seconds) * inputFormat.sampleRate).rounded()))
                player.scheduleBuffer(pcm, at: AVAudioTime(sampleTime: offset, atRate: inputFormat.sampleRate))
            }
        }
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: chunkFrames)
        try engine.start()
        for player in players { player.play(at: AVAudioTime(sampleTime: 0, atRate: format.sampleRate)) }
    }

    deinit { engine.stop() }

    func nextSample() throws -> CMSampleBuffer? {
        guard rendered < frameCount else { return nil }
        let frames = AVAudioFrameCount(min(Int64(chunkFrames), frameCount - rendered))
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            throw AudioMixError.format
        }
        let status = try engine.renderOffline(frames, to: pcm)
        guard status == .success, pcm.frameLength == frames,
              let channels = pcm.floatChannelData else { throw AudioMixError.render }
        let length = Int(frames) * 8
        var block: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil,
                                                  blockLength: length, blockAllocator: kCFAllocatorDefault,
                                                  customBlockSource: nil, offsetToData: 0,
                                                  dataLength: length, flags: 0,
                                                  blockBufferOut: &block) == noErr,
              let block else { throw AudioMixError.format }
        var samples = [Float](repeating: 0, count: Int(frames) * 2)
        for frame in 0..<Int(frames) {
            samples[frame * 2] = min(1, max(-1, channels[0][frame]))
            samples[frame * 2 + 1] = min(1, max(-1, channels[1][frame]))
        }
        let copy = samples.withUnsafeBytes {
            CMBlockBufferReplaceDataBytes(with: $0.baseAddress!, blockBuffer: block,
                                          offsetIntoDestination: 0, dataLength: length)
        }
        guard copy == noErr else { throw AudioMixError.copy(copy) }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                                        presentationTimeStamp: CMTimeAdd(start, CMTime(value: rendered, timescale: 48_000)),
                                        decodeTimeStamp: .invalid)
        var size = 8
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
                                        formatDescription: sampleFormat, sampleCount: Int(frames),
                                        sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                                        sampleSizeEntryCount: 1, sampleSizeArray: &size,
                                        sampleBufferOut: &sample) == noErr,
              let sample else { throw AudioMixError.format }
        rendered += Int64(frames)
        return sample
    }
}

private enum AudioMixError: LocalizedError {
    case format, copy(OSStatus), render
    var errorDescription: String? {
        switch self {
        case .format: "Could not prepare the audio mix."
        case .copy(let status): "Could not copy audio for mixing (\(status))."
        case .render: "Could not render the audio mix."
        }
    }
}
