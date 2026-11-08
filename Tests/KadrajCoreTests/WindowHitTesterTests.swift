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
