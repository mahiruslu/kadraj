import Foundation

/// The UI language picked in Settings: "System" follows macOS (including the per-app language
/// in System Settings, which writes the same key), otherwise Kadraj's own `AppleLanguages`.
@MainActor
final class AppLanguage: ObservableObject {
    enum Choice: String, CaseIterable, Identifiable {
        case system, en, tr
        var id: String { rawValue }
    }

    private static let key = "AppleLanguages"
    private let defaults = UserDefaults.standard

    @Published var choice: Choice {
        didSet {
            guard choice != oldValue else { return }
            if choice == .system { defaults.removeObject(forKey: Self.key) } else { defaults.set([choice.rawValue], forKey: Self.key) }
            needsRestart = choice != launchChoice
        }
    }
    /// Bundles pick their language at launch, so a change takes effect after a restart.
    @Published private(set) var needsRestart = false
    private let launchChoice: Choice

    init() {
        // Only Kadraj's own domain: the global AppleLanguages is the system language list.
        let own = UserDefaults.standard.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "")?[Self.key] as? [String]
        let initial = own?.first.flatMap { code in Choice.allCases.first { $0 != .system && code.hasPrefix($0.rawValue) } } ?? .system
        choice = initial
        launchChoice = initial
    }
}
