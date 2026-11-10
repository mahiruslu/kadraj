import CoreGraphics
import Testing
@testable import KadrajCore

private func win(_ id: UInt32, _ r: CGRect, layer: Int = 0) -> WindowCandidate {
    WindowCandidate(id: id, frame: r, layer: layer, ownerName: "App\(id)")
}

@Test func picksFrontmostContainingWindow() {
    let front = win(1, CGRect(x: 50, y: 50, width: 100, height: 100))
    let back = win(2, CGRect(x: 0, y: 0, width: 400, height: 400))
    #expect(WindowHitTester.topmost(at: CGPoint(x: 60, y: 60), in: [front, back]) == front)
    #expect(WindowHitTester.topmost(at: CGPoint(x: 300, y: 300), in: [front, back]) == back)
}

@Test func skipsNonNormalLayersAndTinyWindows() {
    let menuBar = win(1, CGRect(x: 0, y: 0, width: 400, height: 400), layer: 25)
    let tiny = win(2, CGRect(x: 0, y: 0, width: 20, height: 20))
    let normal = win(3, CGRect(x: 0, y: 0, width: 300, height: 300))
    #expect(WindowHitTester.topmost(at: CGPoint(x: 10, y: 10), in: [menuBar, tiny, normal]) == normal)
    #expect(WindowHitTester.topmost(at: CGPoint(x: 350, y: 350), in: [menuBar, tiny, normal]) == nil)
}

@Test func clickSelectsWindowUnderPointerClippedToScreen() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let front = win(1, CGRect(x: 100, y: 100, width: 300, height: 200))
    let spanning = win(2, CGRect(x: 800, y: 500, width: 600, height: 500)) // runs off the screen
    let windows = [front, spanning]
    #expect(WindowHitTester.clickSelection(at: CGPoint(x: 150, y: 150), in: windows, screen: screen) == front.frame)
    #expect(WindowHitTester.clickSelection(at: CGPoint(x: 900, y: 600), in: windows, screen: screen)
        == CGRect(x: 800, y: 500, width: 200, height: 300))
}

@Test func clickOnDesktopSelectsNothing() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let windows = [win(1, CGRect(x: 100, y: 100, width: 300, height: 200))]
    #expect(WindowHitTester.clickSelection(at: CGPoint(x: 900, y: 700), in: windows, screen: screen) == nil)
}

@Test func clickIgnoresWindowOnAnotherScreen() {
    let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let other = win(1, CGRect(x: 1000, y: 0, width: 500, height: 500))
    // Pointer on the edge shared with the other screen: nothing of that window is on this one.
    #expect(WindowHitTester.clickSelection(at: CGPoint(x: 1000, y: 100), in: [other], screen: screen) == nil)
}
