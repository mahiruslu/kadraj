import AppKit
import KadrajCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore = SettingsStore()
    private let hotkeys = HotkeyCenter()
    private let onboarding = OnboardingWindowController()
    private var statusMenu: StatusMenu?
    private var coordinator: CaptureCoordinator?
    private let quickAccess = QuickAccessController()

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

        statusMenu = StatusMenu(
            appInfo: AppInfo(infoDictionary: Bundle.main.infoDictionary),
            settingsStore: settingsStore,
            actions: .init(
                capture: { coordinator.start($0) },
                openOnboarding: { [onboarding] in onboarding.show() },
                openSettings: {}))

        registerHotkeys()

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
        for (action, ok) in result where !ok {
            NSLog("Kadraj: could not register shortcut for \(action.rawValue)")
        }
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .captureArea: coordinator?.start(.area)
        case .captureWindow: coordinator?.start(.window)
        case .captureFullscreen: coordinator?.start(.fullscreen)
        }
    }
}
