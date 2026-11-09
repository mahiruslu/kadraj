import AppKit
import KadrajCore
import ScreenCaptureKit

@MainActor
enum WindowCapturer {
    /// On-screen windows of other apps, ordered front to back, with frames in AppKit coordinates.
    static func candidates() async throws -> (list: [WindowCandidate], byID: [CGWindowID: SCWindow]) {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let pid = getpid()
        var byID: [CGWindowID: SCWindow] = [:]
        for w in content.windows where w.owningApplication?.processID != pid && w.isOnScreen {
            byID[w.windowID] = w
        }
        // SCShareableContent has no z-order; CGWindowList is ordered front to back.
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var list: [WindowCandidate] = []
        for entry in info {
            guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                  let window = byID[number.uint32Value],
                  (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue } // skip invisible windows
            list.append(WindowCandidate(
                id: window.windowID,
                frame: ScreenCoordinates.appKitRect(fromCG: window.frame, primaryScreenHeight: primaryHeight),
                layer: window.windowLayer,
                ownerName: window.owningApplication?.applicationName ?? ""))
        }
        return (list, byID)
    }

    /// Captures a single window at native resolution, independent of what covers it.
    static func capture(_ window: SCWindow, includeShadow: Bool) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.ignoreShadowsSingleWindow = !includeShadow
        config.showsCursor = false
        config.captureResolution = .best
        config.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        config.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }
}
