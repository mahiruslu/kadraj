import AppKit
import CoreMedia
import KadrajCore
import ScreenCaptureKit
import VideoToolbox

/// Streams a screen region while the user scrolls it and stitches the frames.
final class ScrollSession: NSObject, SCStreamOutput, @unchecked Sendable {
    // Accessed only on `queue`.
    private let stitcher = ScrollStitcher()
    private var busy = false
    private var finished = false
    private let queue = DispatchQueue(label: "app.kadraj.scroll")
    private var stream: SCStream?
    private let onUpdate: @Sendable (ScrollStitcher.AddResult, Int) -> Void

    private init(onUpdate: @escaping @Sendable (ScrollStitcher.AddResult, Int) -> Void) {
        self.onUpdate = onUpdate
    }

    /// Shows the frame + HUD, streams `region` (global AppKit coordinates on `screen`) and returns
    /// the stitched image when the user presses Done (nil on cancel).
    @MainActor
    static func run(region: CGRect, screen: NSScreen) async throws -> CGImage? {
        let hud = ScrollHUD(region: region, screen: screen)
        let session = ScrollSession { result, height in
            Task { @MainActor in hud.update(result: result, height: height) }
        }
        try await session.start(region: region, screen: screen)
        let done = await hud.waitForDecision()
        let image = await session.stop(keep: done)
        hud.close()
        return image
    }

    @MainActor
    private func start(region: CGRect, screen: NSScreen) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let id = screen.displayID, let display = content.displays.first(where: { $0.displayID == id }) else {
            throw CaptureError.noScreens
        }
        let ownApps = content.applications.filter { $0.processID == getpid() }
        let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
        let scale = screen.backingScaleFactor
        let config = SCStreamConfiguration()
        // sourceRect is in points, relative to the display, top-left origin.
        config.sourceRect = CGRect(x: region.minX - screen.frame.minX, y: screen.frame.maxY - region.maxY,
                                   width: region.width, height: region.height)
        config.width = Int(region.width * scale)
        config.height = Int(region.height * scale)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 15)
        config.showsCursor = false
        config.queueDepth = 4
        config.pixelFormat = kCVPixelFormatType_32BGRA
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    @MainActor
    private func stop(keep: Bool) async -> CGImage? {
        try? await stream?.stopCapture()
        stream = nil
        guard keep else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async {
                self.finished = true
                continuation.resume(returning: self.stitcher.image())
            }
        }
    }

    // MARK: SCStreamOutput (on `queue`)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, !finished, !busy, Self.isComplete(sampleBuffer),
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(pixelBuffer, options: nil, imageOut: &image)
        guard let image else { return }
        busy = true
        let result = stitcher.add(image)
        busy = false
        if result == .limitReached { finished = true }
        onUpdate(result, stitcher.height)
    }

    /// Only frames with new content (idle/blank frames are skipped).
    private static func isComplete(_ buffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }
}
