import CoreGraphics
import Testing
@testable import KadrajCore

/// RGBA8 pixel reader; (x, y) with a top-left origin.
private struct Pixels {
    let width: Int, height: Int
    private let data: [UInt8]

    init(_ image: CGImage) {
        width = image.width; height = image.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let ctx = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        data = buffer
    }

    subscript(x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }
}

private func solid(_ w: Int, _ h: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

/// 4 px black/white checkerboard.
private func checker(_ w: Int, _ h: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(gray: 1, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    for y in stride(from: 0, to: h, by: 4) {
        for x in stride(from: 0, to: w, by: 4) where (x / 4 + y / 4) % 2 == 0 {
            ctx.fill(CGRect(x: x, y: y, width: 4, height: 4))
        }
    }
    return ctx.makeImage()!
}

private let red = AnnotationStyle(color: .red, width: .medium)
private func doc(_ w: Int, _ h: Int, _ a: [AnnotationKind], crop: CGRect? = nil) -> AnnotationDocument {
    AnnotationDocument(imageSize: CGSize(width: w, height: h), annotations: a.map { Annotation(kind: $0, style: red) }, crop: crop)
}
private func isRed(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r > 200 && p.g < 120 && p.b < 120 }
private func isWhite(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r > 240 && p.g > 240 && p.b > 240 }

@Test func rectangleOutlineOnly() throws {
    let out = try #require(AnnotationRenderer.render(base: solid(200, 100),
                                                      document: doc(200, 100, [.rectangle(CGRect(x: 10, y: 10, width: 80, height: 40))])))
    let px = Pixels(out)
    #expect(isRed(px[10, 30]))
    #expect(isWhite(px[50, 30]))
    #expect(isWhite(px[150, 80]))
}

@Test func topLeftOriginIsRespected() throws {
    // A short line near the top must appear near the top of the image.
    let out = try #require(AnnotationRenderer.render(base: solid(100, 100),
                                                      document: doc(100, 100, [.line(CGPoint(x: 10, y: 10), CGPoint(x: 90, y: 10))])))
    let px = Pixels(out)
    #expect(isRed(px[50, 10]))
    #expect(isWhite(px[50, 90]))
}

@Test func pixelateBlocksTheRegionOnly() throws {
    let out = try #require(AnnotationRenderer.render(base: checker(200, 100),
                                                      document: doc(200, 100, [.pixelate(CGRect(x: 0, y: 0, width: 100, height: 100))])))
    let px = Pixels(out)
    #expect(px[20, 20] == px[21, 20])                    // inside: 1 px apart, same block
    #expect(px[20, 20] == px[24, 20])                    // a checker cell apart, same block
    #expect(px[150, 50] != px[154, 50])                  // outside: checkerboard intact
}

@Test func cropProducesCroppedSize() throws {
    let out = try #require(AnnotationRenderer.render(base: solid(200, 100),
                                                      document: doc(200, 100, [], crop: CGRect(x: 50, y: 0, width: 100, height: 100))))
    #expect(out.width == 100 && out.height == 100)
}

@Test func cropKeepsPixelatedRegionAligned() throws {
    let out = try #require(AnnotationRenderer.render(
        base: checker(200, 100),
        document: doc(200, 100, [.pixelate(CGRect(x: 60, y: 10, width: 40, height: 40))],
                      crop: CGRect(x: 50, y: 0, width: 100, height: 100))))
    let px = Pixels(out)
    #expect(px[11, 20] == px[14, 20])   // pixelated area now at x 10…50 in the crop (14 px blocks from x 10)
    #expect(px[70, 70] != px[74, 70])   // untouched area keeps the checkerboard
}

@Test func overflowingBlurDoesNotCrash() throws {
    let out = try #require(AnnotationRenderer.render(base: checker(200, 100),
                                                      document: doc(200, 100, [.blur(CGRect(x: 180, y: 80, width: 100, height: 100))])))
    #expect(out.width == 200 && out.height == 100)
}

@Test func textDrawsSomething() throws {
    let out = try #require(AnnotationRenderer.render(base: solid(300, 100),
                                                      document: doc(300, 100, [.text(origin: CGPoint(x: 10, y: 20), string: "Kadraj", fontSize: 40)])))
    let px = Pixels(out)
    var colored = 0
    for y in 0..<100 { for x in 0..<300 where !isWhite(px[x, y]) { colored += 1 } }
    #expect(colored > 100)
}

@Test func stepBadgeHasWhiteNumber() throws {
    let out = try #require(AnnotationRenderer.render(base: solid(100, 100),
                                                      document: doc(100, 100, [.step(center: CGPoint(x: 50, y: 50), number: 1)])))
    let px = Pixels(out)
    #expect(isRed(px[50 - 12, 50]))     // inside the disc, left of the digit
    var whiteInside = 0
    for y in 42...58 { for x in 46...54 where isWhite(px[x, y]) { whiteInside += 1 } }
    #expect(whiteInside > 5)            // the white "1"
}
