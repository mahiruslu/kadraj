import AVFoundation
import Foundation

/// Recordings with both system sound and the microphone are written as two AAC tracks while
/// recording (two live sources, each with its own timing). Many players and browsers play only
/// the first audio track, so afterwards the file is rewritten with one mixed track; the video
/// samples are copied as they are, not re-encoded.
public enum AudioMixdown {
    /// Rewrites `url` in place when it has more than one audio track. On any failure the
    /// original file is left untouched.
    public static func mixAudioTracks(at url: URL) async throws {
        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard audioTracks.count > 1, let video = try await asset.loadTracks(withMediaType: .video).first else { return }
        let duration = try await asset.load(.duration)
        let videoFormat = try await video.load(.formatDescriptions).first

        let reader = try AVAssetReader(asset: asset)
        let videoOut = AVAssetReaderTrackOutput(track: video, outputSettings: nil) // passthrough
        videoOut.alwaysCopiesSampleData = false
        let audioOut = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false,
        ])
        reader.add(videoOut)
        reader.add(audioOut)

        let temp = url.deletingLastPathComponent().appendingPathComponent(".kadraj-mix-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: temp) }
        let writer = try AVAssetWriter(outputURL: temp, fileType: .mp4)
        let videoIn = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: videoFormat)
        let audioIn = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ])
        writer.add(videoIn)
        writer.add(audioIn)

        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        let pumps = [Pump(output: videoOut, input: videoIn, label: "video"),
                     Pump(output: audioOut, input: audioIn, label: "audio")]
        await withTaskGroup(of: Void.self) { group in
            for pump in pumps { group.addTask { await pump.run() } }
        }
        if reader.status == .failed {
            writer.cancelWriting()
            throw reader.error ?? CocoaError(.fileReadUnknown)
        }
        // Keep the original length: the recorder holds the last frame until the moment of stop.
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temp)
    }
}

/// Moves every sample of one reader output into one writer input.
private final class Pump: @unchecked Sendable {
    private let output: AVAssetReaderOutput
    private let input: AVAssetWriterInput
    private let label: String

    init(output: AVAssetReaderOutput, input: AVAssetWriterInput, label: String) {
        self.output = output
        self.input = input
        self.label = label
    }

    func run() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            var finished = false
            input.requestMediaDataWhenReady(on: DispatchQueue(label: "app.kadraj.mixdown.\(label)")) { [self] in
                while !finished, input.isReadyForMoreMediaData {
                    if let buffer = output.copyNextSampleBuffer(), input.append(buffer) { continue }
                    finished = true
                    input.markAsFinished()
                    done.resume()
                }
            }
        }
    }
}
