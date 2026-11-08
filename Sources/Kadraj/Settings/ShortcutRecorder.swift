import AppKit
import KadrajCore
import SwiftUI

/// Click, then press a key combination. Esc cancels, Delete clears.
struct ShortcutRecorder: View {
    @Binding var hotkey: Hotkey?
    var unavailable: Bool
    var onRecordingChange: (Bool) -> Void

    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggle) {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .frame(minWidth: 120)
            }
            .buttonStyle(.bordered)
            .tint(recording ? .accentColor : nil)
            if unavailable {
                Label("Bu kısayol kullanılamıyor", systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.orange)
                    .help("Bu kısayol başka bir uygulama tarafından kullanılıyor olabilir.")
            }
        }
        .onDisappear(perform: stop)
    }

    private var label: String {
        if recording { return "Kısayola basın…" }
        return hotkey?.displayString ?? "Kaydet"
    }

    private func toggle() { recording ? stop() : start() }

    private func start() {
        recording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handle(event)
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording { onRecordingChange(false) }
        recording = false
    }

    private func handle(_ event: NSEvent) {
        let code = UInt32(event.keyCode)
        if code == 53 { stop(); return }                       // Esc
        if code == 51 || code == 117 { hotkey = nil; stop(); return } // Delete
        var mods: Hotkey.Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        if flags.contains(.shift) { mods.insert(.shift) }
        let isFunctionKey = KeyNames.name(for: code).hasPrefix("F") && KeyNames.name(for: code).count > 1
        guard !mods.subtracting(.shift).isEmpty || isFunctionKey else { NSSound.beep(); return }
        hotkey = Hotkey(keyCode: code, modifiers: mods)
        stop()
    }
}
