import AppKit
import KadrajCore
import SwiftUI

/// The region outline (click-through, so the content underneath can be scrolled) and a small
/// control panel with the stitched height, hints and Done / Cancel.
@MainActor
final class ScrollHUD {
    /// The HUD of the running scroll capture (⌥⇧S again finishes it).
    static weak var active: ScrollHUD?
    private let frame: NSPanel
    private let panel: NSPanel
    private let model = ScrollHUDModel()
    private var continuation: CheckedContinuation<Bool, Never>?

    init(region: CGRect, screen: NSScreen) {
        let outline = region.insetBy(dx: -3, dy: -3)
        frame = NSPanel(contentRect: outline, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        frame.level = .floating
        frame.isOpaque = false
        frame.backgroundColor = .clear
        frame.ignoresMouseEvents = true
        frame.hasShadow = false
        frame.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let border = NSView(frame: CGRect(origin: .zero, size: outline.size))
        border.wantsLayer = true
        border.layer?.borderColor = NSColor.systemRed.cgColor
        border.layer?.borderWidth = 2
        border.layer?.cornerRadius = 3
        frame.contentView = border
        frame.orderFrontRegardless()

        let view = FirstMouseHostingView(rootView: ScrollHUDView(model: model))
        let size = view.fittingSize
        panel = NSPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = view
        // Below the region, else above it; only as a last resort inside it (it would block scrolling there).
        let area = screen.visibleFrame
        var origin = CGPoint(x: region.midX - size.width / 2, y: region.minY - size.height - 12)
        if origin.y < area.minY { origin.y = region.maxY + 12 }
        if origin.y + size.height > area.maxY { origin.y = region.minY + 12 }
        origin.x = min(max(area.minX + 8, origin.x), area.maxX - size.width - 8)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        model.done = { [weak self] in self?.finish(true) }
        model.cancel = { [weak self] in self?.finish(false) }
        Self.active = self
    }

    func waitForDecision() async -> Bool {
        await withCheckedContinuation { continuation = $0 }
    }

    func update(result: ScrollStitcher.AddResult, height: Int) {
        model.height = height
        switch result {
        // After a miss the next frames can only match again if the user goes back a little.
        case .noMatch: model.hint = "Biraz yukarı kaydırın, sonra yavaşça devam edin"
        case .limitReached:
            model.hint = "En fazla yüksekliğe ulaşıldı"
            finish(true)
        case .appended, .first: model.hint = nil
        case .unchanged: break
        }
    }

    /// Ends the session as if Done was pressed (e.g. the stream stopped by itself).
    func finishKeeping() { finish(true) }

    func setPreview(_ image: CGImage) {
        model.preview = NSImage(cgImage: image, size: .zero)
    }

    func close() {
        frame.orderOut(nil)
        panel.orderOut(nil)
    }

    private func finish(_ keep: Bool) {
        continuation?.resume(returning: keep)
        continuation = nil
    }
}

@MainActor
final class ScrollHUDModel: ObservableObject {
    @Published var height = 0
    @Published var hint: String?
    @Published var preview: NSImage?
    var done: () -> Void = {}
    var cancel: () -> Void = {}
}

private struct ScrollHUDView: View {
    @ObservedObject var model: ScrollHUDModel

    var body: some View {
        HStack(spacing: 12) {
            if let preview = model.preview {
                Image(nsImage: preview)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 44, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.secondary.opacity(0.4), lineWidth: 1))
            } else {
                // Same footprint as the preview, so the panel is sized for it from the start
                // (otherwise the buttons get squeezed once the preview appears).
                Image(systemName: "arrow.down.doc").font(.system(size: 18)).foregroundStyle(.tint)
                    .frame(width: 44, height: 70)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Seçili alanı aşağı kaydırın").font(.system(size: 13, weight: .semibold))
                Text(model.hint ?? (model.height > 0 ? "\(model.height) px" : "Kaydırmaya başlayın"))
                    .font(.system(size: 12))
                    .foregroundStyle(model.hint == nil ? Color.secondary : Color.orange)
            }
            .frame(minWidth: 170, alignment: .leading)
            Button("İptal") { model.cancel() }.fixedSize()
            Button("Bitti") { model.done() }.buttonStyle(.borderedProminent).fixedSize()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15), lineWidth: 1))
    }
}
