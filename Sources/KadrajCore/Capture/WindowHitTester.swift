import CoreGraphics

public struct WindowCandidate: Equatable, Sendable {
    public let id: UInt32
    /// AppKit global coordinates.
    public let frame: CGRect
    public let layer: Int
    public let ownerName: String

    public init(id: UInt32, frame: CGRect, layer: Int, ownerName: String) {
        self.id = id
        self.frame = frame
        self.layer = layer
        self.ownerName = ownerName
    }
}

public enum WindowHitTester {
    static let minimumSize: CGFloat = 40

    /// `candidates` must be ordered front to back.
    public static func topmost(at point: CGPoint, in candidates: [WindowCandidate]) -> WindowCandidate? {
        candidates.first { c in
            c.layer == 0
                && c.frame.width >= minimumSize && c.frame.height >= minimumSize
                && c.frame.contains(point)
        }
    }

    /// In area mode a click without dragging selects the window under the pointer (iShot style):
    /// its frame, limited to the clicked screen. `nil` on the desktop or when nothing usable is left.
    public static func clickSelection(at point: CGPoint, in candidates: [WindowCandidate], screen: CGRect) -> CGRect? {
        guard let window = topmost(at: point, in: candidates) else { return nil }
        let rect = window.frame.intersection(screen)
        guard !rect.isNull, SelectionGeometry.isUsableSelection(rect) else { return nil }
        return rect
    }
}
