import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import KadrajCore

@Test func evenPixelSizes() {
    let a = RecordingGeometry.evenPixelSize(CGSize(width: 101.5, height: 50.25), scale: 2)
    #expect(a.width == 202 && a.height == 100)
    let b = RecordingGeometry.evenPixelSize(CGSize(width: 0.4, height: 0.4), scale: 1)
    #expect(b.width == 2 && b.height == 2)
}

@Test func gifTimingShortClip() {
    let t = GIFTiming.frameTimes(duration: 2, fps: 15, maxFrames: 600)
    #expect(abs(t.delay - 0.07) < 1e-9)          // GIF stores hundredths: 1/15 s isn't representable
    #expect(t.times.count == 28)                 // 28 × 0.07 = 1.96 s ≈ clip length
    #expect(t.times.first == 0)
}

@Test func gifTimingCapsFramesAndKeepsDuration() {
    let t = GIFTiming.frameTimes(duration: 100, fps: 15, maxFrames: 600)
    #expect(t.times.count <= 600)
    #expect(t.times.last! < 100)
    #expect(abs((t.delay * 100).rounded() - t.delay * 100) < 1e-9)   // whole hundredths
    #expect(abs(t.delay * Double(t.times.count) - 100) <= t.delay)    // playback length ≈ clip length
}

private func solid(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGImage {
    let ctx = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(CGColor(red: r, green: g, blue: b, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
    return ctx.makeImage()!
}

@Test func gifWriterStreamsFramesToFile() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("kadraj-test-\(UUID().uuidString).gif")
    defer { try? FileManager.default.removeItem(at: url) }
    let writer = try #require(GIFWriter(url: url, frameCount: 3, delay: 0.1))
    for color in [(1.0, 0.0, 0.0), (0.0, 1.0, 0.0), (0.0, 0.0, 1.0)] { writer.add(solid(color.0, color.1, color.2)) }
    #expect(writer.finish())
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    #expect(CGImageSourceGetCount(source) == 3)
}

@Test func gifEncoderWritesLoopingAnimation() throws {
    let data = try #require(GIFEncoder.encode([solid(1, 0, 0), solid(0, 0, 1)], delay: 0.1))
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    #expect(CGImageSourceGetType(source) as String? == "com.compuserve.gif")
    #expect(CGImageSourceGetCount(source) == 2)
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    #expect((gif?[kCGImagePropertyGIFDelayTime] as? Double).map { abs($0 - 0.1) < 0.001 } == true)
    let fileProps = CGImageSourceCopyProperties(source, nil) as? [CFString: Any]
    let loop = (fileProps?[kCGImagePropertyGIFDictionary] as? [CFString: Any])?[kCGImagePropertyGIFLoopCount] as? Int
    #expect(loop == 0)
}
