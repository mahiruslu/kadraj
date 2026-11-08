import AppKit
import KadrajCore

/// Draws one screen's frozen image, the dimmed surroundings, the selection or hovered window,
/// the pixel size label and the loupe.
final class SelectionOverlayView: NSView {
    private let frozen: FrozenScreen
    private let state: OverlayState
    private let showLoupe: Bool
    private unowned let controller: SelectionOverlayController

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

    override func cursorUpdate(with event: NSEvent) {
        (state.mode == .area ? NSCursor.crosshair : NSCursor.pointingHand).set()
    }
    override func mouseMoved(with event: NSEvent) { controller.mouseMoved(to: global(event)) }
    override func mouseDown(with event: NSEvent) { controller.mouseDown(at: global(event), on: frozen.screen) }
    override func mouseDragged(with event: NSEvent) { controller.mouseDragged(to: global(event)) }
    override func mouseUp(with event: NSEvent) { controller.mouseUp(at: global(event)) }
    override func keyDown(with event: NSEvent) { controller.keyDown(event) }
    override func rightMouseDown(with event: NSEvent) { controller.keyDown(escapeEvent(event)) }

    private func escapeEvent(_ e: NSEvent) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: e.locationInWindow, modifierFlags: [], timestamp: e.timestamp,
                         windowNumber: e.windowNumber, context: nil, characters: "\u{1b}",
                         charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53) ?? e
    }

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
            case .fullscreen:
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

    private func drawHint() {
        let text = (state.mode == .area
            ? "Sürükleyerek alan seçin · Space: pencere modu · Esc: iptal"
            : "Bir pencereye tıklayın · Space: alan modu · Esc: iptal") as NSString
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
