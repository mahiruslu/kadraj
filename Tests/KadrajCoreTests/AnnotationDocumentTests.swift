import CoreGraphics
import Testing
@testable import KadrajCore

private let style = AnnotationStyle(color: .red, width: .medium)
private func rect(_ x: CGFloat) -> Annotation {
    Annotation(kind: .rectangle(CGRect(x: x, y: 0, width: 10, height: 10)), style: style)
}
private func step(_ n: Int) -> Annotation {
    Annotation(kind: .step(center: CGPoint(x: n * 10, y: 0), number: n), style: style)
}

@Test func undoRedoRoundTrip() {
    var h = EditHistory(AnnotationDocument(imageSize: CGSize(width: 100, height: 100)))
    #expect(!h.canUndo)
    h.apply { $0.annotations.append(rect(1)) }
    #expect(h.current.annotations.count == 1)
    h.undo()
    #expect(h.current.annotations.isEmpty)
    #expect(h.canRedo)
    h.redo()
    #expect(h.current.annotations.count == 1)
}

@Test func newChangeClearsRedo() {
    var h = EditHistory(AnnotationDocument(imageSize: CGSize(width: 100, height: 100)))
    h.apply { $0.annotations.append(rect(1)) }
    h.undo()
    h.apply { $0.annotations.append(rect(2)) }
    #expect(!h.canRedo)
}

@Test func historyIsCappedAt100() {
    var h = EditHistory(AnnotationDocument(imageSize: CGSize(width: 100, height: 100)))
    for i in 0..<101 { h.apply { $0.annotations.append(rect(CGFloat(i))) } }
    var undos = 0
    while h.canUndo { h.undo(); undos += 1 }
    #expect(undos == 100)
}

@Test func nextStepNumberIsMaxPlusOne() {
    var doc = AnnotationDocument(imageSize: CGSize(width: 100, height: 100))
    #expect(doc.nextStepNumber == 1)
    doc.annotations = [step(1), step(2), step(3)]
    doc.annotations.remove(at: 1)
    #expect(doc.nextStepNumber == 4)
}

@Test func translateMovesGeometry() {
    let r = rect(5).translated(dx: 3, dy: 4)
    #expect(r.kind == .rectangle(CGRect(x: 8, y: 4, width: 10, height: 10)))
    let pen = Annotation(kind: .pen([CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 1)]), style: style).translated(dx: 1, dy: 1)
    #expect(pen.kind == .pen([CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)]))
}

@Test func paletteStartsWithRed() {
    #expect(RGBAColor.palette.count == 7)
    #expect(RGBAColor.palette.first == .red)
}
