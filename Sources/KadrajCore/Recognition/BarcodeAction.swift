import Foundation

public enum BarcodeAction {
    /// A QR payload is offered as an "Open" action only if it is a plain web link.
    public static func openableURL(_ payload: String) -> URL? {
        guard let url = URL(string: payload.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }
}
