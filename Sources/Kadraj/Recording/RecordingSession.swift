import AppKit
import AVFoundation
import KadrajCore
import ScreenCaptureKit

/// Which sound goes into a recording, each as its own AAC track.
struct RecordingAudio: Sendable {
    var system = false
    /// macOS 15+ only (ScreenCaptureKit's microphone capture).
    var microphone = false
}

/// Records a screen region to H.264 MP4, optionally with system audio and the microphone.
final class RecordingSession: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    enum RecordingError: LocalizedError {
        case noFrames
        var errorDescription: String? { String(localized: "The recording is too short; no frames were captured.") }
    }

    // Accessed only on `queue`.
    private let queue = DispatchQueue(label: "app.kadraj.recording")
    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let systemAudioInput: AVAssetWriterInput?
    private let microphoneInput: AVAssetWriterInput?
    private var started = false
    private var sessionStart = CMTime.invalid
    private var stopped = false
    private var frames = 0
    private var failureReported = false
    private var stream: SCStream?
    let url: URL
    /// Called if the stream stops by itself; the controller then finalizes the file.
    var onStreamStopped: @Sendable () -> Void = {}

    private static func audioInput(channels: Int, bitRate: Int) -> AVAssetWriterInput {
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitRate,
        ])
        input.expectsMediaDataInRealTime = true
        return input
    }

    private init(url: URL, width: Int, height: Int, audio: RecordingAudio) throws {
        self.url = url
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                // ~3 bits per pixel, capped at 24 Mbps (screen content compresses well).
                AVVideoAverageBitRateKey: min(max(width * height * 3, 2_000_000), 24_000_000),
                AVVideoExpectedSourceFrameRateKey: 30,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        // Two live sources, two tracks; stop() mixes them into one afterwards.
        systemAudioInput = audio.system ? Self.audioInput(channels: 2, bitRate: 160_000) : nil
        microphoneInput = audio.microphone ? Self.audioInput(channels: 1, bitRate: 96_000) : nil
        for track in [systemAudioInput, microphoneInput].compactMap({ $0 }) { writer.add(track) }
        super.init()
    }

    @MainActor
    static func start(region: CGRect, screen: NSScreen, url: URL, audio: RecordingAudio,
                      includingWindow overlayID: CGWindowID? = nil,
                      onStreamStopped: @escaping @Sendable () -> Void) async throws -> RecordingSession {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let id = screen.displayID, let display = content.displays.first(where: { $0.displayID == id }) else {
            throw CaptureError.noScreens
        }
        let ownApps = content.applications.filter { $0.processID == getpid() }
        let size = RecordingGeometry.evenPixelSize(region.size, scale: screen.backingScaleFactor)
        let session = try RecordingSession(url: url, width: size.width, height: size.height, audio: audio)
        session.onStreamStopped = onStreamStopped // set before the stream can report anything
        guard session.writer.startWriting() else { throw session.writer.error ?? CocoaError(.fileWriteUnknown) }

        let config = SCStreamConfiguration()
        // sourceRect matches the even pixel size exactly, so frames aren't resampled.
        config.sourceRect = CGRect(x: region.minX - screen.frame.minX, y: screen.frame.maxY - region.maxY,
                                   width: CGFloat(size.width) / screen.backingScaleFactor,
                                   height: CGFloat(size.height) / screen.backingScaleFactor)
        config.width = size.width
        config.height = size.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        config.showsCursor = true
        config.queueDepth = 6
        config.pixelFormat = kCVPixelFormatType_32BGRA
        if audio.system {
            config.capturesAudio = true
            config.sampleRate = 48_000
            config.channelCount = 2
            config.excludesCurrentProcessAudio = true // no Kadraj sounds in the recording
        }
        if audio.microphone, #available(macOS 15.0, *) {
            config.captureMicrophone = true
        }
        // Kadraj's windows stay out of the video, except the click/shortcut overlay.
        let overlay = content.windows.filter { $0.windowID == overlayID }
        if overlayID != nil, overlay.isEmpty { NSLog("Kadraj: recording overlay not found; recording without it") }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: overlay)
        let stream = SCStream(filter: filter, configuration: config, delegate: session)
        do {
            try stream.addStreamOutput(session, type: .screen, sampleHandlerQueue: session.queue)
            if audio.system {
                try stream.addStreamOutput(session, type: .audio, sampleHandlerQueue: session.queue)
            }
            if audio.microphone, #available(macOS 15.0, *) {
                try stream.addStreamOutput(session, type: .microphone, sampleHandlerQueue: session.queue)
            }
            try await stream.startCapture()
        } catch {
            session.writer.cancelWriting() // startWriting already created an empty file
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        session.stream = stream
        return session
    }

    /// Stops and finalizes the file; deletes it and throws if nothing was recorded.
    @MainActor
    /// `endTime` is the host-clock moment the user pressed stop.
    func stop(endTime: CMTime) async throws -> URL {
        try? await stream?.stopCapture()
        stream = nil
        let frameCount: Int = await withCheckedContinuation { continuation in
            queue.async {
                self.stopped = true
                continuation.resume(returning: self.frames)
            }
        }
        if writer.status == .failed {
            let error = writer.error ?? CocoaError(.fileWriteUnknown)
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw error // e.g. disk full: report the real cause
        }
        guard frameCount > 0 else {
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: url)
            throw RecordingError.noFrames
        }
        input.markAsFinished()
        systemAudioInput?.markAsFinished()
        microphoneInput?.markAsFinished()
        // ScreenCaptureKit only delivers frames when something changes: extend the video to the
        // moment the user pressed stop, holding the last frame (sample times use the host clock).
        writer.endSession(atSourceTime: endTime)
        await writer.finishWriting()
        if let error = writer.error { throw error }
        if systemAudioInput != nil, microphoneInput != nil {
            // One mixed track plays everywhere; if mixing fails the two-track file is still fine.
            do { try await AudioMixdown.mixAudioTracks(at: url) } catch {
                NSLog("Kadraj: audio mixdown failed, keeping separate tracks: \(error.localizedDescription)")
            }
        }
        return url
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("Kadraj: recording stream stopped: \(error.localizedDescription)")
        onStreamStopped()
    }

    // MARK: SCStreamOutput (on `queue`)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !stopped, sampleBuffer.isValid else { return }
        if type == .screen {
            appendVideo(sampleBuffer)
        } else if type == .audio {
            appendAudio(sampleBuffer, to: systemAudioInput)
        } else if #available(macOS 15.0, *), type == .microphone {
            appendAudio(sampleBuffer, to: microphoneInput)
        }
    }

    /// Sound is kept from the first video frame on: the file's timeline starts there.
    private func appendAudio(_ sampleBuffer: CMSampleBuffer, to input: AVAssetWriterInput?) {
        guard started, writer.status == .writing, let input, input.isReadyForMoreMediaData,
              sampleBuffer.presentationTimeStamp >= sessionStart else { return }
        input.append(sampleBuffer)
    }

    private func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard Self.isComplete(sampleBuffer) else { return }
        if writer.status == .failed {
            // Stop once; stop() then reports writer.error instead of recording silently nothing.
            if !failureReported { failureReported = true; onStreamStopped() }
            return
        }
        if !started {
            sessionStart = sampleBuffer.presentationTimeStamp
            writer.startSession(atSourceTime: sessionStart)
            started = true
        }
        if input.isReadyForMoreMediaData, input.append(sampleBuffer) { frames += 1 }
    }

    private static func isComplete(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}

enum GIFExporter {
    /// 15 fps, at most 640 px wide and 450 frames, saved next to the video.
    static func export(_ video: URL) async throws -> URL {
        let asset = AVURLAsset(url: video)
        let duration = try await asset.load(.duration).seconds
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 640)
        let tolerance = CMTime(value: 1, timescale: 30)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        let timing = GIFTiming.frameTimes(duration: duration, fps: 15, maxFrames: 450)
        let url = FileNamer.uniqueURL(directory: video.deletingLastPathComponent(),
                                      fileName: video.deletingPathExtension().appendingPathExtension("gif").lastPathComponent) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        // Frames go straight into the file instead of being collected in memory first.
        guard let writer = GIFWriter(url: url, frameCount: timing.times.count, delay: timing.delay) else {
            throw CocoaError(.fileWriteUnknown)
        }
        for time in timing.times {
            let (image, _) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 600))
            autoreleasepool { writer.add(image) }
        }
        guard writer.finish() else { throw CocoaError(.fileWriteUnknown) }
        return url
    }
}
