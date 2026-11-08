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
}
