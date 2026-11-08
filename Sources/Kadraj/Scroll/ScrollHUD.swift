import AppKit
import KadrajCore
import SwiftUI

/// The region outline (click-through, so the content underneath can be scrolled) and a small
/// control panel with the stitched height, hints and Done / Cancel.
@MainActor
final class ScrollHUD {
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
        // Below the region if there is room, otherwise inside its bottom edge.
        let area = screen.visibleFrame
        var origin = CGPoint(x: region.midX - size.width / 2, y: region.minY - size.height - 12)
        if origin.y < area.minY { origin.y = region.minY + 12 }
        origin.x = min(max(area.minX + 8, origin.x), area.maxX - size.width - 8)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()

        model.done = { [weak self] in self?.finish(true) }
        model.cancel = { [weak self] in self?.finish(false) }
    }

    func waitForDecision() async -> Bool {
        await withCheckedContinuation { continuation = $0 }
    }

    func update(result: ScrollStitcher.AddResult, height: Int) {
        model.height = height
        switch result {
        case .noMatch: model.hint = "Daha yavaş kaydırın"
        case .limitReached:
            model.hint = "En fazla yüksekliğe ulaşıldı"
            finish(true)
        case .appended, .first: model.hint = nil
        case .unchanged: break
        }
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
    var done: () -> Void = {}
    var cancel: () -> Void = {}
}

private struct ScrollHUDView: View {
    @ObservedObject var model: ScrollHUDModel

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.doc").font(.system(size: 18)).foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Seçili alanı aşağı kaydırın").font(.system(size: 13, weight: .semibold))
                Text(model.hint ?? (model.height > 0 ? "\(model.height) px" : "Kaydırmaya başlayın"))
                    .font(.system(size: 12))
                    .foregroundStyle(model.hint == nil ? Color.secondary : Color.orange)
            }
            .frame(minWidth: 170, alignment: .leading)
            Button("İptal") { model.cancel() }
            Button("Bitti") { model.done() }.buttonStyle(.borderedProminent)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15), lineWidth: 1))
    }
}
