import CoreGraphics
import Foundation
import Testing
@testable import KadrajCore

private let red = (r: 255.0 / 255, g: 59.0 / 255, b: 48.0 / 255)

@Test func colorFormats() {
    #expect(ColorFormatter.string(red: red.r, green: red.g, blue: red.b, format: .hex) == "#FF3B30")
    #expect(ColorFormatter.string(red: red.r, green: red.g, blue: red.b, format: .rgb) == "rgb(255, 59, 48)")
    #expect(ColorFormatter.string(red: red.r, green: red.g, blue: red.b, format: .hsl) == "hsl(3, 100%, 59%)")
    #expect(ColorFormatter.string(red: 0, green: 0, blue: 0, format: .hsl) == "hsl(0, 0%, 0%)")
    #expect(ColorFormatter.string(red: 1, green: 1, blue: 1, format: .hex) == "#FFFFFF")
}

@Test func rulerLabel() {
    #expect(RulerFormatter.label(CGSize(width: 320, height: 180), scale: 2) == "320 × 180 pt · 640 × 360 px")
}

@Test func colorFormatSetting() throws {
    let home = URL(fileURLWithPath: "/Users/test")
    #expect(CaptureSettings.defaults(home: home).colorFormat == .hex)
    #expect(try CaptureSettings.decode(Data("{}".utf8), home: home).colorFormat == .hex)
}

@Test func toolHotkeys() {
    #expect(Hotkey.defaults[.pickColor]?.displayString == "⌥⇧C")
    #expect(Hotkey.defaults[.ruler]?.displayString == "⌥⇧M")
    #expect(HotkeyAction.pickColor.title == "Pick Color")
    #expect(HotkeyAction.ruler.title == "Ruler")
}
