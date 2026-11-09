import AppKit
import KadrajCore

/// What to do with an image edited directly in the overlay.
enum OverlayAction: Sendable {
    case done, copy, save, pin, ocr, qr, editor
}

enum OverlayResult {
    /// Area selection annotated in place, plus the chosen action.
    case edited(CGImage, OverlayAction)
    case image(CGImage)
    case window(WindowCandidate)
    /// The selected rect itself (global AppKit coordinates), for scroll capture.
    case region(CGRect, CGDirectDisplayID)
    case cancelled
}

/// Shared state for all per-screen overlay views.
@MainActor
final class OverlayState {
    var mode: CaptureMode
    /// What the selection is for (area/window capture, text, QR).
    let purpose: CaptureMode
    let captureOnRelease: Bool
    /// Selection in global AppKit coordinates, limited to `selectionScreen`.
    var selection: CGRect?
    var selectionScreen: NSScreen?
    /// Set while the user drags out a new selection.
    var dragStart: CGPoint?
    /// Set while the user moves an existing selection.
    var moveAnchor: CGPoint?
    var moveOrigin: CGRect?
    var mouse: CGPoint = NSEvent.mouseLocation
    var hoveredWindow: WindowCandidate?

    /// The selection is being annotated in place (toolbar under it).
    var editing = false

    init(mode: CaptureMode, captureOnRelease: Bool) {
        self.mode = mode == .window ? .window : .area
        self.purpose = mode
        // Reading text or a QR code is a quick lookup: no confirm step.
        self.captureOnRelease = mode == .ruler ? false : (captureOnRelease || [.text, .qr, .scroll, .record].contains(mode))
    }

    /// A finished selection waiting for confirmation (iShot style).
    var isAdjusting: Bool { selection != nil && dragStart == nil && !captureOnRelease && !editing }
}

/// Shows a frozen-screen overlay on every display and lets the user pick an area or a window.
@MainActor
final class SelectionOverlayController {
    private let frozen: [FrozenScreen]
    private let settings: CaptureSettings
    private let windows: [WindowCandidate]
    let state: OverlayState
    private var panels: [OverlayPanel] = []
    private var completion: ((OverlayResult) -> Void)?
    private var editModel: EditorModel?

    init(frozen: [FrozenScreen], mode: CaptureMode, settings: CaptureSettings, windows: [WindowCandidate]) {
        self.frozen = frozen
        self.settings = settings
        self.windows = windows
        self.state = OverlayState(mode: mode, captureOnRelease: settings.captureOnRelease)
    }

