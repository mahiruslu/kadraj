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
