import AppKit
import KadrajCore

enum CaptureMode: String {
    case area, window, fullscreen
    /// Select an area, then recognize text / read QR codes instead of saving an image.
    case text, qr
    /// Select an area, then stitch frames while the user scrolls it.
    case scroll
    /// Select an area (or click for the whole screen) and record it.
    case record
    /// Measure on the frozen screen (nothing is saved).
    case ruler
    /// Pick a color with the system sampler (handled by AppDelegate, no overlay).
    case color
}

/// Runs one capture at a time: permission gate → freeze screens → (overlay) → output.
@MainActor
final class CaptureCoordinator {
    private let settingsStore: SettingsStore
    private let onPermissionMissing: () -> Void
    private let onResult: (CaptureResult) -> Void
    private let toast: ResultToastController
    /// Starts a recording of the selected region (set by AppDelegate).
    var startRecording: @MainActor (CGRect, NSScreen) async throws -> Void = { _, _ in }
    private var isCapturing = false
    /// Scale of the screen the latest image came from.
    private var lastScale: CGFloat = 2
    /// Action chosen in the in-place editor (`.done` for every other path).
    private var lastAction: OverlayAction = .done
    /// Provided by AppDelegate.
    var openEditor: (CGImage, CGFloat) -> Void = { _, _ in }
    var pin: (CGImage, CGFloat) -> Void = { _, _ in }
    /// True while a capture (overlay, scroll session, …) is running.
    var isBusy: Bool { isCapturing }
    /// Retained for the whole selection: overlay views reference the controller unowned.
    private var activeOverlay: SelectionOverlayController?

    init(settingsStore: SettingsStore,
         onPermissionMissing: @escaping () -> Void,
         onResult: @escaping (CaptureResult) -> Void,
         toast: ResultToastController) {
        self.settingsStore = settingsStore
        self.toast = toast
        self.onPermissionMissing = onPermissionMissing
        self.onResult = onResult
    }

