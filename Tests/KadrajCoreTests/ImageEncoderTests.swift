import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import KadrajCore

private func makeImage(width: Int, height: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    return ctx.makeImage()!
}

@Test(arguments: [(ImageFormat.png, "public.png"), (ImageFormat.jpeg, "public.jpeg")])
func encodesRoundTrip(format: ImageFormat, uti: String) throws {
    let data = try #require(ImageEncoder.data(for: makeImage(width: 4, height: 3), format: format))
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    #expect(CGImageSourceGetType(source) as String? == uti)
    let decoded = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    #expect(decoded.width == 4)
    #expect(decoded.height == 3)
}

@Test func fileExtensions() {
    #expect(ImageFormat.png.fileExtension == "png")
    #expect(ImageFormat.jpeg.fileExtension == "jpg")
}
