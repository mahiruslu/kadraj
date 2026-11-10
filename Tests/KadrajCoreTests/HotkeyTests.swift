import Foundation
import Testing
@testable import KadrajCore

@Test func defaultHotkeysDisplay() {
    #expect(Hotkey.defaults[.captureArea]?.displayString == "⌥⇧A")
    #expect(Hotkey.defaults[.captureWindow]?.displayString == "⌥⇧W")
    #expect(Hotkey.defaults[.captureFullscreen]?.displayString == "⌥⇧F")
}

@Test func modifierOrderAndCarbonFlags() {
    #expect(Hotkey(keyCode: 0, modifiers: [.command, .shift, .control, .option]).displayString == "⌃⌥⇧⌘A")
    #expect(Hotkey.Modifiers([.command, .shift]).carbonFlags == 0x300)
    #expect(Hotkey.Modifiers([.option, .control]).carbonFlags == 0x1800)
}

@Test func hotkeyCodableRoundTrip() throws {
    let hk = Hotkey(keyCode: 19, modifiers: [.control, .shift])
    let data = try JSONEncoder().encode(hk)
    #expect(try JSONDecoder().decode(Hotkey.self, from: data) == hk)
}

@Test func keyNames() {
    #expect(KeyNames.name(for: 49) == "Space")
    #expect(KeyNames.name(for: 18) == "1")
    #expect(KeyNames.name(for: 122) == "F1")
    #expect(KeyNames.name(for: 999) == "Key 999")
}

@Test func actionTitles() {
    #expect(HotkeyAction.captureArea.title == "Capture Area")
    #expect(HotkeyAction.captureWindow.title == "Capture Window")
    #expect(HotkeyAction.captureFullscreen.title == "Capture Full Screen")
}

@Test func recognitionHotkeys() {
    #expect(Hotkey.defaults[.recognizeText]?.displayString == "⌥⇧O")
    #expect(Hotkey.defaults[.readQRCode]?.displayString == "⌥⇧Q")
    #expect(HotkeyAction.recognizeText.title == "Recognize Text")
    #expect(HotkeyAction.readQRCode.title == "Read QR Code")
}

@Test func scrollCaptureHotkey() {
    #expect(Hotkey.defaults[.scrollCapture]?.displayString == "⌥⇧S")
    #expect(HotkeyAction.scrollCapture.title == "Scrolling Capture")
}

@Test func recordHotkey() {
    #expect(Hotkey.defaults[.recordScreen]?.displayString == "⌥⇧R")
    #expect(HotkeyAction.recordScreen.title == "Record Screen")
}

@Test func recordingsShowShortcutsButNotTyping() {
    // Typed text (passwords!) must never end up in a video: plain and shifted keys are hidden.
    #expect(KeystrokeDisplay.label(keyCode: 0, modifiers: []) == nil)               // a
    #expect(KeystrokeDisplay.label(keyCode: 0, modifiers: [.shift]) == nil)         // A
    #expect(KeystrokeDisplay.label(keyCode: 49, modifiers: []) == nil)              // Space
    #expect(KeystrokeDisplay.label(keyCode: 8, modifiers: [.command]) == "⌘C")
    #expect(KeystrokeDisplay.label(keyCode: 21, modifiers: [.command, .shift]) == "⇧⌘4")
    #expect(KeystrokeDisplay.label(keyCode: 0, modifiers: [.option]) == "⌥A")
    #expect(KeystrokeDisplay.label(keyCode: 36, modifiers: []) == "Return")        // special keys show alone
    #expect(KeystrokeDisplay.label(keyCode: 53, modifiers: []) == "Esc")
    #expect(KeystrokeDisplay.label(keyCode: 125, modifiers: [.shift]) == "⇧↓")
}
