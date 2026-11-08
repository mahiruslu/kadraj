import CoreGraphics

public enum ScreenCoordinates {
    /// CoreGraphics/ScreenCaptureKit global rect (top-left origin of the primary screen)
    /// → AppKit global rect (bottom-left origin of the primary screen).
    public static func appKitRect(fromCG r: CGRect, primaryScreenHeight h: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: h - r.maxY, width: r.width, height: r.height)
    }
}
