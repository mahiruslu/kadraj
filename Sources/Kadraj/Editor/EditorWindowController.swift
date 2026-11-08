import AppKit
import KadrajCore
import SwiftUI

@MainActor
final class EditorWindowController: NSObject, NSWindowDelegate {
    /// One editor per capture: reopening the same capture brings its window forward.
    private static var open: [String: EditorWindowController] = [:]
    /// Current capture settings (save folder, format), provided by AppDelegate.
    /// Pins an image (provided by AppDelegate).
    static var pin: (CGImage) -> Void = { _ in }
    static var settings: () -> CaptureSettings = { .defaults(home: FileManager.default.homeDirectoryForCurrentUser) }

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
                                                            onSave: { [weak self] in self?.save() },
                                                            onPin: { [weak self] in
                                                                if let image = self?.model.render() { Self.pin(image) }
                                                            }))
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
        canvas.onCommand = { [weak self] command in
            switch command {
            case .copy: self?.copy()
            case .save: self?.save()
            case .saveAs: self?.saveAs()
            }
        }
        window.center()
    }

    func show() {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        window.makeFirstResponder(canvas)
    }

    // MARK: Output

    func copy() {
        canvas.commitText()
        guard let image = model.render() else { return }
        CaptureOutput.copyToClipboard(image)
    }

    /// Overwrites the original capture (same format), or saves a new file to the capture folder.
    @discardableResult
    func save() -> Bool {
        canvas.commitText()
        guard let image = model.render() else { return false }
        do {
            if let url = model.sourceURL {
                let format: ImageFormat = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png
                guard let data = ImageEncoder.data(for: image, format: format) else { throw CocoaError(.fileWriteUnknown) }
                try data.write(to: url, options: .atomic)
                model.markSaved(at: url)
            } else {
                let url = try CaptureOutput.save(image, settings: Self.settings(), date: Date())
                model.markSaved(at: url)
                window.title = url.lastPathComponent
            }
            return true
        } catch {
            NSAlert(error: error).beginSheetModal(for: window)
            return false
        }
    }

    func saveAs() {
        canvas.commitText()
        guard let image = model.render() else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = model.sourceURL?.lastPathComponent ?? "Kadraj.png"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            let format: ImageFormat = ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) ? .jpeg : .png
            if let data = ImageEncoder.data(for: image, format: format), (try? data.write(to: url, options: .atomic)) != nil {
                self.model.markSaved(at: url)
                self.window.title = url.lastPathComponent
            }
        }
    }

    // MARK: NSWindowDelegate

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        canvas.commitText()
        guard model.hasUnsavedChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "Değişiklikleri kaydetmek istiyor musunuz?"
        alert.informativeText = "Kaydetmezseniz işaretlemeler kaybolur."
        alert.addButton(withTitle: "Kaydet")
        alert.addButton(withTitle: "Kaydetme")
        alert.addButton(withTitle: "İptal")
        switch alert.runModal() {
        case .alertFirstButtonReturn: return save()
        case .alertSecondButtonReturn: return true
        default: return false
        }
    }

    /// Runs the unsaved-changes prompt for every open editor; false if the user cancelled.
    static func confirmCloseAll() -> Bool {
        for controller in open.values where !controller.windowShouldClose(controller.window) {
            controller.show()
            return false
        }
        return true
    }

    func windowWillClose(_ notification: Notification) {
        Self.open[key] = nil
    }
}
