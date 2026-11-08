import AppKit
import KadrajCore
import SwiftUI

@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    /// One editor per capture: reopening the same capture brings its window forward.
    private static var open: [String: EditorWindowController] = [:]

    let model: EditorModel
    private let window: NSWindow
    private let key: String
    private let canvas: AnnotationCanvasView

    static func open(image: CGImage, sourceURL: URL?) {
        let key = sourceURL?.standardizedFileURL.path ?? "image-\(ObjectIdentifier(image).hashValue)"
        if let existing = open[key] {
            existing.show()
            return
        }
        let controller = EditorWindowController(image: image, sourceURL: sourceURL, key: key)
        open[key] = controller
        controller.show()
    }

    private init(image: CGImage, sourceURL: URL?, key: String) {
        model = EditorModel(base: image, sourceURL: sourceURL)
        canvas = AnnotationCanvasView(model: model)
        self.key = key

        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let natural = CGSize(width: CGFloat(image.width) / scale + 48, height: CGFloat(image.height) / scale + 48 + 44)
        let size = CGSize(width: min(max(natural.width, 760), visible.width * 0.8),
                          height: min(max(natural.height, 480), visible.height * 0.8))
        window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
                          styleMask: [.titled, .closable, .resizable, .miniaturizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = sourceURL?.lastPathComponent ?? "Yeni Yakalama"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = CGSize(width: 640, height: 400)

        let toolbar = NSHostingView(rootView: EditorToolbar(model: model,
                                                            onCopy: { [weak self] in self?.copy() },
                                                            onSave: { [weak self] in self?.save() }))
        let stack = NSStackView(views: [toolbar, canvas])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.alignment = .leading
        toolbar.setContentHuggingPriority(.required, for: .vertical)
        canvas.translatesAutoresizingMaskIntoConstraints = false
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            toolbar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            canvas.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        window.contentView = stack
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(canvas)
    }

    // MARK: Output (Task 6 completes saving)

    func copy() {
        guard let image = model.render() else { return }
        CaptureOutput.copyToClipboard(image)
    }

    func save() {}

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        Self.open[key] = nil
    }
}
