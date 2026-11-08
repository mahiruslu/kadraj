import CoreGraphics
import Testing
@testable import KadrajCore

private func frag(_ t: String, x: CGFloat, y: CGFloat, w: CGFloat = 0.2, h: CGFloat = 0.05) -> RecognizedFragment {
    RecognizedFragment(text: t, box: CGRect(x: x, y: y, width: w, height: h))
}

@Test func linesTopToBottom() {
    let lower = frag("ikinci satır", x: 0.1, y: 0.5)
    let upper = frag("birinci satır", x: 0.1, y: 0.8)
    #expect(TextAssembler.assemble([lower, upper]) == "birinci satır\nikinci satır")
}

@Test func fragmentsOnSameLineLeftToRight() {
    let right = frag("Dünya", x: 0.5, y: 0.7)
    let left = frag("Merhaba", x: 0.1, y: 0.7)
    #expect(TextAssembler.assemble([right, left]) == "Merhaba Dünya")
}

@Test func slightlyOffsetFragmentsShareALine() {
    let a = frag("Ad:", x: 0.1, y: 0.700)
    let b = frag("Mahir", x: 0.4, y: 0.715) // offset < half the height (0.025)
    let c = frag("Alt satır", x: 0.1, y: 0.60)
    #expect(TextAssembler.assemble([c, b, a]) == "Ad: Mahir\nAlt satır")
}

@Test func emptyInputAndEmptyFragments() {
    #expect(TextAssembler.assemble([]) == "")
    #expect(TextAssembler.assemble([frag("  ", x: 0, y: 0.5), frag("x", x: 0.3, y: 0.5)]) == "x")
}

@Test func mildlySkewedLinesStayTogether() {
    let l1 = [frag("Bir", x: 0.1, y: 0.80, h: 0.04), frag("iki", x: 0.35, y: 0.79, h: 0.04), frag("üç", x: 0.6, y: 0.78, h: 0.04)]
    let l2 = [frag("dört", x: 0.1, y: 0.74, h: 0.04), frag("beş", x: 0.35, y: 0.73, h: 0.04), frag("altı", x: 0.6, y: 0.72, h: 0.04)]
    #expect(TextAssembler.assemble((l2 + l1).shuffled()) == "Bir iki üç\ndört beş altı")
}

@Test func smallLabelNextToLargeValue() {
    let label = frag("Ad:", x: 0.1, y: 0.50, w: 0.1, h: 0.02)
    let value = frag("MAHİR", x: 0.25, y: 0.49, w: 0.4, h: 0.10)
    #expect(TextAssembler.assemble([value, label]) == "Ad: MAHİR")
}

@Test func twoColumnsWithDifferentSpacingReadColumnByColumn() {
    let a = (0..<3).map { frag("A\($0 + 1)", x: 0.05, y: 0.9 - CGFloat($0) * 0.12, w: 0.35, h: 0.04) }
    let b = (0..<4).map { frag("B\($0 + 1)", x: 0.6, y: 0.88 - CGFloat($0) * 0.08, w: 0.35, h: 0.02) }
    #expect(TextAssembler.assemble((a + b).shuffled()) == "A1\nA2\nA3\nB1\nB2\nB3\nB4")
}

@Test func alignedTableStaysRowByRow() {
    let rows = [("Ad:", "Mahir"), ("Soyad:", "Uslu"), ("Şehir:", "İstanbul")]
    var fragments: [RecognizedFragment] = []
    for (i, row) in rows.enumerated() {
        let y = 0.8 - CGFloat(i) * 0.1
        fragments.append(frag(row.0, x: 0.05, y: y, w: 0.2))
        fragments.append(frag(row.1, x: 0.6, y: y, w: 0.3))
    }
    #expect(TextAssembler.assemble(fragments.shuffled()) == "Ad: Mahir\nSoyad: Uslu\nŞehir: İstanbul")
}
