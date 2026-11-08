import CoreGraphics
import Testing
@testable import KadrajCore

private let style = AnnotationStyle(color: .red, width: .medium)

@Test func arrowHeadPointsAlongTheShaft() {
    let head = AnnotationGeometry.arrowHead(from: CGPoint(x: 0, y: 0), to: CGPoint(x: 100, y: 0), width: 6)
    #expect(head.tip == CGPoint(x: 100, y: 0))
    #expect(head.left.x < 100 && head.right.x < 100)
    #expect(abs(head.left.y + head.right.y) < 0.001)
    #expect(abs(head.left.y) > 1)
}

@Test func segmentDistance() {
    let a = CGPoint(x: 0, y: 0), b = CGPoint(x: 10, y: 0)
    #expect(AnnotationGeometry.distance(from: CGPoint(x: 5, y: 0), toSegment: a, b) == 0)
    #expect(AnnotationGeometry.distance(from: CGPoint(x: 5, y: 5), toSegment: a, b) == 5)
    #expect(AnnotationGeometry.distance(from: CGPoint(x: 13, y: 4), toSegment: a, b) == 5)
}

@Test func hitTestLinesAndRectangleEdges() {
    let line = Annotation(kind: .line(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)), style: style)
    let box = Annotation(kind: .rectangle(CGRect(x: 200, y: 0, width: 100, height: 100)), style: style)
    #expect(AnnotationGeometry.hitTest(CGPoint(x: 50, y: 3), annotations: [line, box]) == line.id)
    #expect(AnnotationGeometry.hitTest(CGPoint(x: 50, y: 30), annotations: [line, box]) == nil)
    #expect(AnnotationGeometry.hitTest(CGPoint(x: 201, y: 50), annotations: [line, box]) == box.id)
    #expect(AnnotationGeometry.hitTest(CGPoint(x: 250, y: 50), annotations: [line, box]) == nil)
}

@Test func hitTestPrefersTopmost() {
    let bottom = Annotation(kind: .pixelate(CGRect(x: 0, y: 0, width: 100, height: 100)), style: style)
    let top = Annotation(kind: .step(center: CGPoint(x: 50, y: 50), number: 1), style: style)
    #expect(AnnotationGeometry.hitTest(CGPoint(x: 50, y: 50), annotations: [bottom, top]) == top.id)
    #expect(AnnotationGeometry.hitTest(CGPoint(x: 5, y: 5), annotations: [bottom, top]) == bottom.id)
}

@Test func stepBoundsAreCentered() {
    let b = AnnotationGeometry.bounds(of: .step(center: CGPoint(x: 50, y: 40), number: 2), width: 6)
    #expect(b.midX == 50 && b.midY == 40)
    #expect(b.width >= 28)
}
