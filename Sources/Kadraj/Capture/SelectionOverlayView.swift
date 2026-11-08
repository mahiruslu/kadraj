import AppKit
import KadrajCore

/// Draws one screen's frozen image, the dimmed surroundings, the selection or hovered window,
/// the pixel size label and the loupe.
final class SelectionOverlayView: NSView {
    private let frozen: FrozenScreen
    private let state: OverlayState
    private let showLoupe: Bool
    private unowned let controller: SelectionOverlayController
    private var confirmRect: CGRect?
    private var cancelRect: CGRect?

    init(frozen: FrozenScreen, state: OverlayState, showLoupe: Bool, controller: SelectionOverlayController) {
        self.frozen = frozen
        self.state = state
        self.showLoupe = showLoupe
        self.controller = controller
        super.init(frame: NSRect(origin: .zero, size: frozen.screen.frame.size))
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect, .cursorUpdate],
                                       owner: self, userInfo: nil))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var screenOrigin: CGPoint { frozen.screen.frame.origin }
    private func toLocal(_ r: CGRect) -> CGRect { r.offsetBy(dx: -screenOrigin.x, dy: -screenOrigin.y) }
    private func global(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x + screenOrigin.x, y: p.y + screenOrigin.y)
    }

    // MARK: Events

    override func cursorUpdate(with event: NSEvent) { updateCursor(at: global(event)) }
    override func mouseMoved(with event: NSEvent) {
        controller.mouseMoved(to: global(event))
        updateCursor(at: global(event))
    }
    override func mouseDown(with event: NSEvent) {
        let local = convert(event.locationInWindow, from: nil)
        if let confirmRect, confirmRect.contains(local) { controller.confirm(); return }
        if let cancelRect, cancelRect.contains(local) { controller.cancel(); return }
        controller.mouseDown(at: global(event), on: frozen.screen, clickCount: event.clickCount)
    }

    private func updateCursor(at point: CGPoint) {
        if state.mode == .window { NSCursor.pointingHand.set(); return }
        if state.isAdjusting, let s = state.selection, s.contains(point) { NSCursor.openHand.set(); return }
        NSCursor.crosshair.set()
    }
    override func mouseDragged(with event: NSEvent) { controller.mouseDragged(to: global(event)) }
    override func mouseUp(with event: NSEvent) { controller.mouseUp(at: global(event)) }
    override func keyDown(with event: NSEvent) { controller.keyDown(event) }
    override func rightMouseDown(with event: NSEvent) { controller.cancel() }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.interpolationQuality = .high
        ctx.draw(frozen.image, in: bounds)

        let highlight: CGRect? = {
            switch state.mode {
            case .area:
                guard let s = state.selection, state.selectionScreen == frozen.screen else { return nil }
                return toLocal(s)
            case .window:
                return state.hoveredWindow.map { toLocal($0.frame) }
            case .fullscreen, .text, .qr: // the overlay mode is only ever .area or .window
                return nil
            }
        }()

        // Dim everything except the highlighted rect.
        let dim = CGMutablePath()
        dim.addRect(bounds)
        if let highlight { dim.addRect(highlight) }
        ctx.addPath(dim)
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.4).cgColor)
        ctx.fillPath(using: .evenOdd)

        if let highlight {
            if state.mode == .window {
                ctx.setFillColor(NSColor.controlAccentColor.withAlphaComponent(0.15).cgColor)
                ctx.fill(highlight)
                ctx.setStrokeColor(NSColor.controlAccentColor.cgColor)
                ctx.setLineWidth(3)
            } else {
                ctx.setStrokeColor(NSColor.white.cgColor)
                ctx.setLineWidth(1)
            }
            ctx.stroke(highlight.insetBy(dx: 0.5, dy: 0.5))
            drawSizeLabel(for: highlight)
        }
        confirmRect = nil
        cancelRect = nil
        if state.isAdjusting, let highlight, state.mode == .area { drawToolbar(below: highlight) }

        if NSMouseInRect(state.mouse, frozen.screen.frame, false) {
            if state.mode == .area, state.selection == nil || state.dragStart != nil {
                drawCrosshairGuides(at: CGPoint(x: state.mouse.x - screenOrigin.x, y: state.mouse.y - screenOrigin.y))
            }
            if showLoupe, state.mode == .area {
                Loupe.draw(in: ctx, image: frozen.image, scale: frozen.scale, viewBounds: bounds,
                           mouse: CGPoint(x: state.mouse.x - screenOrigin.x, y: state.mouse.y - screenOrigin.y))
            }
        }

        if state.selection == nil, state.mode == .area || state.hoveredWindow == nil {
            drawHint()
        }
    }

    private func drawCrosshairGuides(at p: CGPoint) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.move(to: CGPoint(x: 0, y: p.y.rounded() + 0.5)); ctx.addLine(to: CGPoint(x: bounds.maxX, y: p.y.rounded() + 0.5))
        ctx.move(to: CGPoint(x: p.x.rounded() + 0.5, y: 0)); ctx.addLine(to: CGPoint(x: p.x.rounded() + 0.5, y: bounds.maxY))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private func drawSizeLabel(for rect: CGRect) {
        let w = Int((rect.width * frozen.scale).rounded())
        let h = Int((rect.height * frozen.scale).rounded())
        let text = "\(w) × \(h)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let pad: CGFloat = 6
        var origin = CGPoint(x: rect.minX, y: rect.minY - size.height - pad * 2 - 4)
        if origin.y < 4 { origin.y = rect.minY + 4 }
        origin.x = min(max(4, origin.x), bounds.maxX - size.width - pad * 2 - 4)
        let bg = CGRect(x: origin.x, y: origin.y, width: size.width + pad * 2, height: size.height + pad)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 5, yRadius: 5).fill()
        text.draw(at: CGPoint(x: bg.minX + pad, y: bg.minY + pad / 2), withAttributes: attrs)
    }

    /// ✕ / ✓ buttons under (or inside) the selection while it waits for confirmation.
    private func drawToolbar(below rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let confirm = "✓  Yakala" as NSString, cancel = "✕" as NSString
        let cs = confirm.size(withAttributes: attrs), xs = cancel.size(withAttributes: attrs)
        let h: CGFloat = 30, pad: CGFloat = 12, gap: CGFloat = 6
        let cw = cs.width + pad * 2, xw = xs.width + pad * 2
        let total = cw + xw + gap
        var origin = CGPoint(x: rect.maxX - total, y: rect.minY - h - 34)
        if origin.y < 4 { origin.y = rect.minY + 8 }
        origin.x = min(max(4, origin.x), bounds.maxX - total - 4)
        let cancelBox = CGRect(x: origin.x, y: origin.y, width: xw, height: h)
        let confirmBox = CGRect(x: cancelBox.maxX + gap, y: origin.y, width: cw, height: h)
        NSColor.black.withAlphaComponent(0.8).setFill()
        NSBezierPath(roundedRect: cancelBox, xRadius: 7, yRadius: 7).fill()
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: confirmBox, xRadius: 7, yRadius: 7).fill()
        cancel.draw(at: CGPoint(x: cancelBox.minX + pad, y: cancelBox.midY - xs.height / 2), withAttributes: attrs)
        confirm.draw(at: CGPoint(x: confirmBox.minX + pad, y: confirmBox.midY - cs.height / 2), withAttributes: attrs)
        confirmRect = confirmBox
        cancelRect = cancelBox
    }

    private func drawHint() {
        let text: NSString
        switch (state.purpose, state.mode) {
        case (.text, .area): text = "Metni okunacak alanı seçin · Space: pencere modu · Esc: iptal"
        case (.qr, .area): text = "QR kodun bulunduğu alanı seçin · Space: pencere modu · Esc: iptal"
        case (_, .area) where state.captureOnRelease:
            text = "Sürükleyerek alan seçin · Space: pencere modu · Esc: iptal"
        case (_, .area): text = "Sürükleyerek alan seçin · Return veya çift tık: yakala · Space: pencere modu · Esc: iptal"
        default: text = "Bir pencereye tıklayın · Space: alan modu · Esc: iptal"
        }
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = text.size(withAttributes: attrs)
        let bg = CGRect(x: bounds.midX - size.width / 2 - 12, y: bounds.maxY - 90, width: size.width + 24, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.7).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 8, yRadius: 8).fill()
        text.draw(at: CGPoint(x: bg.minX + 12, y: bg.minY + 6), withAttributes: attrs)
    }
}
