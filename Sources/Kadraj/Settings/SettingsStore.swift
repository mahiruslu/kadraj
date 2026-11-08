import Foundation
import KadrajCore

/// Persists `CaptureSettings` as JSON in UserDefaults.
@MainActor
final class SettingsStore: ObservableObject {
    private static let key = "captureSettings"
    private let defaults: UserDefaults
    private let home = FileManager.default.homeDirectoryForCurrentUser

    @Published var settings: CaptureSettings {
        didSet { save() }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let stored = try? CaptureSettings.decode(data, home: home) {
            settings = stored
        } else {
            settings = .defaults(home: home)
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}
