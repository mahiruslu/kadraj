import AppKit
import KadrajCore

@MainActor
enum RecognitionOutput {
    static func handleText(_ text: String, toast: ResultToastController) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            toast.show(symbol: "text.viewfinder", title: "Metin bulunamadı", detail: "Seçilen alanda okunabilir metin yok.")
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(trimmed, forType: .string)
        let preview = trimmed.count > 120 ? String(trimmed.prefix(120)) + "…" : trimmed
        toast.show(symbol: "text.viewfinder", title: "Metin kopyalandı (\(trimmed.count) karakter)", detail: preview)
    }

    static func handleBarcodes(_ results: [BarcodeResult], toast: ResultToastController) {
        guard let first = BarcodeAction.preferred(results) else {
            toast.show(symbol: "qrcode.viewfinder", title: "QR kod bulunamadı", detail: "Seçilen alanda QR kod veya barkod yok.")
            return
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(first.payload, forType: .string)
        var detail = first.payload
        if results.count > 1 { detail += "\n+\(results.count - 1) kod daha" }
        var actions: [ToastAction] = []
        if let url = BarcodeAction.openableURL(first.payload) {
            actions.append(ToastAction(title: BarcodeAction.openTitle(for: url)) { NSWorkspace.shared.open(url) })
        }
        toast.show(symbol: "qrcode.viewfinder", title: "QR kod okundu ve kopyalandı", detail: detail, actions: actions)
    }

    /// Runs `work`; if it takes longer than 300 ms a "reading…" toast appears meanwhile.
    static func withProgress<T: Sendable>(toast: ResultToastController,
                                          _ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let progress = Task { @MainActor in
            try await Task.sleep(for: .milliseconds(300))
            toast.show(symbol: "text.viewfinder", title: "Metin okunuyor…", detail: nil)
        }
        defer { progress.cancel() }
        return try await work()
    }

    static func showError(_ message: String, toast: ResultToastController) {
        toast.show(symbol: "exclamationmark.triangle", title: "İşlem başarısız", detail: message)
    }
}
