import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Thumbnails stacked in the bottom-right corner after each capture.
@MainActor
final class QuickAccessController {
    private static let maxVisible = 3
    private static let width: CGFloat = 240
    private static let spacing: CGFloat = 10
    private var entries: [QuickAccessEntry] = []
    /// Runs OCR on a capture (wired by AppDelegate).
    var recognizeText: (CGImage) -> Void = { _ in }

    func show(_ result: CaptureResult) {
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }
        let entry = QuickAccessEntry(result: result, width: Self.width, recognizeText: recognizeText) { [weak self] entry in
            self?.remove(entry)
        }
        entries.insert(entry, at: 0)
        while entries.count > Self.maxVisible { entries.removeLast().close() }
        layout(on: screen)
        entry.panel.orderFrontRegardless()
    }

    private func remove(_ entry: QuickAccessEntry) {
        entry.close()
        entries.removeAll { $0 === entry }
        if let screen = entries.first?.panel.screen { layout(on: screen) }
    }

    private func layout(on screen: NSScreen) {
        let area = screen.visibleFrame
        var y = area.minY + 16
        for entry in entries {
            let size = entry.panel.frame.size
            entry.panel.setFrameOrigin(CGPoint(x: area.maxX - size.width - 16, y: y))
            y += size.height + Self.spacing
        }
    }
}

@MainActor
final class QuickAccessEntry {
    let panel: NSPanel
    private var dismissTask: Task<Void, Never>?
    private let model: QuickAccessModel

    init(result: CaptureResult, width: CGFloat, recognizeText: @escaping (CGImage) -> Void,
         onClose: @escaping (QuickAccessEntry) -> Void) {
        let image = NSImage(cgImage: result.image, size: .zero)
        let aspect = CGFloat(result.image.height) / max(CGFloat(result.image.width), 1)
        // At least 130 pt so the three rows of hover buttons fit on wide, short captures.
        let thumbHeight = min(max(width * aspect, 130), 200)
        let errorHeight: CGFloat = result.error == nil ? 0 : 44
        let size = CGSize(width: width, height: thumbHeight + errorHeight)

        model = QuickAccessModel(result: result, image: image)
        model.recognizeText = recognizeText
        panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        model.close = { [weak self] in if let self { onClose(self) } }
        model.hoverChanged = { [weak self] hovering in
            guard let self else { return }
            hovering ? self.dismissTask?.cancel() : self.scheduleDismiss()
        }
        let view = FirstMouseHostingView(rootView: QuickAccessView(model: model))
        view.frame = CGRect(origin: .zero, size: size)
        panel.contentView = view
        scheduleDismiss()
    }

    func close() {
        dismissTask?.cancel()
        panel.orderOut(nil)
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.model.close?()
        }
    }
}

/// Lets buttons react to the first click in a panel that is not key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class QuickAccessModel: ObservableObject {
    let result: CaptureResult
    let image: NSImage
    var close: (() -> Void)?
    var hoverChanged: ((Bool) -> Void)?
    var recognizeText: (CGImage) -> Void = { _ in }

    init(result: CaptureResult, image: NSImage) {
        self.result = result
        self.image = image
    }

    func copyText() {
        recognizeText(result.image)
        close?()
    }

    func copy() {
        CaptureOutput.copyToClipboard(result.image)
        close?()
    }

    func saveAs() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = result.fileURL?.lastPathComponent ?? "Kadraj.png"
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url,
           let data = NSBitmapImageRep(cgImage: result.image).representation(using: .png, properties: [:]) {
            try? data.write(to: url, options: .atomic)
            close?()
        }
    }

    func revealInFinder() {
        guard let url = result.fileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
        close?()
    }

    func open() {
        guard let url = result.fileURL else { return }
        NSWorkspace.shared.open(url)
        close?()
    }

    /// File for drag & drop: the saved file, or a temporary PNG.
    func dragItem() -> NSItemProvider {
        if let url = result.fileURL, let provider = NSItemProvider(contentsOf: url) { return provider }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("Kadraj", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("Kadraj \(Int(Date().timeIntervalSince1970)).png")
        if let data = NSBitmapImageRep(cgImage: result.image).representation(using: .png, properties: [:]) {
            try? data.write(to: url)
        }
        return NSItemProvider(contentsOf: url) ?? NSItemProvider()
    }
}

private struct QuickAccessView: View {
    @ObservedObject var model: QuickAccessModel
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Image(nsImage: model.image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .onDrag { model.dragItem() }
                    .onTapGesture(count: 2) { model.open() }

                if hovering {
                    Color.black.opacity(0.45)
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            ActionButton(title: "Kopyala", symbol: "doc.on.doc") { model.copy() }
                            ActionButton(title: "Kaydet…", symbol: "square.and.arrow.down") { model.saveAs() }
                        }
                        ActionButton(title: "Metni Kopyala", symbol: "text.viewfinder") { model.copyText() }
                        if model.result.fileURL != nil {
                            ActionButton(title: "Finder'da Göster", symbol: "folder") { model.revealInFinder() }
                        }
                    }
                    VStack {
                        HStack {
                            Button { model.close?() } label: {
                                Image(systemName: "xmark.circle.fill").font(.system(size: 16))
                                    .foregroundStyle(.white, .black.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(6)
                }
            }
            if let error = model.result.error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .padding(6)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.red.opacity(0.85))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.25), lineWidth: 1))
        .onHover { hovering = $0; model.hoverChanged?($0) }
    }
}

private struct ActionButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(0.9), in: Capsule())
                .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
    }
}
