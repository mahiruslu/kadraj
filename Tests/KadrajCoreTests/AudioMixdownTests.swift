import AVFoundation
import Foundation
import Testing
@testable import KadrajCore

/// One second of tone: 0.1 s chunks so audio and video stay interleaved while writing.
private func pcm(frames: Int, start: Int, frequency: Double) throws -> CMSampleBuffer {
    var asbd = AudioStreamBasicDescription(
        mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
        mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
        mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0)
    var format: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0,
                                   magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
    let bytes = frames * 4
    var block: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: bytes, blockAllocator: nil,
                                       customBlockSource: nil, offsetToData: 0, dataLength: bytes,
                                       flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block)
    var samples = (0..<frames).map { Float(sin(2 * .pi * frequency * Double(start + $0) / 48_000) * 0.5) }
    CMBlockBufferReplaceDataBytes(with: &samples, blockBuffer: try #require(block), offsetIntoDestination: 0, dataLength: bytes)
    var buffer: CMSampleBuffer?
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(
        allocator: nil, dataBuffer: try #require(block), formatDescription: try #require(format), sampleCount: frames,
        presentationTimeStamp: CMTime(value: Int64(start), timescale: 48_000), packetDescriptions: nil, sampleBufferOut: &buffer)
    return try #require(buffer)
}

private func waitUntilReady(_ input: AVAssetWriterInput) async throws {
    for _ in 0..<400 where !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
}

/// A 1 s, 64×64 H.264 video with `audioTracks` mono AAC tracks (440 Hz, 880 Hz, …).
private func makeRecording(at url: URL, audioTracks: Int) async throws {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 64, AVVideoHeightKey: 64,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: 64, kCVPixelBufferHeightKey as String: 64,
    ])
    writer.add(video)
    let audios = (0..<audioTracks).map { _ in
        AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 64_000,
        ])
    }
    audios.forEach(writer.add)
    #expect(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    for step in 0..<10 {
        try await waitUntilReady(video)
        var pixels: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &pixels)
        adaptor.append(try #require(pixels), withPresentationTime: CMTime(value: Int64(step), timescale: 10))
        for (index, input) in audios.enumerated() {
            try await waitUntilReady(input)
            input.append(try pcm(frames: 4_800, start: step * 4_800, frequency: 440 * Double(index + 1)))
        }
    }
    video.markAsFinished()
    audios.forEach { $0.markAsFinished() }
    writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
    await writer.finishWriting()
    #expect(writer.status == .completed, "\(String(describing: writer.error))")
}

private func temporaryURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("kadraj-mixdown-\(UUID().uuidString).mp4")
}

@Test func twoAudioTracksBecomeOneAndTheVideoStays() async throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try await makeRecording(at: url, audioTracks: 2)
    #expect(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).count == 2)

    try await AudioMixdown.mixAudioTracks(at: url)

    let asset = AVURLAsset(url: url)
    #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
    #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
    #expect(abs(try await asset.load(.duration).seconds - 1) < 0.1)
}

@Test func singleAudioTrackIsLeftAlone() async throws {
    let url = temporaryURL()
    defer { try? FileManager.default.removeItem(at: url) }
    try await makeRecording(at: url, audioTracks: 1)
    let before = try Data(contentsOf: url)

    try await AudioMixdown.mixAudioTracks(at: url)

    #expect(try Data(contentsOf: url) == before)
}
