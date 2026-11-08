import CoreGraphics
import CoreImage
import CoreText
import Foundation

/// Draws annotations onto an image. All geometry is in image pixels with a top-left origin;
/// `draw(_:in:base:imageHeight:)` expects a context already flipped to that space.
public enum AnnotationRenderer {
    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    /// Full-resolution export: base image, annotations in order, then the crop.
    public static func render(base: CGImage, document: AnnotationDocument) -> CGImage? {
        let width = base.width, height = base.height
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: 1, y: -1)
        let full = CGRect(x: 0, y: 0, width: width, height: height)
        drawImage(base, in: full, ctx: ctx)
        for annotation in document.annotations {
            draw(annotation, in: ctx, base: base, imageHeight: CGFloat(height))
        }
        guard let image = ctx.makeImage() else { return nil }
        guard let crop = document.crop?.standardized.integral.intersection(full), !crop.isEmpty else { return image }
        return image.cropping(to: crop) // CGImage cropping uses a top-left origin, like our model
    }

    public static func draw(_ annotation: Annotation, in ctx: CGContext, base: CGImage?, imageHeight: CGFloat) {
        let color = annotation.style.color.cgColor
        let width = annotation.style.width.rawValue
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(width)
        ctx.setStrokeColor(color)
        ctx.setFillColor(color)

        switch annotation.kind {
        case .arrow(let start, let end):
            let head = AnnotationGeometry.arrowHead(from: start, to: end, width: width)
            // Stop the shaft inside the head so the round cap doesn't poke through the tip.
            let back = CGPoint(x: (head.left.x + head.right.x) / 2, y: (head.left.y + head.right.y) / 2)
            ctx.move(to: start)
            ctx.addLine(to: hypot(end.x - start.x, end.y - start.y) > AnnotationGeometry.arrowHeadLength(width: width) ? back : start)
            ctx.strokePath()
            ctx.move(to: head.left)
            ctx.addLine(to: head.tip)
            ctx.addLine(to: head.right)
            ctx.closePath()
            ctx.fillPath()
        case .line(let a, let b):
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()
        case .rectangle(let rect):
            ctx.stroke(rect.standardized)
        case .ellipse(let rect):
            ctx.strokeEllipse(in: rect.standardized)
        case .pen(let points):
            strokePolyline(points, ctx: ctx)
        case .highlighter(let points):
            ctx.setBlendMode(.multiply)
            ctx.setStrokeColor(annotation.style.color.withAlpha(0.35).cgColor)
            ctx.setLineWidth(AnnotationGeometry.highlighterWidth(width))
            ctx.setLineCap(.square)
            strokePolyline(points, ctx: ctx)
        case .text(let origin, let string, let fontSize):
            drawText(string, at: origin, fontSize: fontSize, color: color, ctx: ctx)
        case .step(let center, let number):
            let d = AnnotationGeometry.stepDiameter(width: width)
            ctx.fillEllipse(in: CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d))
            drawCentered("\(number)", center: center, fontSize: d * 0.55, ctx: ctx)
        case .pixelate(let rect), .blur(let rect):
            guard let base else { return }
            let region = rect.standardized.integral.intersection(CGRect(x: 0, y: 0, width: base.width, height: base.height))
            guard !region.isEmpty, let filtered = filteredRegion(annotation.kind, region: region, base: base) else { return }
            drawImage(filtered, in: region, ctx: ctx)
        }
    }

    // MARK: Helpers

    /// Draws an image upright into a top-left-origin rect of a flipped context.
    public static func drawImage(_ image: CGImage, in rect: CGRect, ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
        ctx.restoreGState()
    }

    private static func strokePolyline(_ points: [CGPoint], ctx: CGContext) {
        guard let first = points.first else { return }
        ctx.move(to: first)
        if points.count == 1 { ctx.addLine(to: first) }
        for p in points.dropFirst() { ctx.addLine(to: p) }
        ctx.strokePath()
    }

    /// Pixelates or blurs `region` (top-left origin) of the base image.
    private static func filteredRegion(_ kind: AnnotationKind, region: CGRect, base: CGImage) -> CGImage? {
        let height = CGFloat(base.height)
        // CoreImage uses a bottom-left origin.
        let ciRegion = CGRect(x: region.minX, y: height - region.maxY, width: region.width, height: region.height)
        let input = CIImage(cgImage: base).clampedToExtent()
        let output: CIImage?
        switch kind {
        case .pixelate:
            let filter = CIFilter(name: "CIPixellate")!
            filter.setValue(input, forKey: kCIInputImageKey)
            // Large blocks: the region must become unreadable, not just softened.
            filter.setValue(max(min(region.width, region.height) / 5, 14), forKey: kCIInputScaleKey)
            // Anchor the blocks to the region's corner so they don't shift with the image size.
            filter.setValue(CIVector(x: ciRegion.minX, y: ciRegion.minY), forKey: kCIInputCenterKey)
            output = filter.outputImage
        case .blur:
            let filter = CIFilter(name: "CIGaussianBlur")!
            filter.setValue(input, forKey: kCIInputImageKey)
            filter.setValue(12, forKey: kCIInputRadiusKey)
            output = filter.outputImage
        default:
            output = nil
        }
        guard let output else { return nil }
        return ciContext.createCGImage(output.cropped(to: ciRegion), from: ciRegion)
    }

    private static func font(size: CGFloat) -> CTFont {
        CTFontCreateUIFontForLanguage(.emphasizedSystem, size, nil) ?? CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    }

    private static func attributed(_ string: String, font: CTFont, fill: CGColor?, stroke: CGColor?, strokeWidth: CGFloat = 0) -> NSAttributedString {
        var attrs: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font]
        if let fill { attrs[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = fill }
        if let stroke {
            attrs[NSAttributedString.Key(kCTStrokeColorAttributeName as String)] = stroke
            attrs[NSAttributedString.Key(kCTStrokeWidthAttributeName as String)] = strokeWidth
        }
        return NSAttributedString(string: string, attributes: attrs)
    }

    /// Multi-line text, top-left at `origin`, with a white outline for legibility.
    private static func drawText(_ string: String, at origin: CGPoint, fontSize: CGFloat, color: CGColor, ctx: CGContext) {
        let f = font(size: fontSize)
        let ascent = CTFontGetAscent(f), lineHeight = fontSize * 1.3
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1) // glyphs upright in the flipped context
        for (i, line) in string.components(separatedBy: "\n").enumerated() {
            let baseline = CGPoint(x: origin.x, y: origin.y + ascent + CGFloat(i) * lineHeight)
            for pass in [attributed(line, font: f, fill: nil, stroke: CGColor(gray: 1, alpha: 1), strokeWidth: 18),
                         attributed(line, font: f, fill: color, stroke: nil)] {
                ctx.textPosition = baseline
                CTLineDraw(CTLineCreateWithAttributedString(pass), ctx)
            }
        }
    }

    private static func drawCentered(_ string: String, center: CGPoint, fontSize: CGFloat, ctx: CGContext) {
        let line = CTLineCreateWithAttributedString(attributed(string, font: font(size: fontSize),
                                                               fill: CGColor(gray: 1, alpha: 1), stroke: nil))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        ctx.textPosition = CGPoint(x: center.x - bounds.midX, y: center.y + bounds.midY)
        CTLineDraw(line, ctx)
    }
}
