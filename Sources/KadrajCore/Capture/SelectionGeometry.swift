import CoreGraphics

/// Pure geometry used by the selection overlay.
public enum SelectionGeometry {
    public static func normalizedRect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// A click or a hairline drag is not a selection.
    public static func isUsableSelection(_ r: CGRect) -> Bool {
        r.width >= 2 && r.height >= 2
    }

    /// Converts a selection in screen-local AppKit points (bottom-left origin) into a pixel
    /// rect of the screen's captured image (top-left origin), clamped to the image.
    public static func pixelCropRect(selection: CGRect, screenSize: CGSize, scale: CGFloat) -> CGRect {
        let flipped = CGRect(
            x: selection.minX * scale,
            y: (screenSize.height - selection.maxY) * scale,
            width: selection.width * scale,
            height: selection.height * scale
        ).integral
        let image = CGRect(x: 0, y: 0, width: screenSize.width * scale, height: screenSize.height * scale)
        return flipped.intersection(image)
    }

    /// Moves (or resizes when `resize` is true) a selection with the keyboard, keeping it inside `bounds`.
    public static func nudge(_ r: CGRect, dx: CGFloat, dy: CGFloat, resize: Bool, within bounds: CGRect) -> CGRect {
        var out = r
        if resize {
            out.size.width = max(1, r.width + dx)
            out.size.height = max(1, r.height + dy)
            out.size.width = min(out.width, bounds.maxX - out.minX)
            out.size.height = min(out.height, bounds.maxY - out.minY)
        } else {
            out.origin.x = min(max(bounds.minX, r.minX + dx), bounds.maxX - r.width)
            out.origin.y = min(max(bounds.minY, r.minY + dy), bounds.maxY - r.height)
        }
        return out
    }
}
