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
        guard let first = results.first else {
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
            actions.append(ToastAction(title: "Aç") { NSWorkspace.shared.open(url) })
        }
        toast.show(symbol: "qrcode.viewfinder", title: "QR kod okundu ve kopyalandı", detail: detail, actions: actions)
    }

    static func showError(_ message: String, toast: ResultToastController) {
        toast.show(symbol: "exclamationmark.triangle", title: "İşlem başarısız", detail: message)
    }
}
