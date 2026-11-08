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
    private var recorder: RecordingController?
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
        let recorder = RecordingController(toast: toast, settings: { [settingsStore] in settingsStore.settings })
        self.recorder = recorder
        coordinator.startRecording = { rect, screen in try await recorder.start(region: rect, screen: screen) }
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
                capture: { [weak self] in self?.startCapture($0) },
                openOnboarding: { [onboarding] in onboarding.show() },
                openSettings: { settingsWindow.show() },
                pinClipboard: { [pins] in
                    if let image = NSImage(pasteboard: .general)?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        pins.pin(image)
                    }
                },
                makePinsInteractive: { [pins] in pins.makeAllInteractive() },
                closeAllPins: { [pins] in pins.closeAll() },
                pinState: { [pins] in (pins.hasPins, pins.hasClickThroughPins) },
                recordingState: { (recorder.isRecording, recorder.elapsedText) },
                stopRecording: { recorder.stop() }))
        recorder.onStateChange = { [weak self] on in self?.statusMenu?.setRecording(on) }

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

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        EditorWindowController.confirmCloseAll() ? .terminateNow : .terminateCancel
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
        startCapture(mode)
    }

    /// Single entry point for menu, shortcuts and URLs: the record action toggles, and nothing
    /// else starts while a recording is running.
    private func startCapture(_ mode: CaptureMode) {
        if let recorder, recorder.isRecording {
            if mode == .record { recorder.stop() } else { NSSound.beep() }
            return
        }
        if mode == .color { pickColor(); return }
        coordinator?.start(mode)
    }

    /// System color sampler (no permission needed); the color is copied in the chosen format.
    private func pickColor() {
        NSColorSampler().show { [weak self] color in
            guard let rgb = color?.usingColorSpace(.sRGB) else { return }
            let (r, g, b) = (rgb.redComponent, rgb.greenComponent, rgb.blueComponent)
            // AppKit calls the sampler handler on the main thread.
            MainActor.assumeIsolated {
                guard let self else { return }
                let text = ColorFormatter.string(red: r, green: g, blue: b, format: self.settingsStore.settings.colorFormat)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                self.toast.show(symbol: "eyedropper", title: "Renk kopyalandı", detail: text)
            }
        }
    }

    private func registerHotkeys() {
        let result = hotkeys.register(settingsStore.settings.hotkeys) { [weak self] action in
            self?.perform(action)
        }
        hotkeyStatus.unavailable = Set(result.filter { !$0.value }.keys)
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .captureArea: startCapture(.area)
        case .captureWindow: startCapture(.window)
        case .captureFullscreen: startCapture(.fullscreen)
        case .scrollCapture: startCapture(.scroll)
        case .recordScreen: startCapture(.record)
        case .recognizeText: startCapture(.text)
        case .readQRCode: startCapture(.qr)
        case .pickColor: startCapture(.color)
        case .ruler: startCapture(.ruler)
        }
    }
}
