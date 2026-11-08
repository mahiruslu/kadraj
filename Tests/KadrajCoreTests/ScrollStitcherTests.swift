import Foundation
import CoreGraphics
import Testing
@testable import KadrajCore

/// Deterministic "page": rows of random gray blocks, like text lines. 3 bytes per pixel RGB stored in RGBA.
private struct Page {
    let width: Int, height: Int
    var pixels: [UInt8]

    init(width: Int, height: Int, seed: UInt64) {
        self.width = width; self.height = height
        pixels = [UInt8](repeating: 255, count: width * height * 4)
        var state = seed
        func next() -> UInt64 { state = state &* 6364136223846793005 &+ 1442695040888963407; return state >> 33 }
        for y in 0..<height {
            let lineKind = Int(next() % 5)
            for x in 0..<width {
                let v: UInt8 = lineKind == 0 ? 255 : UInt8(next() % 200 + 30)
                let i = (y * width + x) * 4
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v; pixels[i + 3] = 255
            }
        }
    }

    /// Rows [top, top+h) as a CGImage, optionally overlaid with fixed header/footer bands.
    func frame(top: Int, height h: Int, header: Int = 0, footer: Int = 0) -> CGImage {
        var rows = Array(pixels[(top * width * 4)..<((top + h) * width * 4)])
        for y in 0..<header { for x in 0..<width { let i = (y * width + x) * 4; rows[i] = 10; rows[i + 1] = 120; rows[i + 2] = 200 } }
        for y in (h - footer)..<h { for x in 0..<width { let i = (y * width + x) * 4; rows[i] = 200; rows[i + 1] = 60; rows[i + 2] = 20 } }
        return Self.image(rows, width: width, height: h)
    }

    static func image(_ rows: [UInt8], width: Int, height: Int) -> CGImage {
        let provider = CGDataProvider(data: Data(rows) as CFData)!
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
}

private func rgba(_ image: CGImage) -> [UInt8] {
    var buf = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let ctx = CGContext(data: &buf, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return buf
}

private let page = Page(width: 300, height: 2400, seed: 42)

@Test func stitchesVariableScrollAmounts() throws {
    let s = ScrollStitcher()
    #expect(s.add(page.frame(top: 0, height: 400)) == .first)
    #expect(s.add(page.frame(top: 130, height: 400)) == .appended(130))
    #expect(s.add(page.frame(top: 300, height: 400)) == .appended(170))
    #expect(s.add(page.frame(top: 420, height: 400)) == .appended(120))
    let out = try #require(s.image())
    #expect(out.width == 300 && out.height == 820)
    let expected = rgba(Page.image(Array(page.pixels[0..<(820 * 300 * 4)]), width: 300, height: 820))
    #expect(rgba(out) == expected)
}

@Test func stickyHeaderAndFooterAppearOnce() throws {
    let s = ScrollStitcher()
    _ = s.add(page.frame(top: 0, height: 400, header: 40, footer: 30))
    #expect(s.add(page.frame(top: 100, height: 400, header: 40, footer: 30)) == .appended(100))
    #expect(s.add(page.frame(top: 250, height: 400, header: 40, footer: 30)) == .appended(150))
    let out = try #require(s.image())
    #expect(out.height == 400 + 250)
    let px = rgba(out)
    func row(_ y: Int) -> (UInt8, UInt8, UInt8) { let i = y * 300 * 4; return (px[i], px[i + 1], px[i + 2]) }
    #expect(row(0) == (10, 120, 200))              // header at the top
    #expect(row(39) == (10, 120, 200))
    #expect(row(100) != (10, 120, 200))            // no repeated header further down
    #expect(row(out.height - 1) == (200, 60, 20))  // footer at the bottom
    #expect(row(out.height - 31) != (200, 60, 20)) // only once
}

@Test func unchangedAndReverseFramesAreIgnored() {
    let s = ScrollStitcher()
    _ = s.add(page.frame(top: 200, height: 400))
    #expect(s.add(page.frame(top: 200, height: 400)) == .unchanged)
    #expect(s.add(page.frame(top: 100, height: 400)) == .noMatch)
    #expect(s.height == 400)
}

@Test func tooFastScrollIsNotMatched() {
    let s = ScrollStitcher()
    _ = s.add(page.frame(top: 0, height: 400))
    #expect(s.add(page.frame(top: 390, height: 400)) == .noMatch)
    #expect(s.height == 400)
}

@Test func heightLimitStopsStitching() {
    let s = ScrollStitcher(maxHeight: 900)
    _ = s.add(page.frame(top: 0, height: 400))
    _ = s.add(page.frame(top: 250, height: 400))
    #expect(s.add(page.frame(top: 520, height: 400)) == .limitReached) // 650 + 270 > 900
    #expect(s.height <= 900)
}

/// Text blocks separated by 10 or 40 px of white: the identical bottom rows ("footer")
/// change from frame to frame. The result must still match the page exactly.
@Test func varyingBlankFootersStayPixelExact() throws {
    var gapped = Page(width: 200, height: 1600, seed: 7)
    var y = 0, block = 0
    while y < gapped.height {
        let gap = block % 2 == 0 ? 10 : 60
        for row in y..<min(y + gap, gapped.height) {
            for x in 0..<gapped.width { let i = (row * gapped.width + x) * 4; gapped.pixels[i] = 255; gapped.pixels[i + 1] = 255; gapped.pixels[i + 2] = 255 }
        }
        y += gap + 20
        block += 1
    }
    let s = ScrollStitcher()
    var tops = [0]
    for i in 0..<30 { tops.append(tops.last! + [13, 29, 17, 23, 11, 19][i % 6]) }
    for top in tops { _ = s.add(gapped.frame(top: top, height: 300)) }
    let out = try #require(s.image())
    let end = tops.last! + 300
    #expect(out.height == end)
    let expected = rgba(Page.image(Array(gapped.pixels[0..<(end * 200 * 4)]), width: 200, height: end))
    #expect(rgba(out) == expected)
}
