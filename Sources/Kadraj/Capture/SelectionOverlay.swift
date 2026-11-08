import AppKit
import KadrajCore

enum OverlayResult {
    case image(CGImage)
    case window(WindowCandidate)
    case cancelled
}

/// Shared state for all per-screen overlay views.
@MainActor
final class OverlayState {
    var mode: CaptureMode
    /// Selection in global AppKit coordinates, limited to `selectionScreen`.
    var selection: CGRect?
    var selectionScreen: NSScreen?
    var dragStart: CGPoint?
    var mouse: CGPoint = NSEvent.mouseLocation
    var hoveredWindow: WindowCandidate?

    init(mode: CaptureMode) { self.mode = mode == .window ? .window : .area }
}

/// Shows a frozen-screen overlay on every display and lets the user pick an area or a window.
@MainActor
final class SelectionOverlayController {
    private let frozen: [FrozenScreen]
    private let settings: CaptureSettings
    private let windows: [WindowCandidate]
    private let state: OverlayState
    private var panels: [OverlayPanel] = []
    private var completion: ((OverlayResult) -> Void)?

    init(frozen: [FrozenScreen], mode: CaptureMode, settings: CaptureSettings, windows: [WindowCandidate]) {
        self.frozen = frozen
        self.settings = settings
        self.windows = windows
        self.state = OverlayState(mode: mode)
    }

    func run(completion: @escaping (OverlayResult) -> Void) {
        self.completion = completion
        for item in frozen {
            let panel = OverlayPanel(screen: item.screen)
            let view = SelectionOverlayView(frozen: item, state: state, showLoupe: settings.showLoupe, controller: self)
            panel.contentView = view
            panel.orderFrontRegardless()
            panels.append(panel)
        }
        updateHover()
        let keyPanel = panels.first { NSMouseInRect(state.mouse, $0.frame, false) } ?? panels.first
        keyPanel?.makeKey()
        NSCursor.crosshair.set()
        redraw()
    }

    // MARK: Events from views

    func mouseMoved(to point: CGPoint) {
        state.mouse = point
        updateHover()
        redraw()
    }

    func mouseDown(at point: CGPoint, on screen: NSScreen) {
        state.mouse = point
        guard state.mode == .area else { return }
        state.dragStart = point
        state.selectionScreen = screen
        state.selection = nil
        redraw()
    }

    func mouseDragged(to point: CGPoint) {
        state.mouse = point
        guard state.mode == .area, let start = state.dragStart, let screen = state.selectionScreen else { return }
        let clamped = CGPoint(x: min(max(point.x, screen.frame.minX), screen.frame.maxX),
                              y: min(max(point.y, screen.frame.minY), screen.frame.maxY))
        state.selection = SelectionGeometry.normalizedRect(from: start, to: clamped)
        redraw()
    }

    func mouseUp(at point: CGPoint) {
        state.mouse = point
        switch state.mode {
        case .area:
            state.dragStart = nil
            if let selection = state.selection, SelectionGeometry.isUsableSelection(selection) {
                finishArea()
            } else {
                state.selection = nil
                redraw()
            }
        case .window:
            if let window = state.hoveredWindow { finish(.window(window)) }
        case .fullscreen:
            break
        }
    }

    func keyDown(_ event: NSEvent) {
        switch event.keyCode {
        case 53: finish(.cancelled) // Esc
        case 36, 76: // Return, Enter
            if state.mode == .area, state.selection != nil { finishArea() }
            else if state.mode == .window, let window = state.hoveredWindow { finish(.window(window)) }
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
        state.selection = SelectionGeometry.nudge(selection, dx: dx, dy: resize ? -dy : dy,
                                                  resize: resize, within: screen.frame)
        redraw()
    }

    private func updateHover() {
        state.hoveredWindow = state.mode == .window ? WindowHitTester.topmost(at: state.mouse, in: windows) : nil
    }

    private func finishArea() {
        guard let selection = state.selection, let screen = state.selectionScreen,
              let item = frozen.first(where: { $0.screen == screen }) else { return }
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
