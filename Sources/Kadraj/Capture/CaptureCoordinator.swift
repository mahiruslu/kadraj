import AppKit
import KadrajCore

enum CaptureMode: String {
    case area, window, fullscreen
}

/// Runs one capture at a time: permission gate → freeze screens → (overlay) → output.
@MainActor
final class CaptureCoordinator {
    private let settingsStore: SettingsStore
    private let onPermissionMissing: () -> Void
    private let onResult: (CaptureResult) -> Void
    private var isCapturing = false

    init(settingsStore: SettingsStore,
         onPermissionMissing: @escaping () -> Void,
         onResult: @escaping (CaptureResult) -> Void) {
        self.settingsStore = settingsStore
        self.onPermissionMissing = onPermissionMissing
        self.onResult = onResult
    }

    func start(_ mode: CaptureMode) {
        guard !isCapturing else { return }
        guard ScreenCapturePermission.status == .granted else {
            onPermissionMissing()
            return
        }
        isCapturing = true
        Task {
            defer { isCapturing = false }
            do {
                let frozen = try await ScreenFreezer.freezeAll()
                guard let image = try await image(for: mode, frozen: frozen) else { return }
                onResult(CaptureOutput.deliver(image, settings: settingsStore.settings))
            } catch {
                NSLog("Kadraj: capture failed: \(error.localizedDescription)")
                if ScreenCapturePermission.status == .notGranted { onPermissionMissing() }
            }
        }
    }

    private func image(for mode: CaptureMode, frozen: [FrozenScreen]) async throws -> CGImage? {
        if mode == .fullscreen { return screenUnderMouse(frozen)?.image }

        let windows = try await WindowCapturer.candidates()
        let overlay = SelectionOverlayController(frozen: frozen, mode: mode,
                                                 settings: settingsStore.settings, windows: windows.list)
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
