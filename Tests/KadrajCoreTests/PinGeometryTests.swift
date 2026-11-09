import CoreGraphics
import Testing
@testable import KadrajCore

private let natural = CGSize(width: 400, height: 200)

@Test func zoomDoublesSize() {
    let r = PinGeometry.zoomed(frame: CGRect(x: 100, y: 100, width: 400, height: 200), naturalSize: natural,
                               currentScale: 1, factor: 2, anchor: CGPoint(x: 300, y: 200))
    #expect(r.scale == 2)
    #expect(r.frame.size == CGSize(width: 800, height: 400))
}

@Test func anchorAtCenterKeepsCenter() {
    let r = PinGeometry.zoomed(frame: CGRect(x: 100, y: 100, width: 400, height: 200), naturalSize: natural,
                               currentScale: 1, factor: 1.5, anchor: CGPoint(x: 300, y: 200))
    #expect(abs(r.frame.midX - 300) < 0.001 && abs(r.frame.midY - 200) < 0.001)
}

@Test func anchorAtCornerKeepsCorner() {
    let r = PinGeometry.zoomed(frame: CGRect(x: 100, y: 100, width: 400, height: 200), naturalSize: natural,
                               currentScale: 1, factor: 0.5, anchor: CGPoint(x: 100, y: 100))
    #expect(r.frame.origin == CGPoint(x: 100, y: 100))
}

@Test func scaleIsClamped() {
    let r = PinGeometry.zoomed(frame: CGRect(x: 0, y: 0, width: 1200, height: 600), naturalSize: natural,
                               currentScale: 3, factor: 10, anchor: .zero)
    #expect(r.scale == PinGeometry.maxScale)
}

@Test func tinyImageKeepsMinimumSideAndAspect() {
    let r = PinGeometry.zoomed(frame: CGRect(x: 0, y: 0, width: 80, height: 40), naturalSize: CGSize(width: 20, height: 10),
                               currentScale: 1, factor: 0.01, anchor: .zero)
    #expect(r.frame.size == CGSize(width: 80, height: 40))
}

 func zoomOutKeepsAspect() {
    let r = PinGeometry.zoomed(frame: CGRect(x: 0, y: 0, width: 400, height: 200), naturalSize: natural,
                               currentScale: 1, factor: 0.01, anchor: .zero)
    #expect(r.frame.size == CGSize(width: 80, height: 40))
}

 func tallImagesCanShrinkBelowDefaultMinimum() {
    let tall = CGSize(width: 600, height: 15000)
    let r = PinGeometry.zoomed(frame: CGRect(x: 0, y: 0, width: 600, height: 15000), naturalSize: tall,
                               currentScale: 1, factor: 0.001, anchor: .zero, minScale: 0.05)
    #expect(r.scale == 0.05)
    #expect(r.frame.size == CGSize(width: 40, height: 1000))
}

@Test func longSideIsCapped() {
    let s = PinGeometry.size(natural: CGSize(width: 400, height: 15000), scale: 0.01, maxLongSide: 875)
    #expect(s.height <= 875)
    #expect(abs(s.width / s.height - 400.0 / 15000) < 0.001)
}
