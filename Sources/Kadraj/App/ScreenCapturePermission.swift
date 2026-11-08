import CoreGraphics
import KadrajCore

@MainActor
enum ScreenCapturePermission {
    static var status: PermissionStatus {
        CGPreflightScreenCaptureAccess() ? .granted : .notGranted
    }

    /// Sistem izin penceresini tetikler (ilk seferde) ve Kadraj'ı Ekran Kaydı listesine ekler.
    static func request() {
        _ = CGRequestScreenCaptureAccess()
    }
}