    func run(completion: @escaping (OverlayResult) -> Void) {
        self.completion = completion
        for item in frozen {
            let panel = OverlayPanel(screen: item.screen)
            let view = SelectionOverlayView(frozen: item, state: state, showLoupe: settings.showLoupe, controller: self)
            panel.contentView = view
            panel.initialFirstResponder = view
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        updateHover()
        let keyPanel = panels.first { NSMouseInRect(state.mouse, $0.frame, false) } ?? panels.first
        keyPanel?.makeKey()
        // Without an explicit first responder, Esc/Space before the first click would only beep.
        if let keyPanel, let view = keyPanel.contentView { keyPanel.makeFirstResponder(view) }
        NSCursor.crosshair.set()
        redraw()
    }

    // MARK: Events from views

    func mouseMoved(to point: CGPoint) {
        let previous = state.mouse
        let hovered = state.hoveredWindow
        state.mouse = point
        updateHover()
        // Only the screens the pointer left/entered (or whose highlight changed) need repainting.
        redraw(around: [previous, point], all: hovered != state.hoveredWindow)
    }

    func mouseDown(at point: CGPoint, on screen: NSScreen, clickCount: Int) {
        state.mouse = point
        guard !state.editing else { return }
        guard state.mode == .area else { return }
        if state.isAdjusting, let selection = state.selection, selection.contains(point) {
            if clickCount >= 2 { confirm(); return }
            state.moveAnchor = point
            state.moveOrigin = selection
            return
        }
        state.dragStart = point
        state.selectionScreen = screen
        state.selection = nil
        redraw()
    }

    func mouseDragged(to point: CGPoint) {
        state.mouse = point
        guard !state.editing else { return }
        guard state.mode == .area, let screen = state.selectionScreen else { return }
        if let anchor = state.moveAnchor, let origin = state.moveOrigin {
            state.selection = SelectionGeometry.nudge(origin, dx: point.x - anchor.x, dy: point.y - anchor.y,
                                                      resize: false, within: screen.frame)
        } else if let start = state.dragStart {
            let clamped = CGPoint(x: min(max(point.x, screen.frame.minX), screen.frame.maxX),
                                  y: min(max(point.y, screen.frame.minY), screen.frame.maxY))
            state.selection = SelectionGeometry.normalizedRect(from: start, to: clamped)
        }
        redraw()
    }

    func mouseUp(at point: CGPoint) {
        state.mouse = point
        guard !state.editing else { return }
        switch state.mode {
        case .area:
            if state.moveAnchor != nil {
                state.moveAnchor = nil
                state.moveOrigin = nil
                redraw()
                return
            }
            guard state.dragStart != nil else { return }
            state.dragStart = nil
            if let selection = state.selection, SelectionGeometry.isUsableSelection(selection) {
                if state.captureOnRelease { finishArea() }
                else if state.purpose == .area { beginEditing() } // annotate right away (iShot style)
                else { redraw() }
            } else if state.purpose == .record, let screen = state.selectionScreen {
                // A click without dragging records the whole screen.
                finish(.region(screen.frame, screen.displayID ?? 0))
            } else {
                state.selection = nil
                redraw()
            }
        case .window:
            if let window = state.hoveredWindow { finish(.window(window)) }
        default:
            break
        }
    }

    func keyDown(_ event: NSEvent) {
        if state.editing {
            switch event.keyCode {
            case 53: cancel()
            case 36, 76: perform(.done)
            default: break
            }
            return
        }
        switch event.keyCode {
        case 53: cancel() // Esc
        case 36, 76: confirm() // Return, Enter
        case 49 where state.purpose == .scroll: // window mode would repeat static sidebars in every chunk
            NSSound.beep()
        case 49: // Space toggles area / window
            state.mode = state.mode == .area ? .window : .area
            state.selection = nil
            state.dragStart = nil
            updateHover()
            (state.mode == .area ? NSCursor.crosshair : NSCursor.pointingHand).set()
            redraw()
        case 123, 124, 125, 126:
            nudge(event)
        default:
            break
        }
    }

    func confirm() {
        if state.mode == .area, state.selection != nil { finishArea() }
        else if state.mode == .window, let window = state.hoveredWindow { finish(.window(window)) }
    }

    func cancel() { finish(.cancelled) }

    /// Renders the annotated selection and closes the overlay with the chosen action.
    func perform(_ action: OverlayAction) {
        guard let model = editModel, let image = model.render() else { return }
        finish(.edited(image, action))
    }

    /// Turns the finished selection into an in-place editor: the cropped frozen pixels become
    /// the canvas, with the tool/action bar right under it.
    private func beginEditing() {
        guard let selection = state.selection, let screen = state.selectionScreen,
              let item = frozen.first(where: { $0.screen == screen }),
              let panel = panels.first(where: { $0.frame == screen.frame }), let host = panel.contentView else { return }
        let local = selection.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let crop = SelectionGeometry.pixelCropRect(selection: local, screenSize: screen.frame.size, scale: item.scale)
        guard let image = item.image.cropping(to: crop) else { return }
        let model = EditorModel(base: image, sourceURL: nil, imageScale: item.scale)
        editModel = model
        state.editing = true

        let canvas = AnnotationCanvasView(model: model, embedded: true)
        canvas.frame = local
        canvas.onCommand = { [weak self] command in
            switch command {
            case .copy: self?.perform(.copy)
            case .save, .saveAs: self?.perform(.save)
            }
        }
        host.addSubview(canvas)

        let bar = FirstMouseHostingView(rootView: OverlayEditToolbar(
            model: model, onAction: { [weak self] in self?.perform($0) }, onCancel: { [weak self] in self?.cancel() }))
        let size = bar.fittingSize
        var origin = CGPoint(x: local.maxX - size.width, y: local.minY - size.height - 8)
        if origin.y < 4 { origin.y = local.maxY + 8 }                                   // above
        if origin.y + size.height > host.bounds.maxY - 4 { origin.y = local.minY + 8 }  // inside, last resort
        origin.x = min(max(4, origin.x), host.bounds.maxX - size.width - 4)
        bar.frame = CGRect(origin: origin, size: size)
        host.addSubview(bar)
        panel.makeKey()
        panel.makeFirstResponder(canvas)
        NSCursor.arrow.set()
        redraw()
    }

    // MARK: Private

    private func nudge(_ event: NSEvent) {
        guard state.mode == .area, let selection = state.selection, let screen = state.selectionScreen else { return }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        var dx: CGFloat = 0, dy: CGFloat = 0
        switch event.keyCode {
        case 123: dx = -step
        case 124: dx = step
        case 125: dy = -step
        default: dy = step
        }
        let resize = event.modifierFlags.contains(.option)
        if resize {
            // ⌥→ wider, ⌥← narrower, ⌥↓ taller (grows downward), ⌥↑ shorter; the top edge stays put.
            var r = SelectionGeometry.nudge(selection, dx: dx, dy: -dy, resize: true, within: screen.frame)
            r.origin.y = selection.maxY - r.height
            state.selection = r.intersection(screen.frame)
        } else {
            state.selection = SelectionGeometry.nudge(selection, dx: dx, dy: dy, resize: false, within: screen.frame)
        }
        redraw()
    }

    private func updateHover() {
        state.hoveredWindow = state.mode == .window ? WindowHitTester.topmost(at: state.mouse, in: windows) : nil
    }

    private func finishArea() {
        guard let selection = state.selection, let screen = state.selectionScreen,
              let item = frozen.first(where: { $0.screen == screen }) else {
            finish(.cancelled) // e.g. NSScreen objects recreated by a display change
            return
        }
        if [.scroll, .record, .ruler].contains(state.purpose) {
            finish(.region(selection, screen.displayID ?? 0))
            return
        }
        let local = selection.offsetBy(dx: -screen.frame.minX, dy: -screen.frame.minY)
        let crop = SelectionGeometry.pixelCropRect(selection: local, screenSize: screen.frame.size, scale: item.scale)
        guard let image = item.image.cropping(to: crop) else { finish(.cancelled); return }
        finish(.image(image))
    }

    private func finish(_ result: OverlayResult) {
        panels.forEach { $0.orderOut(nil) }
        panels.removeAll()
        NSCursor.arrow.set()
        let completion = self.completion
        self.completion = nil
        completion?(result)
    }

    private func redraw() {
        panels.forEach { $0.contentView?.needsDisplay = true }
    }

    private func redraw(around points: [CGPoint], all: Bool) {
        for panel in panels where all || points.contains(where: { NSMouseInRect($0, panel.frame, false) }) {
            panel.contentView?.needsDisplay = true
        }
    }
}

/// Borderless full-screen panel above everything, able to take keyboard focus
/// without activating Kadraj (the frontmost app keeps its state).
final class OverlayPanel: NSPanel {
    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = true
        hasShadow = false
        backgroundColor = .black
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
}
