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
    /// Toasts with buttons stay longer so there is time to use them.
    private var lifetime: Duration = .seconds(4)

    /// `sticky` keeps the toast until the next one replaces it (e.g. while an export runs).
    func show(symbol: String, title: String, detail: String?, actions: [ToastAction] = [], sticky: Bool = false) {
        close()
        lifetime = actions.isEmpty ? .seconds(4) : .seconds(10)
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }

        let view = ToastView(symbol: symbol, title: title, detail: detail,
                             actions: actions.map { action in
                                 ToastAction(title: action.title) { [weak self] in
                                     // Close first: the action may show a new toast.
                                     self?.close()
                                     action.perform()
                                 }
                             },
                             onClose: { [weak self] in self?.close() })
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
        if !sticky { scheduleDismiss(after: lifetime) }
    }

    func close() {
        dismissTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }

    /// Closes after `delay`, but not from under the pointer: while the mouse is over the toast
    /// (about to press a button) it checks again a moment later. Polling the pointer instead of
    /// hover events, which a non-key panel doesn't reliably get on exit.
    private func scheduleDismiss(after delay: Duration) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            if let panel, NSMouseInRect(NSEvent.mouseLocation, panel.frame, false) {
                scheduleDismiss(after: .seconds(1.5))
            } else {
                close()
            }
        }
    }
}

private struct ToastView: View {
    let symbol: String
    let title: String
    let detail: String?
    let actions: [ToastAction]
    let onClose: () -> Void

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
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close")
        }
        .padding(14)
        .frame(minWidth: 260, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.15), lineWidth: 1))
    }
}
