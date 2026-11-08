import CoreGraphics
import CoreImage
import CoreText
import Foundation

enum RecognitionTestImages {
    /// Black text on white, 48 pt.
    static func text(_ string: String, width: Int = 1400, height: Int = 200) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, 48, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attrs))
        ctx.textPosition = CGPoint(x: 40, y: CGFloat(height) / 2 - 16)
        CTLineDraw(line, ctx)
        return ctx.makeImage()!
    }

    static func blank(width: Int = 400, height: Int = 200) -> CGImage {
        text("", width: width, height: height)
    }

    /// A QR code scaled 10x with a white margin.
    static func qr(_ payload: String) -> CGImage {
        let filter = CIFilter(name: "CIQRCodeGenerator")!
        filter.setValue(Data(payload.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        let code = filter.outputImage!.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        let margin: CGFloat = 60
        let canvas = CIImage(color: .white)
            .cropped(to: code.extent.insetBy(dx: -margin, dy: -margin))
        let composed = code.composited(over: canvas)
        return CIContext().createCGImage(composed, from: composed.extent)!
    }
}
