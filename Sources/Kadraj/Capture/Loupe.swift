import AppKit

/// A magnifier next to the cursor showing the frozen pixels around it.
enum Loupe {
    static let pixels = 15      // odd, so there is a center pixel
    static let zoom: CGFloat = 8

    static func draw(in ctx: CGContext, image: CGImage, scale: CGFloat, viewBounds: CGRect, mouse: CGPoint) {
        let side = CGFloat(pixels) * zoom
        // Pixel under the cursor (image space, top-left origin).
        let px = Int(mouse.x * scale)
        let py = Int((viewBounds.height - mouse.y) * scale)
        let half = pixels / 2
        let source = CGRect(x: px - half, y: py - half, width: pixels, height: pixels)
        guard let crop = image.cropping(to: source) else { return }

        var origin = CGPoint(x: mouse.x + 24, y: mouse.y - side - 24 - 22)
        if origin.x + side > viewBounds.maxX { origin.x = mouse.x - side - 24 }
        if origin.y < 0 { origin.y = mouse.y + 24 }
        let frame = CGRect(origin: CGPoint(x: origin.x, y: origin.y + 22), size: CGSize(width: side, height: side))

        ctx.saveGState()
        let clip = CGPath(roundedRect: frame, cornerWidth: 10, cornerHeight: 10, transform: nil)
        ctx.addPath(clip)
        ctx.clip()
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.fill(frame)
        ctx.interpolationQuality = .none
        // Cropping at the image edge returns fewer pixels; keep them aligned to the cursor.
        let dx = CGFloat(crop.width < pixels && source.minX < 0 ? pixels - crop.width : 0) * zoom
        let dyTop = CGFloat(crop.height < pixels && source.minY < 0 ? pixels - crop.height : 0) * zoom
        let drawRect = CGRect(x: frame.minX + dx,
                              y: frame.maxY - dyTop - CGFloat(crop.height) * zoom,
                              width: CGFloat(crop.width) * zoom, height: CGFloat(crop.height) * zoom)
        ctx.draw(crop, in: drawRect)
        // Center pixel marker.
        let center = CGRect(x: frame.minX + CGFloat(half) * zoom, y: frame.minY + CGFloat(half) * zoom,
                            width: zoom, height: zoom)
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1)
        ctx.stroke(center)
        ctx.restoreGState()

        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(2)
        ctx.addPath(clip)
        ctx.strokePath()

        let label = "\(px), \(py)" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = label.size(withAttributes: attrs)
        let bg = CGRect(x: frame.midX - size.width / 2 - 6, y: origin.y, width: size.width + 12, height: 18)
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: bg, xRadius: 4, yRadius: 4).fill()
        label.draw(at: CGPoint(x: bg.minX + 6, y: bg.minY + 2), withAttributes: attrs)
    }
}
