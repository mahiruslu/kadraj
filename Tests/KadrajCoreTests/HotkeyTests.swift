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
    #expect(HotkeyAction.captureArea.title == "Alan Yakala")
    #expect(HotkeyAction.captureWindow.title == "Pencere Yakala")
    #expect(HotkeyAction.captureFullscreen.title == "Tam Ekran Yakala")
}

@Test func recognitionHotkeys() {
    #expect(Hotkey.defaults[.recognizeText]?.displayString == "⌥⇧O")
    #expect(Hotkey.defaults[.readQRCode]?.displayString == "⌥⇧Q")
    #expect(HotkeyAction.recognizeText.title == "Metin Tanı")
    #expect(HotkeyAction.readQRCode.title == "QR Kod Oku")
}
