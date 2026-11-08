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
    private let toast = ResultToastController()
    private let pins = PinController()
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
            },
            toast: toast)
        self.coordinator = coordinator
        EditorWindowController.settings = { [settingsStore] in settingsStore.settings }
        quickAccess.pin = { [pins] image in pins.pin(image) }
        EditorWindowController.pin = { [pins] image in pins.pin(image) }
        pins.onEdit = { image in EditorWindowController.open(image: image, sourceURL: nil) }
        quickAccess.edit = { result in EditorWindowController.open(image: result.image, sourceURL: result.fileURL) }
        quickAccess.recognizeText = { [settingsStore, toast] image in
            Task {
                do {
                    let text = try await TextRecognizer.recognize(image, languages: settingsStore.settings.ocrLanguages)
                    RecognitionOutput.handleText(text, toast: toast)
                } catch {
                    RecognitionOutput.showError(error.localizedDescription, toast: toast)
                }
            }
        }
        pins.onCopyText = quickAccess.recognizeText

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
                openSettings: { settingsWindow.show() },
                pinClipboard: { [pins] in
                    if let image = NSImage(pasteboard: .general)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        pins.pin(image)
                    }
                },
                makePinsInteractive: { [pins] in pins.makeAllInteractive() },
                closeAllPins: { [pins] in pins.closeAll() },
                pinState: { [pins] in (pins.hasPins, pins.hasClickThroughPins) }))

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

    /// kadraj://capture/area|window|fullscreen|text|qr, kadraj://settings
    private func handle(_ url: URL) {
        if url.scheme == "kadraj", url.host == "settings" {
            settingsWindow?.show()
            return
        }
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
        case .recognizeText: coordinator?.start(.text)
        case .readQRCode: coordinator?.start(.qr)
        }
    }
}
