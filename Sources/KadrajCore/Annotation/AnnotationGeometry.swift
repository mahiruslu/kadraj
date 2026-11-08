import CoreGraphics
import Foundation

public enum AnnotationGeometry {
    static let headAngle: CGFloat = 28 * .pi / 180

    public static func arrowHeadLength(width: CGFloat) -> CGFloat { max(width * 4, 16) }
    public static func stepDiameter(width: CGFloat) -> CGFloat { max(width * 5, 28) }
    public static func highlighterWidth(_ width: CGFloat) -> CGFloat { width * 3 }

    public static func arrowHead(from start: CGPoint, to tip: CGPoint, width: CGFloat) -> (left: CGPoint, tip: CGPoint, right: CGPoint) {
        let angle = atan2(tip.y - start.y, tip.x - start.x)
        let length = arrowHeadLength(width: width)
        func wing(_ delta: CGFloat) -> CGPoint {
            CGPoint(x: tip.x - length * cos(angle + delta), y: tip.y - length * sin(angle + delta))
        }
        return (wing(headAngle), tip, wing(-headAngle))
    }

    public static func distance(from p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSquared))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    public static func bounds(of kind: AnnotationKind, width: CGFloat) -> CGRect {
        switch kind {
        case .arrow(let a, let b):
            return CGRect(points: [a, b]).insetBy(dx: -arrowHeadLength(width: width), dy: -arrowHeadLength(width: width))
        case .line(let a, let b):
            return CGRect(points: [a, b]).insetBy(dx: -width, dy: -width)
        case .rectangle(let r), .ellipse(let r):
            return r.standardized.insetBy(dx: -width / 2, dy: -width / 2)
        case .pen(let points):
            return CGRect(points: points).insetBy(dx: -width, dy: -width)
        case .highlighter(let points):
            let w = highlighterWidth(width)
            return CGRect(points: points).insetBy(dx: -w / 2, dy: -w / 2)
        case .text(let origin, let string, let size):
            let longest = string.split(separator: "\n", omittingEmptySubsequences: false).map(\.count).max() ?? 0
            let lines = max(1, string.split(separator: "\n", omittingEmptySubsequences: false).count)
            return CGRect(x: origin.x, y: origin.y, width: max(size, size * 0.6 * CGFloat(longest)),
                          height: size * 1.3 * CGFloat(lines))
        case .step(let center, _):
            let d = stepDiameter(width: width)
            return CGRect(x: center.x - d / 2, y: center.y - d / 2, width: d, height: d)
        case .pixelate(let r), .blur(let r):
            return r.standardized
        }
    }

    /// The topmost (last) annotation under `p`. Rectangles and ellipses are hit only near
    /// their outline, so something underneath them stays selectable.
    public static func hitTest(_ p: CGPoint, annotations: [Annotation], tolerance: CGFloat = 8) -> UUID? {
        annotations.last { isHit(p, $0, tolerance: tolerance) }?.id
    }

    static func isHit(_ p: CGPoint, _ annotation: Annotation, tolerance: CGFloat) -> Bool {
        let w = annotation.style.width.rawValue
        switch annotation.kind {
        case .arrow(let a, let b), .line(let a, let b):
            return distance(from: p, toSegment: a, b) <= tolerance + w / 2
        case .pen(let points):
            return polylineDistance(p, points) <= tolerance + w / 2
        case .highlighter(let points):
            return polylineDistance(p, points) <= tolerance + highlighterWidth(w) / 2
        case .rectangle(let rect):
            let r = rect.standardized
            let slack = tolerance + w / 2
            return r.insetBy(dx: -slack, dy: -slack).contains(p) && !r.insetBy(dx: slack, dy: slack).contains(p)
        case .ellipse(let rect):
            let r = rect.standardized
            let a = r.width / 2, b = r.height / 2
            guard a > 0, b > 0 else { return false }
            let nx = (p.x - r.midX) / a, ny = (p.y - r.midY) / b
            return abs(sqrt(nx * nx + ny * ny) - 1) * min(a, b) <= tolerance + w / 2
        case .text, .step, .pixelate, .blur:
            return bounds(of: annotation.kind, width: w).contains(p)
        }
    }

    private static func polylineDistance(_ p: CGPoint, _ points: [CGPoint]) -> CGFloat {
        guard let first = points.first else { return .infinity }
        guard points.count > 1 else { return hypot(p.x - first.x, p.y - first.y) }
        return zip(points, points.dropFirst()).map { distance(from: p, toSegment: $0, $1) }.min() ?? .infinity
    }
}

extension CGRect {
    init(points: [CGPoint]) {
        guard let first = points.first else { self = .null; return }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points.dropFirst() {
            minX = Swift.min(minX, p.x); minY = Swift.min(minY, p.y)
            maxX = Swift.max(maxX, p.x); maxY = Swift.max(maxY, p.y)
        }
        self.init(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
