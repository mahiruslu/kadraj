import Foundation

/// Ekran Kaydı (Screen Recording) izninin durumu.
public enum PermissionStatus: Sendable {
    case granted
    case notGranted

    public var menuTitle: String {
        switch self {
        case .granted: String(localized: "Screen Recording permission: granted ✓")
        case .notGranted: String(localized: "Screen Recording permission required…")
        }
    }
}

public enum SystemSettingsLink {
    /// Sistem Ayarları > Gizlilik ve Güvenlik > Ekran Kaydı paneli.
    public static let screenRecording = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!
    /// Sistem Ayarları > Gizlilik ve Güvenlik > Erişilebilirlik paneli.
    public static let accessibility = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!
    /// Sistem Ayarları > Gizlilik ve Güvenlik > Mikrofon paneli.
    public static let microphone = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    )!
}
