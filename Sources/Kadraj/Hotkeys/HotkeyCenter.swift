import Carbon.HIToolbox
import KadrajCore

/// Global shortcuts via Carbon `RegisterEventHotKey`. Unlike event taps this needs
/// no Accessibility or Input Monitoring permission, which matters on managed Macs.
@MainActor
final class HotkeyCenter {
    private static let signature: OSType = 0x4B44_524A // 'KDRJ'

    private var refs: [EventHotKeyRef] = []
    private var actionsByID: [UInt32: HotkeyAction] = [:]
    private var handler: (@MainActor (HotkeyAction) -> Void)?
    private var eventHandler: EventHandlerRef?

    /// Replaces all registrations. Returns, per action, whether registration succeeded
    /// (it fails when another app already owns the shortcut).
    @discardableResult
    func register(_ hotkeys: [HotkeyAction: Hotkey],
                  handler: @escaping @MainActor (HotkeyAction) -> Void) -> [HotkeyAction: Bool] {
        unregisterAll()
        installEventHandlerIfNeeded()
        self.handler = handler

        var result: [HotkeyAction: Bool] = [:]
        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let hotkey = hotkeys[action] else { continue }
            let id = UInt32(index + 1)
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                hotkey.keyCode, hotkey.modifiers.carbonFlags,
                EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref {
                refs.append(ref)
                actionsByID[id] = action
                result[action] = true
            } else {
                result[action] = false
            }
        }
        return result
    }

    func unregisterAll() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        actionsByID.removeAll()
    }

    fileprivate func fire(id: UInt32) {
        if let action = actionsByID[id] { handler?(action) }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard status == noErr else { return status }
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated { center.fire(id: hotKeyID.id) }
            return noErr
        }, 1, &spec, userData, &eventHandler)
    }
}
