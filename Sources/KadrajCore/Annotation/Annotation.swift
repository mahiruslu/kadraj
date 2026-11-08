import CoreGraphics
import Foundation

public struct RGBAColor: Codable, Hashable, Sendable {
    public var r, g, b, a: Double

    public init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    public init(hex: UInt32) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255, b: Double(hex & 0xFF) / 255)
    }

    public static let red = RGBAColor(hex: 0xFF3B30)
    public static let orange = RGBAColor(hex: 0xFF9500)
    public static let yellow = RGBAColor(hex: 0xFFCC00)
    public static let green = RGBAColor(hex: 0x34C759)
    public static let blue = RGBAColor(hex: 0x007AFF)
    public static let black = RGBAColor(hex: 0x000000)
    public static let white = RGBAColor(hex: 0xFFFFFF)
    public static let palette: [RGBAColor] = [.red, .orange, .yellow, .green, .blue, .black, .white]

    public var cgColor: CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
    public func withAlpha(_ alpha: Double) -> RGBAColor { RGBAColor(r: r, g: g, b: b, a: alpha) }
}

/// Stroke widths in image pixels.
public enum StrokeWidth: CGFloat, CaseIterable, Sendable {
    case small = 3, medium = 6, large = 10
}

public struct AnnotationStyle: Equatable, Sendable {
    public var color: RGBAColor
    public var width: StrokeWidth

    public init(color: RGBAColor, width: StrokeWidth) {
        self.color = color
        self.width = width
    }
}

/// Geometry is in image pixels with a top-left origin.
public enum AnnotationKind: Equatable, Sendable {
    case arrow(CGPoint, CGPoint)
    case line(CGPoint, CGPoint)
    case rectangle(CGRect)
    case ellipse(CGRect)
    case pen([CGPoint])
    case highlighter([CGPoint])
    case text(origin: CGPoint, string: String, fontSize: CGFloat)
    case step(center: CGPoint, number: Int)
    case pixelate(CGRect)
    case blur(CGRect)
}

public struct Annotation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var kind: AnnotationKind
    public var style: AnnotationStyle

    public init(id: UUID = UUID(), kind: AnnotationKind, style: AnnotationStyle) {
        self.id = id
        self.kind = kind
        self.style = style
    }

    public func translated(dx: CGFloat, dy: CGFloat) -> Annotation {
        func p(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x + dx, y: point.y + dy) }
        func r(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: dx, dy: dy) }
        var copy = self
        switch kind {
        case .arrow(let a, let b): copy.kind = .arrow(p(a), p(b))
        case .line(let a, let b): copy.kind = .line(p(a), p(b))
        case .rectangle(let rect): copy.kind = .rectangle(r(rect))
        case .ellipse(let rect): copy.kind = .ellipse(r(rect))
        case .pen(let points): copy.kind = .pen(points.map(p))
        case .highlighter(let points): copy.kind = .highlighter(points.map(p))
        case .text(let origin, let string, let size): copy.kind = .text(origin: p(origin), string: string, fontSize: size)
        case .step(let center, let number): copy.kind = .step(center: p(center), number: number)
        case .pixelate(let rect): copy.kind = .pixelate(r(rect))
        case .blur(let rect): copy.kind = .blur(r(rect))
        }
        return copy
    }
}
