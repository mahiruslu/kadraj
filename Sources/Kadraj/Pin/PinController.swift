import AppKit
import KadrajCore
import UniformTypeIdentifiers

/// Keeps track of images pinned to the screen.
@MainActor
final class PinController {
    private var pins: [PinPanel] = []
    var onEdit: (CGImage) -> Void = { _ in }
    var onCopyText: (CGImage) -> Void = { _ in }

    var hasPins: Bool { !pins.isEmpty }
    var hasClickThroughPins: Bool { pins.contains { $0.ignoresMouseEvents } }

    /// Pins `image` at its natural on-screen size, centered on the screen under the pointer
    /// (cascaded so several pins don't stack exactly).
    func pin(_ image: CGImage) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let panel = PinPanel(image: image, scale: screen.backingScaleFactor, controller: self)
        var frame = panel.frame
        let area = screen.visibleFrame
        // Large captures start smaller so the pin doesn't cover the screen.
        let fit = min(1, area.width * 0.5 / frame.width, area.height * 0.5 / frame.height)
        if fit < 1 { panel.zoom(by: fit, around: CGPoint(x: frame.midX, y: frame.midY)); frame = panel.frame }
        let offset = CGFloat(pins.count % 8) * 24
        frame.origin = CGPoint(x: area.midX - frame.width / 2 + offset, y: area.midY - frame.height / 2 - offset)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        pins.append(panel)
    }

    func close(_ panel: PinPanel) {
        panel.orderOut(nil)
        pins.removeAll { $0 === panel }
    }

    func closeAll() {
        pins.forEach { $0.orderOut(nil) }
        pins.removeAll()
    }

    func makeAllInteractive() {
        pins.forEach { $0.ignoresMouseEvents = false }
    }
}

final class PinPanel: NSPanel {
    let image: CGImage
    let naturalSize: CGSize
    private(set) var zoomScale: CGFloat = 1
    private weak var controller: PinController?

    @MainActor
    init(image: CGImage, scale: CGFloat, controller: PinController) {
        self.image = image
        self.controller = controller
        naturalSize = CGSize(width: max(CGFloat(image.width) / scale, PinGeometry.minSide),
                             height: max(CGFloat(image.height) / scale, PinGeometry.minSide))
        super.init(contentRect: CGRect(origin: .zero, size: naturalSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        contentView = PinView(panel: self)
    }

    override var canBecomeKey: Bool { true }

    func zoom(by factor: CGFloat, around anchor: CGPoint) {
        let result = PinGeometry.zoomed(frame: frame, naturalSize: naturalSize, currentScale: zoomScale,
                                        factor: factor, anchor: anchor)
        zoomScale = result.scale
        setFrame(result.frame, display: true)
    }

    @MainActor func closePin() { controller?.close(self) }
    @MainActor func edit() { controller?.onEdit(image); closePin() }
    @MainActor func copyText() { controller?.onCopyText(image) }
}

/// Draws the pinned image; handles drag, zoom, double-click / Esc to close and the context menu.
final class PinView: NSView {
    private unowned let panel: PinPanel

    init(panel: PinPanel) {
        self.panel = panel
        super.init(frame: CGRect(origin: .zero, size: panel.frame.size))
        autoresizingMask = [.width, .height]
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .high
        ctx.draw(panel.image, in: bounds)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        if event.clickCount == 2 { panel.closePin(); return }
        window?.performDrag(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { panel.closePin() } else { super.keyDown(with: event) }
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
        guard delta != 0 else { return }
        // One event never zooms more than 25%, whatever the device reports.
        panel.zoom(by: min(max(1 + delta, 0.8), 1.25), around: NSEvent.mouseLocation)
    }

    override func magnify(with event: NSEvent) {
        panel.zoom(by: 1 + event.magnification, around: NSEvent.mouseLocation)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let opacity = NSMenuItem(title: "Opaklık", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for value in [100, 75, 50, 25] {
            let item = NSMenuItem(title: "%\(value)", action: #selector(setOpacity(_:)), keyEquivalent: "")
            item.target = self
            item.tag = value
            item.state = Int((panel.alphaValue * 100).rounded()) == value ? .on : .off
            sub.addItem(item)
        }
        opacity.submenu = sub
        menu.addItem(opacity)
        menu.addItem(item("Tıklamaları Geçir", #selector(clickThrough)))
        menu.addItem(.separator())
        menu.addItem(item("Kopyala", #selector(copyImage)))
        menu.addItem(item("Kaydet…", #selector(saveImage)))
        menu.addItem(item("Düzenle", #selector(editImage)))
        menu.addItem(item("Metni Kopyala", #selector(copyText)))
        menu.addItem(.separator())
        menu.addItem(item("Kapat", #selector(closePin)))
        return menu
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func setOpacity(_ sender: NSMenuItem) { panel.alphaValue = CGFloat(sender.tag) / 100 }
    @objc private func clickThrough() { panel.ignoresMouseEvents = true }
    @objc private func copyImage() { CaptureOutput.copyToClipboard(panel.image) }
    @objc private func editImage() { panel.edit() }
    @objc private func copyText() { panel.copyText() }
    @objc private func closePin() { panel.closePin() }

    @objc private func saveImage() {
        let save = NSSavePanel()
        save.allowedContentTypes = [.png]
        save.nameFieldStringValue = "Kadraj Pin.png"
        NSApp.activate()
        if save.runModal() == .OK, let url = save.url,
           let data = ImageEncoder.data(for: panel.image, format: .png) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