    func start(_ mode: CaptureMode) {
        guard !isCapturing else { return }
        // A modal panel (save/open dialog) would swallow all overlay events and lock the screen.
        guard NSApp.modalWindow == nil else {
            NSSound.beep()
            return
        }
        guard ScreenCapturePermission.status == .granted else {
            onPermissionMissing()
            return
        }
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                let frozen = try await ScreenFreezer.freezeAll()
                guard !frozen.isEmpty else { throw CaptureError.noScreens }
                guard let image = try await image(for: mode, frozen: frozen) else { return }
                switch mode {
                case .text:
                    let languages = settingsStore.settings.ocrLanguages
                    let text = try await RecognitionOutput.withProgress(toast: toast) {
                        try await TextRecognizer.recognize(image, languages: languages)
                    }
                    RecognitionOutput.handleText(text, toast: toast)
                case .qr:
                    RecognitionOutput.handleBarcodes(try await BarcodeReader.read(image), toast: toast)
                default:
                    try await handle(image, action: lastAction)
                }
            } catch {
                NSLog("Kadraj: capture failed: \(error.localizedDescription)")
                if ScreenCapturePermission.status == .notGranted {
                    onPermissionMissing()
                } else {
                    RecognitionOutput.showError(error.localizedDescription, toast: toast)
                }
            }
        }
    }

    private func image(for mode: CaptureMode, frozen: [FrozenScreen]) async throws -> CGImage? {
        lastAction = .done
        if mode == .fullscreen {
            lastScale = screenUnderMouse(frozen)?.scale ?? 2
            return screenUnderMouse(frozen)?.image
        }

        let windows = try await WindowCapturer.candidates()
        let overlay = SelectionOverlayController(frozen: frozen, mode: mode,
                                                 settings: settingsStore.settings, windows: windows.list)
        activeOverlay = overlay
        defer { activeOverlay = nil }
        let result = await withCheckedContinuation { continuation in
            overlay.run { continuation.resume(returning: $0) }
        }
        if mode == .ruler {
            var measured: (CGRect, CGFloat)?
            switch result {
            case .region(let rect, let displayID):
                measured = (rect, NSScreen.screens.first { $0.displayID == displayID }?.backingScaleFactor ?? 2)
            case .window(let candidate):
                measured = (candidate.frame, NSScreen.screens.first { $0.frame.intersects(candidate.frame) }?.backingScaleFactor ?? 2)
            default:
                break
            }
            if let (rect, scale) = measured {
                let size = "\(Int(rect.width.rounded())) × \(Int(rect.height.rounded()))"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(size, forType: .string)
                toast.show(symbol: "ruler", title: "Ölçü kopyalandı: \(size) pt",
                           detail: RulerFormatter.label(rect.size, scale: scale))
            }
            return nil
        }
        if mode == .scroll || mode == .record {
            let target: (CGRect, NSScreen)?
            switch result {
            case .region(let rect, let displayID):
                target = NSScreen.screens.first(where: { $0.displayID == displayID }).map { (rect, $0) }
            case .window(let candidate):
                target = NSScreen.screens.first(where: { $0.frame.intersects(candidate.frame) })
                    .map { (candidate.frame.intersection($0.frame), $0) }
            default:
                target = nil
            }
            guard let (rect, screen) = target else { return nil }
            if mode == .record {
                try await startRecording(rect, screen)
                return nil
            }
            lastScale = screen.backingScaleFactor
            return try await ScrollSession.run(region: rect, screen: screen)
        }
        switch result {
        case .edited(let image, let action):
            lastScale = screenUnderMouse(frozen)?.scale ?? 2
            lastAction = action
            return image
        case .cancelled, .region:
            return nil
        case .image(let image):
            lastScale = screenUnderMouse(frozen)?.scale ?? 2 // the selection ends under the pointer
            return image
        case .window(let candidate):
            guard let window = windows.byID[candidate.id] else { return nil }
            lastScale = NSScreen.screens.first { $0.frame.intersects(candidate.frame) }?.backingScaleFactor ?? 2
            return try await WindowCapturer.capture(window, includeShadow: settingsStore.settings.includeWindowShadow)
        }
    }

    /// Carries out the action picked in the in-place editor toolbar.
    private func handle(_ image: CGImage, action: OverlayAction) async throws {
        let settings = settingsStore.settings
        switch action {
        case .done:
            onResult(await CaptureOutput.deliver(image, settings: settings, scale: lastScale))
        case .copy:
            CaptureOutput.copyToClipboard(image)
            toast.show(symbol: "doc.on.doc", title: "Panoya kopyalandı", detail: nil)
        case .save:
            let url = try await Task.detached { try CaptureOutput.save(image, settings: settings, date: Date()) }.value
            toast.show(symbol: "square.and.arrow.down", title: "Kaydedildi", detail: url.lastPathComponent, actions: [
                ToastAction(title: "Finder'da Göster") { NSWorkspace.shared.activateFileViewerSelecting([url]) },
            ])
        case .pin:
            pin(image, lastScale)
        case .editor:
            openEditor(image, lastScale)
        case .ocr:
            let languages = settings.ocrLanguages
            let text = try await RecognitionOutput.withProgress(toast: toast) {
                try await TextRecognizer.recognize(image, languages: languages)
            }
            RecognitionOutput.handleText(text, toast: toast)
        case .qr:
            RecognitionOutput.handleBarcodes(try await BarcodeReader.read(image), toast: toast)
        }
    }

    private func screenUnderMouse(_ frozen: [FrozenScreen]) -> FrozenScreen? {
        let mouse = NSEvent.mouseLocation
        return frozen.first { NSMouseInRect(mouse, $0.screen.frame, false) } ?? frozen.first
    }
}

enum CaptureError: LocalizedError {
    case noScreens

    var errorDescription: String? {
        switch self {
        case .noScreens: "Ekran görüntüsü alınacak ekran bulunamadı."
        }
    }
}
