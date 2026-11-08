import AppKit
import KadrajCore

enum CaptureMode: String {
    case area, window, fullscreen
    /// Select an area, then recognize text / read QR codes instead of saving an image.
    case text, qr
}

/// Runs one capture at a time: permission gate → freeze screens → (overlay) → output.
@MainActor
final class CaptureCoordinator {
    private let settingsStore: SettingsStore
    private let onPermissionMissing: () -> Void
    private let onResult: (CaptureResult) -> Void
    private let toast: ResultToastController
    private var isCapturing = false
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
                    let text = try await TextRecognizer.recognize(image, languages: settingsStore.settings.ocrLanguages)
                    RecognitionOutput.handleText(text, toast: toast)
                case .qr:
                    RecognitionOutput.handleBarcodes(try await BarcodeReader.read(image), toast: toast)
                default:
                    onResult(CaptureOutput.deliver(image, settings: settingsStore.settings))
                }
            } catch {
                NSLog("Kadraj: capture failed: \(error.localizedDescription)")
                if ScreenCapturePermission.status == .notGranted {
                    onPermissionMissing()
                } else if mode == .text || mode == .qr {
                    RecognitionOutput.showError(error.localizedDescription, toast: toast)
                }
            }
        }
    }

    private func image(for mode: CaptureMode, frozen: [FrozenScreen]) async throws -> CGImage? {
        if mode == .fullscreen { return screenUnderMouse(frozen)?.image }

        let windows = try await WindowCapturer.candidates()
        let overlay = SelectionOverlayController(frozen: frozen, mode: mode,
                                                 settings: settingsStore.settings, windows: windows.list)
        activeOverlay = overlay
        defer { activeOverlay = nil }
        let result = await withCheckedContinuation { continuation in
            overlay.run { continuation.resume(returning: $0) }
        }
        switch result {
        case .cancelled:
            return nil
        case .image(let image):
            return image
        case .window(let candidate):
            guard let window = windows.byID[candidate.id] else { return nil }
            return try await WindowCapturer.capture(window, includeShadow: settingsStore.settings.includeWindowShadow)
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
