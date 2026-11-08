import Foundation
import Testing
@testable import KadrajCore

private let home = URL(fileURLWithPath: "/Users/test")

@Test func defaultSettings() {
    let s = CaptureSettings.defaults(home: home)
    #expect(s.saveDirectory.path == "/Users/test/Pictures/Kadraj")
    #expect(s.format == .png)
    #expect(s.saveToFile && s.copyToClipboard && s.showQuickAccess)
    #expect(s.includeWindowShadow && s.showLoupe)
    #expect(s.hotkeys == Hotkey.defaults)
}

@Test func settingsRoundTrip() throws {
    var s = CaptureSettings.defaults(home: home)
    s.format = .jpeg
    s.copyToClipboard = false
    s.hotkeys[.captureArea] = Hotkey(keyCode: 19, modifiers: [.control, .shift])
    let data = try JSONEncoder().encode(s)
    #expect(try CaptureSettings.decode(data, home: home) == s)
}

@Test func missingKeysFallBackToDefaults() throws {
    let s = try CaptureSettings.decode(Data(#"{"format":"jpeg"}"#.utf8), home: home)
    var expected = CaptureSettings.defaults(home: home)
    expected.format = .jpeg
    #expect(s == expected)
}

@Test func clearedHotkeyStaysClearedAfterRoundTrip() throws {
    var s = CaptureSettings.defaults(home: home)
    s.hotkeys[.captureWindow] = nil
    let data = try JSONEncoder().encode(s)
    let decoded = try CaptureSettings.decode(data, home: home)
    #expect(decoded.hotkeys[.captureWindow] == nil)
    #expect(decoded.hotkeys[.captureArea] == Hotkey.defaults[.captureArea])
}

@Test func captureOnReleaseDefaultsToFalse() throws {
    #expect(CaptureSettings.defaults(home: home).captureOnRelease == false)
    #expect(try CaptureSettings.decode(Data("{}".utf8), home: home).captureOnRelease == false)
}
