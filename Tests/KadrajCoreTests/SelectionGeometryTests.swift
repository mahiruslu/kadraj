import CoreGraphics
import Testing
@testable import KadrajCore

@Test func normalizesReversedDrag() {
    #expect(SelectionGeometry.normalizedRect(from: CGPoint(x: 50, y: 80), to: CGPoint(x: 10, y: 20))
        == CGRect(x: 10, y: 20, width: 40, height: 60))
}

@Test func tinySelectionIsNotUsable() {
    #expect(!SelectionGeometry.isUsableSelection(CGRect(x: 0, y: 0, width: 1, height: 50)))
    #expect(SelectionGeometry.isUsableSelection(CGRect(x: 0, y: 0, width: 2, height: 2)))
}

@Test func pixelCropFlipsAndScalesRetina() {
    let r = SelectionGeometry.pixelCropRect(
        selection: CGRect(x: 10, y: 0, width: 100, height: 50),
        screenSize: CGSize(width: 1440, height: 900), scale: 2)
    #expect(r == CGRect(x: 20, y: 1700, width: 200, height: 100))
}

@Test func pixelCropNonRetinaAndClamped() {
    let r = SelectionGeometry.pixelCropRect(
        selection: CGRect(x: -5, y: 1060, width: 50, height: 40),
        screenSize: CGSize(width: 1920, height: 1080), scale: 1)
    #expect(r == CGRect(x: 0, y: 0, width: 45, height: 20))
}

@Test func nudgeMovesAndResizesWithinBounds() {
    let b = CGRect(x: 0, y: 0, width: 100, height: 100)
    let r = CGRect(x: 90, y: 10, width: 10, height: 10)
    #expect(SelectionGeometry.nudge(r, dx: 5, dy: 0, resize: false, within: b) == r)
    #expect(SelectionGeometry.nudge(r, dx: -1, dy: 1, resize: false, within: b)
        == CGRect(x: 89, y: 11, width: 10, height: 10))
    #expect(SelectionGeometry.nudge(r, dx: -20, dy: 0, resize: true, within: b).width == 1)
}
