import Foundation

public enum HotkeyAction: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case captureArea, captureWindow, captureFullscreen, scrollCapture, recordScreen, recognizeText, readQRCode,
         pickColor, ruler

    public var title: String {
        switch self {
        case .captureArea: String(localized: "Capture Area")
        case .captureWindow: String(localized: "Capture Window")
        case .captureFullscreen: String(localized: "Capture Full Screen")
        case .scrollCapture: String(localized: "Scrolling Capture")
        case .recordScreen: String(localized: "Record Screen")
        case .recognizeText: String(localized: "Recognize Text")
        case .readQRCode: String(localized: "Read QR Code")
        case .pickColor: String(localized: "Pick Color")
        case .ruler: String(localized: "Ruler")
        }
    }
}

public struct Hotkey: Codable, Equatable, Hashable, Sendable {
    public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)

        /// Carbon `EventModifiers` flags (cmdKey, shiftKey, optionKey, controlKey).
        public var carbonFlags: UInt32 {
            var flags: UInt32 = 0
            if contains(.command) { flags |= 0x0100 }
            if contains(.shift) { flags |= 0x0200 }
            if contains(.option) { flags |= 0x0800 }
            if contains(.control) { flags |= 0x1000 }
            return flags
        }

        /// Standard macOS order: ⌃⌥⇧⌘
        public var symbols: String {
            var s = ""
            if contains(.control) { s += "⌃" }
            if contains(.option) { s += "⌥" }
            if contains(.shift) { s += "⇧" }
            if contains(.command) { s += "⌘" }
            return s
        }
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var displayString: String { modifiers.symbols + KeyNames.name(for: keyCode) }

    public static let defaults: [HotkeyAction: Hotkey] = [
        .captureArea: Hotkey(keyCode: 0, modifiers: [.option, .shift]),        // A
        .captureWindow: Hotkey(keyCode: 13, modifiers: [.option, .shift]),     // W
        .captureFullscreen: Hotkey(keyCode: 3, modifiers: [.option, .shift]),  // F
        .scrollCapture: Hotkey(keyCode: 1, modifiers: [.option, .shift]),      // S
        .recordScreen: Hotkey(keyCode: 15, modifiers: [.option, .shift]),      // R
        .recognizeText: Hotkey(keyCode: 31, modifiers: [.option, .shift]),     // O
        .readQRCode: Hotkey(keyCode: 12, modifiers: [.option, .shift]),        // Q
        .pickColor: Hotkey(keyCode: 8, modifiers: [.option, .shift]),         // C
        .ruler: Hotkey(keyCode: 46, modifiers: [.option, .shift]),             // M
    ]
}

/// Names for macOS virtual key codes (kVK_*), independent of keyboard layout.
public enum KeyNames {
    private static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
        44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete",
        53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    public static func name(for keyCode: UInt32) -> String {
        names[keyCode] ?? "Key \(keyCode)"
    }
}

/// What a screen recording shows for a key press ("Show keyboard shortcuts").
public enum KeystrokeDisplay {
    /// Return, Tab, Delete, Esc, arrows and F-keys are worth showing on their own.
    private static let specialKeys: Set<UInt32> = [36, 48, 51, 53, 117, 123, 124, 125, 126,
                                                   122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]

    /// A label only for shortcuts (⌘, ⌃ or ⌥ held) and special keys; ordinary typing, shifted
    /// or not, returns nil so passwords and messages never appear in a video.
    public static func label(keyCode: UInt32, modifiers: Hotkey.Modifiers) -> String? {
        let shortcut = !modifiers.isDisjoint(with: [.command, .control, .option])
        guard shortcut || specialKeys.contains(keyCode) else { return nil }
        return Hotkey(keyCode: keyCode, modifiers: modifiers).displayString
    }
}
