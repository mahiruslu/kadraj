import AppKit
import SwiftUI

struct ToastAction {
    let title: String
    let perform: () -> Void
}

/// A small result banner at the top of the screen. Unlike system notifications it needs
/// no notification permission.
@MainActor
final class ResultToastController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?

    func show(symbol: String, title: String, detail: String?, actions: [ToastAction] = []) {
        close()
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }

        let view = ToastView(symbol: symbol, title: title, detail: detail,
                             actions: actions.map { action in
                                 ToastAction(title: action.title) { [weak self] in
                                     action.perform()
                                     self?.close()
                                 }
                             },
                             onHover: { [weak self] hovering in
                                 hovering ? self?.dismissTask?.cancel() : self?.scheduleDismiss()
                             })
        let hosting = FirstMouseHostingView(rootView: view)
        let size = hosting.fittingSize
        let panel = NSPanel(contentRect: CGRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.contentView = hosting
        let area = screen.visibleFrame
        panel.setFrameOrigin(CGPoint(x: area.midX - size.width / 2, y: area.maxY - size.height - 12))
        panel.orderFrontRegardless()
        self.panel = panel
        scheduleDismiss()
    }

    func close() {
        dismissTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.close()
        }
    }
}

private struct ToastView: View {
    let symbol: String
    let title: String
    let detail: String?
    let actions: [ToastAction]
    let onHover: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .frame(maxWidth: 360, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !actions.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(actions.indices, id: \.self) { i in
                            Button(actions[i].title, action: actions[i].perform)
                                .controlSize(.small)
                        }
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 260, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15), lineWidth: 1))
        .onHover(perform: onHover)
    }
}
