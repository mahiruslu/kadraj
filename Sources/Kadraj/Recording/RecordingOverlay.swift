import AppKit
import ApplicationServices
import KadrajCore
import QuartzCore

/// A transparent, click-through window over the recorded region that draws a ring where the
/// mouse is clicked and a badge with the keyboard shortcut just pressed. Kadraj's own windows
/// are left out of recordings, so the stream lists this one as an exception (`windowID`).
@MainActor
final class RecordingOverlay {
    private let panel: NSPanel
    private let canvas = NSView()
    private let badge = NSTextField(labelWithString: "")
    private let badgeBox = NSView()
    private var monitors: [Any] = []
    private var badgeHide: DispatchWorkItem?
    private let region: CGRect

    var windowID: CGWindowID { CGWindowID(panel.windowNumber) }

    /// `keys` needs Accessibility access; without it only clicks are shown.
    init(region: CGRect, clicks: Bool, keys: Bool) {
        self.region = region
        panel = NSPanel(contentRect: region, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false

        canvas.frame = CGRect(origin: .zero, size: region.size)
        canvas.wantsLayer = true
        panel.contentView = canvas

        badge.font = .systemFont(ofSize: 22, weight: .semibold)
        badge.textColor = .white
        badgeBox.wantsLayer = true
        badgeBox.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        badgeBox.layer?.cornerRadius = 12
        badgeBox.addSubview(badge)
        badgeBox.alphaValue = 0
        canvas.addSubview(badgeBox)

        if clicks {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
                let point = NSEvent.mouseLocation
                MainActor.assumeIsolated { self?.ring(at: point) }
            }) { monitors.append(monitor) }
        }
        if keys {
            if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
                let code = UInt32(event.keyCode), flags = event.modifierFlags
                MainActor.assumeIsolated { self?.key(code, flags) }
            }) { monitors.append(monitor) }
        }
        panel.orderFrontRegardless()
    }

    /// Accessibility access, needed to see key presses in other apps. Asks macOS to prompt once.
    static func canShowKeys(prompt: Bool) -> Bool {
        // The value of kAXTrustedCheckOptionPrompt (a mutable C global Swift 6 won't read).
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func close() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        panel.orderOut(nil)
    }

    private func ring(at global: CGPoint) {
        guard region.contains(global), let layer = canvas.layer else { return }
        let p = CGPoint(x: global.x - region.minX, y: global.y - region.minY)
        let size: CGFloat = 44
        let ring = CAShapeLayer()
        ring.frame = CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size)
        ring.path = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: size, height: size), transform: nil)
        ring.fillColor = NSColor.systemYellow.withAlphaComponent(0.35).cgColor
        ring.strokeColor = NSColor.systemYellow.cgColor
        ring.lineWidth = 3
        ring.opacity = 0
        layer.addSublayer(ring)

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.4
        scale.toValue = 1.25
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.95
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = 0.5
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        ring.add(group, forKey: "ring")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { ring.removeFromSuperlayer() }
    }

    private func key(_ code: UInt32, _ flags: NSEvent.ModifierFlags) {
        var modifiers: Hotkey.Modifiers = []
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        guard let label = KeystrokeDisplay.label(keyCode: code, modifiers: modifiers) else { return }

        badge.stringValue = label
        badge.sizeToFit()
        let pad = CGSize(width: 18, height: 10)
        let size = CGSize(width: badge.frame.width + pad.width * 2, height: badge.frame.height + pad.height * 2)
        badgeBox.frame = CGRect(x: (region.width - size.width) / 2, y: 28, width: size.width, height: size.height)
        badge.frame.origin = CGPoint(x: pad.width, y: pad.height)
        badgeBox.alphaValue = 1

        badgeHide?.cancel()
        let hide = DispatchWorkItem { [weak self] in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                self?.badgeBox.animator().alphaValue = 0
            }
        }
        badgeHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: hide)
    }
}
