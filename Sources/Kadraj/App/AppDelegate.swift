import AppKit
import Combine
import KadrajCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let hotkeys = HotkeyCenter()
    private let hotkeyStatus = HotkeyStatus()
    private let onboarding = OnboardingWindowController()
    private let quickAccess = QuickAccessController()
    private var statusMenu: StatusMenu?
    private var coordinator: CaptureCoordinator?
    private var settingsWindow: SettingsWindowController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = CaptureCoordinator(
            settingsStore: settingsStore,
            onPermissionMissing: { [onboarding] in onboarding.show() },
            onResult: { [settingsStore, quickAccess] result in
                if settingsStore.settings.showQuickAccess || result.error != nil {
                    quickAccess.show(result)
                }
            })
        self.coordinator = coordinator

        let settingsWindow = SettingsWindowController(
            store: settingsStore, status: hotkeyStatus,
            onRecordingChange: { [weak self] recording in
                // Don't trigger captures while the user is typing a new shortcut.
                if recording { self?.hotkeys.unregisterAll() } else { self?.registerHotkeys() }
            })
        self.settingsWindow = settingsWindow

        statusMenu = StatusMenu(
            appInfo: AppInfo(infoDictionary: Bundle.main.infoDictionary),
            settingsStore: settingsStore,
            actions: .init(
                capture: { coordinator.start($0) },
                openOnboarding: { [onboarding] in onboarding.show() },
                openSettings: { settingsWindow.show() }))

        registerHotkeys()
        settingsStore.$settings
            .map(\.hotkeys)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // @Published emits before the value is stored; register on the next turn.
                DispatchQueue.main.async { self?.registerHotkeys() }
            }
            .store(in: &cancellables)

        if ScreenCapturePermission.status == .notGranted {
            onboarding.show()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { handle(url) }
    }

    /// kadraj://capture/area | window | fullscreen
    private func handle(_ url: URL) {
        guard url.scheme == "kadraj", url.host == "capture",
              let mode = CaptureMode(rawValue: url.lastPathComponent) else {
            NSLog("Kadraj: unsupported URL \(url.absoluteString)")
            return
        }
        coordinator?.start(mode)
    }

    private func registerHotkeys() {
        let result = hotkeys.register(settingsStore.settings.hotkeys) { [weak self] action in
            self?.perform(action)
        }
        hotkeyStatus.unavailable = Set(result.filter { !$0.value }.keys)
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .captureArea: coordinator?.start(.area)
        case .captureWindow: coordinator?.start(.window)
        case .captureFullscreen: coordinator?.start(.fullscreen)
        }
    }
}
