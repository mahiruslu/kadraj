import AppKit
import ScreenCaptureKit

/// A full-resolution snapshot of one screen, taken before any overlay is shown.
struct FrozenScreen {
    let screen: NSScreen
    let image: CGImage
    var scale: CGFloat { screen.backingScaleFactor }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}

enum ScreenFreezer {
    /// Captures every screen at native resolution, excluding Kadraj's own windows
    /// (e.g. Quick Access thumbnails still on screen).
    @MainActor
    static func freezeAll() async throws -> [FrozenScreen] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let ownApps = content.applications.filter { $0.processID == getpid() }
        var frozen: [FrozenScreen] = []
        for screen in NSScreen.screens {
            guard let id = screen.displayID,
                  let display = content.displays.first(where: { $0.displayID == id }) else { continue }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(screen.frame.width * screen.backingScaleFactor)
            config.height = Int(screen.frame.height * screen.backingScaleFactor)
            config.showsCursor = false
            config.captureResolution = .best
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            frozen.append(FrozenScreen(screen: screen, image: image))
        }
        return frozen
    }
}
