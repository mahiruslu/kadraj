import AppKit
import KadrajCore

@MainActor
enum RecognitionOutput {
    static func handleText(_ text: String, toast: ResultToastController) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toast.show(symbol: "text.viewfinder", title: String(localized: "No text found"), detail: String(localized: "There is no readable text in the selected area."))
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(trimmed, forType: .string)
        let preview = trimmed.count > 120 ? String(trimmed.prefix(120)) + "…" : trimmed
        toast.show(symbol: "text.viewfinder", title: String(localized: "Text copied (\(trimmed.count) characters)"), detail: preview)
    }

    static func handleBarcodes(_ results: [BarcodeResult], toast: ResultToastController) {
        guard let first = BarcodeAction.preferred(results) else {
            toast.show(symbol: "qrcode.viewfinder", title: String(localized: "No QR code found"), detail: String(localized: "There is no QR code or barcode in the selected area."))
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(first.payload, forType: .string)
        var detail = first.payload
        if results.count > 1 { detail += "\n" + String(localized: "+\(results.count - 1) more") }
        var actions: [ToastAction] = []
        if let url = BarcodeAction.openableURL(first.payload) {
            actions.append(ToastAction(title: BarcodeAction.openTitle(for: url)) { NSWorkspace.shared.open(url) })
        }
        toast.show(symbol: "qrcode.viewfinder", title: String(localized: "QR code read and copied"), detail: detail, actions: actions)
    }

    /// Runs `work`; if it takes longer than 300 ms a "reading…" toast appears meanwhile.
    static func withProgress<T: Sendable>(toast: ResultToastController,
                                          _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let progress = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(300))
            toast.show(symbol: "text.viewfinder", title: String(localized: "Reading text…"), detail: nil)
        }
        defer { progress.cancel() }
        return try await work()
    }

    static func showError(_ message: String, toast: ResultToastController) {
        toast.show(symbol: "exclamationmark.triangle", title: String(localized: "Something went wrong"), detail: message)
    }
}
