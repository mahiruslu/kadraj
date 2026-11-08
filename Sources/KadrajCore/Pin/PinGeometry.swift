import CoreGraphics

public enum PinGeometry {
    public static let minScale: CGFloat = 0.1
    public static let maxScale: CGFloat = 4
    /// A pin's shorter side never gets smaller than this, so it stays grabbable.
    public static let minSide: CGFloat = 40

    /// Pin size at `scale`, keeping the image's aspect ratio; scaled up so the shorter side is ≥ `minSide`.
    public static func size(natural: CGSize, scale: CGFloat) -> CGSize {
        var size = CGSize(width: natural.width * scale, height: natural.height * scale)
        let shorter = min(size.width, size.height)
        if shorter > 0, shorter < minSide {
            let grow = minSide / shorter
            size = CGSize(width: size.width * grow, height: size.height * grow)
        }
        return size
    }

    /// Zooms a pin around `anchor` (global point), keeping that point fixed on screen.
    /// `minScale` can be lowered for very large images so they can shrink to fit.
    public static func zoomed(frame: CGRect, naturalSize: CGSize, currentScale: CGFloat, factor: CGFloat,
                              anchor: CGPoint, minScale: CGFloat = PinGeometry.minScale) -> (frame: CGRect, scale: CGFloat) {
        let scale = min(max(currentScale * factor, minScale), maxScale)
        let size = size(natural: naturalSize, scale: scale)
        let rx = frame.width > 0 ? (anchor.x - frame.minX) / frame.width : 0.5
        let ry = frame.height > 0 ? (anchor.y - frame.minY) / frame.height : 0.5
        let origin = CGPoint(x: anchor.x - rx * size.width, y: anchor.y - ry * size.height)
        return (CGRect(origin: origin, size: size), scale)
    }
}
