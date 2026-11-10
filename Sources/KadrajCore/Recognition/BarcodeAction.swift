import Foundation

public enum BarcodeAction {
    /// A QR payload is offered as an "Open" action only if it is a plain web link.
    /// Links with user info (`https://good.com@evil.com`) are refused: they disguise the real host.
    public static func openableURL(_ payload: String) -> URL? {
        guard let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil else { return nil }
        return url
    }

    /// The result to copy: the first link if any, otherwise the first non-empty payload.
    public static func preferred(_ results: [BarcodeResult]) -> BarcodeResult? {
        let usable = results.filter { !$0.payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return usable.first { openableURL($0.payload) != nil } ?? usable.first
    }

    /// "Aç: example.com" — the button names the host that will actually open.
    public static func openTitle(for url: URL) -> String {
        String(localized: "Open: \(url.host ?? url.absoluteString)")
    }
}
