import AVFoundation
import CoreMedia
import XCTest
@testable import Clipper

final class RollingBufferTests: XCTestCase {
    func testKeyframeTimeByteTrimmingAndQuietScreenSnapshot() throws {
        let now = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        let frames: [(Double, Bool)] = [(5, true), (4, false), (3, true),
                                        (2, false), (1, true), (0, false)]

        let timeLimited = RollingBuffer(seconds: 2, maxBytes: 10_000)
        for (ago, keyframe) in frames {
            timeLimited.addVideo(try sample(at: now - ago, keyframe: keyframe))
        }
        let timed = try timeLimited.snapshot(seconds: 2)
        XCTAssertEqual(timed.video.count, 4)
        XCTAssertTrue(timed.video[0].isKeyframe)
        XCTAssertEqual(timed.video[0].time.seconds, now - 3, accuracy: 0.01)

        let byteLimited = RollingBuffer(seconds: 30, maxBytes: 250)
        for (ago, keyframe) in frames {
            byteLimited.addVideo(try sample(at: now - ago, keyframe: keyframe))
        }
        let capped = try byteLimited.snapshot(seconds: 2)
        XCTAssertEqual(capped.video.count, 2)
        XCTAssertTrue(capped.video[0].isKeyframe)
        XCTAssertLessThanOrEqual(capped.video.reduce(0) { $0 + $1.bytes }, 250)

        let oversized = RollingBuffer(seconds: 30, maxBytes: 50)
        oversized.addVideo(try sample(at: now, keyframe: true, bytes: 100))
        XCTAssertThrowsError(try oversized.snapshot(seconds: 2))
        oversized.addVideo(try sample(at: now, keyframe: true, bytes: 30))
        XCTAssertEqual(try oversized.snapshot(seconds: 2).video.count, 1)

        let quiet = RollingBuffer(seconds: 30, maxBytes: 350)
        quiet.addVideo(try sample(at: now - 10, keyframe: true))
        var newestAudio: CMSampleBuffer?
        for ago in [5.0, 2.0, 1.0, 0.0] {
            let audio = try pcmSample(at: now - ago)
            XCTAssertTrue(quiet.addAudio(audio))
            if ago == 0 { newestAudio = audio }
        }
        let sourceBlock = try XCTUnwrap(CMSampleBufferGetDataBuffer(try XCTUnwrap(newestAudio)))
        XCTAssertEqual(CMBlockBufferFillDataBytes(with: 0x7F, blockBuffer: sourceBlock,
                                                   offsetIntoDestination: 0, dataLength: 100), noErr)
        let held = try quiet.snapshot(seconds: 3)
        XCTAssertEqual(held.video.count, 1)
        XCTAssertEqual(held.duration, 3, accuracy: 0.01)
        XCTAssertEqual(CMSampleBufferGetDuration(held.video[0].sample).seconds, 3, accuracy: 0.01)
        XCTAssertEqual(held.audio.count, 2)
        XCTAssertTrue(held.audio.allSatisfy { $0.time.seconds >= held.endTime.seconds - 3 })
        let copiedBlock = try XCTUnwrap(CMSampleBufferGetDataBuffer(try XCTUnwrap(held.audio.last).sample))
        var copiedBytes = [UInt8](repeating: 0, count: 100)
        let copyStatus = copiedBytes.withUnsafeMutableBytes {
            CMBlockBufferCopyDataBytes(copiedBlock, atOffset: 0, dataLength: 100,
                                       destination: $0.baseAddress!)
        }
        XCTAssertEqual(copyStatus, noErr)
        XCTAssertTrue(copiedBytes.allSatisfy { $0 == 0x2A })
        XCTAssertLessThanOrEqual(held.video.reduce(0) { $0 + $1.bytes } +
                                 held.audio.reduce(0) { $0 + $1.bytes }, 350)
    }

