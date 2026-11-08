import CoreGraphics

public enum PinGeometry {
    public static let minScale: CGFloat = 0.1
    public static let maxScale: CGFloat = 4
    /// A pin never gets smaller than this, so it stays grabbable.
    public static let minSide: CGFloat = 40

    /// Zooms a pin around `anchor` (global point), keeping that point fixed on screen.
    public static func zoomed(frame: CGRect, naturalSize: CGSize, currentScale: CGFloat, factor: CGFloat,
                              anchor: CGPoint) -> (frame: CGRect, scale: CGFloat) {
        let scale = min(max(currentScale * factor, minScale), maxScale)
        let size = CGSize(width: max(naturalSize.width * scale, minSide), height: max(naturalSize.height * scale, minSide))
        let rx = frame.width > 0 ? (anchor.x - frame.minX) / frame.width : 0.5
        let ry = frame.height > 0 ? (anchor.y - frame.minY) / frame.height : 0.5
        let origin = CGPoint(x: anchor.x - rx * size.width, y: anchor.y - ry * size.height)
        return (CGRect(origin: origin, size: size), scale)
    }
}
