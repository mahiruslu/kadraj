import AppKit
import KadrajCore
import SwiftUI

/// The single active shortcut recording. Only one recorder can listen at a time, and
/// recording stops whenever the Settings window loses focus or closes, so global
/// shortcuts are never left unregistered.
@MainActor
final class ShortcutRecording: ObservableObject {
    @Published private(set) var active: HotkeyAction?
    var onChange: (Bool) -> Void = { _ in }
    private var monitor: Any?

    /// `handler` returns true when recording is finished.
    func start(_ action: HotkeyAction, handler: @escaping (NSEvent) -> Bool) {
        stop()
        active = action
        onChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if handler(event) { self?.stop() }
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard active != nil else { return }
        active = nil
        onChange(false)
    }
}

/// Click, then press a key combination. Esc cancels, Delete clears.
struct ShortcutRecorder: View {
    let action: HotkeyAction
    @Binding var hotkey: Hotkey?
    var unavailable: Bool
    @ObservedObject var recording: ShortcutRecording

    private var isRecording: Bool { recording.active == action }

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Text(isRecording ? "Kısayola basın…" : (hotkey?.displayString ?? "Kaydet"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 120)
            }
            .buttonStyle(.bordered)
            .tint(isRecording ? .accentColor : nil)
            if unavailable {
                Label("Bu kısayol kullanılamıyor", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.orange)
                    .help("Bu kısayol başka bir uygulama tarafından kullanılıyor.")
            }
        }
    }

    private func toggle() {
        if isRecording { recording.stop(); return }
        recording.start(action) { event in handle(event) }
    }

    /// Returns true when recording is finished.
    private func handle(_ event: NSEvent) -> Bool {
        let code = UInt32(event.keyCode)
        if code == 53 { return true }                              // Esc
        if code == 51 || code == 117 { hotkey = nil; return true } // Delete
        var mods: Hotkey.Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.shift) { mods.insert(.shift) }
        let name = KeyNames.name(for: code)
        let isFunctionKey = name.hasPrefix("F") && name.count > 1
        guard !mods.subtracting(.shift).isEmpty || isFunctionKey else { NSSound.beep(); return false }
        hotkey = Hotkey(keyCode: code, modifiers: mods)
        return true
    }
}