    func testExistingSettingsKeepTheirValues() throws {
        let oldJSON = Data(#"{"clipDuration":15,"fps":60,"resolution":"retina","memoryLimitMB":1024,"includeAudio":true,"showInDock":false}"#.utf8)
        let settings = try JSONDecoder().decode(CaptureSettings.self, from: oldJSON)
        XCTAssertEqual(settings.clipDuration, 15)
        XCTAssertFalse(settings.showInDock)
        XCTAssertEqual(settings.bitrateMbps, 0)
        XCTAssertTrue(settings.excludeAppAudio)
        XCTAssertEqual(settings.hotkeyLabel, "⌘⇧9")
        XCTAssertEqual(settings.pauseHotkeyLabel, "⌘⌥P")
        var edited = settings
        edited.clipName = "Gameplay"
        edited.playSoundOnSave = true
        XCTAssertFalse(edited.needsCaptureRestart(comparedTo: settings))
        edited.bitrateMbps = 50
        XCTAssertTrue(edited.needsCaptureRestart(comparedTo: settings))
        edited = settings
        edited.excludeAppAudio = false
        XCTAssertFalse(try JSONDecoder().decode(CaptureSettings.self,
                                               from: JSONEncoder().encode(edited)).excludeAppAudio)
        XCTAssertTrue(edited.needsCaptureRestart(comparedTo: settings))
        edited.bitrateMbps = 500
        XCTAssertEqual(edited.normalized().bitrateMbps, 200)
        edited.bitrateMbps = -1
        XCTAssertEqual(edited.normalized().bitrateMbps, 0)
    }

    private func sample(at seconds: Double, keyframe: Bool, bytes: Int = 100) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                        memoryBlock: nil, blockLength: bytes, blockAllocator: kCFAllocatorDefault,
                        customBlockSource: nil, offsetToData: 0, dataLength: bytes,
                        flags: 0, blockBufferOut: &block), noErr)
        var format: CMVideoFormatDescription?
        XCTAssertEqual(CMVideoFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                        codecType: kCMVideoCodecType_HEVC, width: 16, height: 16,
                        extensions: nil, formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60),
                                        presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600),
                                        decodeTimeStamp: .invalid)
        var size = bytes
        var result: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block,
                        formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 1,
                        sampleTimingArray: &timing, sampleSizeEntryCount: 1,
                        sampleSizeArray: &size, sampleBufferOut: &result), noErr)
        let sample = try XCTUnwrap(result)
        if !keyframe {
            let attachments = try XCTUnwrap(CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true)
                as? [NSMutableDictionary])
            attachments[0][kCMSampleAttachmentKey_NotSync] = true
        }
        return sample
    }

    private func pcmSample(at seconds: Double, bytes: Int = 100) throws -> CMSampleBuffer {
        var block: CMBlockBuffer?
        XCTAssertEqual(CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                        memoryBlock: nil, blockLength: bytes, blockAllocator: kCFAllocatorDefault,
                        customBlockSource: nil, offsetToData: 0, dataLength: bytes,
                        flags: 0, blockBufferOut: &block), noErr)
        let data = try XCTUnwrap(block)
        XCTAssertEqual(CMBlockBufferFillDataBytes(with: 0x2A, blockBuffer: data,
                                                   offsetIntoDestination: 0, dataLength: bytes), noErr)
        var asbd = AudioStreamBasicDescription(mSampleRate: 48_000,
                    mFormatID: kAudioFormatLinearPCM,
                    mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
                    mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2,
                    mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0)
        var format: CMAudioFormatDescription?
        XCTAssertEqual(CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault,
                        asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                        magicCookie: nil, extensions: nil, formatDescriptionOut: &format), noErr)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48_000),
                                        presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 600),
                                        decodeTimeStamp: .invalid)
        var size = 2
        var result: CMSampleBuffer?
        XCTAssertEqual(CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: data,
                        formatDescription: format, sampleCount: bytes / 2, sampleTimingEntryCount: 1,
                        sampleTimingArray: &timing, sampleSizeEntryCount: 1,
                        sampleSizeArray: &size, sampleBufferOut: &result), noErr)
        return try XCTUnwrap(result)
    }
}
