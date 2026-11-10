import AppKit
import KadrajCore

/// Menü çubuğundaki Kadraj ikonu ve menüsü.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    struct Actions {
        var capture: (CaptureMode) -> Void
        var openOnboarding: () -> Void
        var openSettings: () -> Void
        var pinClipboard: () -> Void
        var makePinsInteractive: () -> Void
        var closeAllPins: () -> Void
        var pinState: () -> (hasPins: Bool, hasClickThrough: Bool)
        var recordingState: () -> (isRecording: Bool, elapsed: String)
        var stopRecording: () -> Void
        var checkForUpdates: () -> Void
    }

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let appInfo: AppInfo
    private let settingsStore: SettingsStore
    private let actions: Actions
    private let menu = NSMenu()
    private var iconWanted = true
    private var isRecording = false

    init(appInfo: AppInfo, settingsStore: SettingsStore, actions: Actions) {
        self.appInfo = appInfo
        self.settingsStore = settingsStore
        self.actions = actions
        super.init()
        statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Kadraj")
        menu.delegate = self
        menu.autoenablesItems = false // honor the explicit isEnabled values
        statusItem.menu = menu
        rebuild()
    }

    /// The "Menü çubuğunda göster" setting. The icon still appears while recording: it is the
    /// recording indicator and the way to stop from the menu bar.
    func setIconVisible(_ visible: Bool) {
        iconWanted = visible
        updateVisibility()
    }

    private func updateVisibility() {
        statusItem.isVisible = iconWanted || isRecording
    }

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated { rebuild() }
    }

    private func rebuild() {
        menu.removeAllItems()
        let recording = actions.recordingState()
        if recording.isRecording {
            let stop = NSMenuItem(title: String(localized: "Stop Recording (\(recording.elapsed))"), action: #selector(stopRecordingClicked), keyEquivalent: "")
            stop.target = self
            stop.image = NSImage(systemSymbolName: "stop.circle.fill", accessibilityDescription: nil)
            menu.addItem(stop)
            menu.addItem(.separator())
        }
        let hotkeys = settingsStore.settings.hotkeys
        let captures: [(HotkeyAction, CaptureMode)] = [
            (.captureArea, .area), (.captureWindow, .window), (.captureFullscreen, .fullscreen), (.scrollCapture, .scroll),
            (.recordScreen, .record),
            (.recognizeText, .text), (.readQRCode, .qr),
            (.pickColor, .color), (.ruler, .ruler),
        ]
        for (action, mode) in captures {
            let item = NSMenuItem(title: action.title, action: #selector(captureClicked(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            if let hotkey = hotkeys[action] { applyShortcut(hotkey, to: item) }
            menu.addItem(item)
        }
        let pinClipboard = NSMenuItem(title: String(localized: "Pin Image from Clipboard"), action: #selector(pinClipboardClicked), keyEquivalent: "")
        pinClipboard.target = self
        pinClipboard.isEnabled = NSImage.canInit(with: .general) // cheap: no decoding
        menu.addItem(pinClipboard)
        let state = actions.pinState()
        if state.hasClickThrough {
            let item = NSMenuItem(title: String(localized: "Make Pins Interactive"), action: #selector(makePinsInteractiveClicked), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        if state.hasPins {
            let item = NSMenuItem(title: String(localized: "Close All Pins"), action: #selector(closeAllPinsClicked), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())

        // Only worth a row while something is missing; once granted it would just be noise.
        if ScreenCapturePermission.status != .granted {
            let permission = NSMenuItem(title: ScreenCapturePermission.status.menuTitle,
                                        action: #selector(permissionClicked), keyEquivalent: "")
            permission.target = self
            menu.addItem(permission)
        }
        let settings = NSMenuItem(title: String(localized: "Settings…"), action: #selector(settingsClicked), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        let version = NSMenuItem(title: appInfo.displayString, action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)
        let updates = NSMenuItem(title: String(localized: "Check for Updates…"), action: #selector(updatesClicked), keyEquivalent: "")
        updates.target = self
        menu.addItem(updates)
        menu.addItem(NSMenuItem(title: String(localized: "Quit Kadraj"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    /// Shows the global shortcut next to the item (display only; Carbon handles the key).
    private func applyShortcut(_ hotkey: Hotkey, to item: NSMenuItem) {
        let name = KeyNames.name(for: hotkey.keyCode)
        guard name.count == 1 else { return }
        item.keyEquivalent = name.lowercased()
        var mask: NSEvent.ModifierFlags = []
        if hotkey.modifiers.contains(.command) { mask.insert(.command) }
        if hotkey.modifiers.contains(.option) { mask.insert(.option) }
        if hotkey.modifiers.contains(.control) { mask.insert(.control) }
        if hotkey.modifiers.contains(.shift) { mask.insert(.shift) }
        item.keyEquivalentModifierMask = mask
    }

    @objc private func captureClicked(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = CaptureMode(rawValue: raw) else { return }
        // Let the menu close before the screen is frozen.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [actions] in actions.capture(mode) }
    }

    @objc private func permissionClicked() {
        if ScreenCapturePermission.status == .notGranted { actions.openOnboarding() }
    }

    @objc private func settingsClicked() { actions.openSettings() }
    @objc private func stopRecordingClicked() { actions.stopRecording() }
    @objc private func updatesClicked() { actions.checkForUpdates() }

    /// Red record symbol in the menu bar while recording.
    func setRecording(_ on: Bool) {
        isRecording = on
        updateVisibility()
        if on {
            // Menu bar images are templates (monochrome); the record symbol must be a real red image.
            let image = NSImage(systemSymbolName: "record.circle.fill", accessibilityDescription: String(localized: "Kadraj is recording"))?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.white, .systemRed]))
            image?.isTemplate = false
            statusItem.button?.image = image
        } else {
            statusItem.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "Kadraj")
        }
    }
    @objc private func pinClipboardClicked() { actions.pinClipboard() }
    @objc private func makePinsInteractiveClicked() { actions.makePinsInteractive() }
    @objc private func closeAllPinsClicked() { actions.closeAllPins() }
}
