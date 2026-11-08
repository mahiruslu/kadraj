import CoreGraphics
import Foundation

public enum ColorFormat: String, Codable, CaseIterable, Sendable {
    case hex, rgb, hsl

    public var title: String {
        switch self {
        case .hex: "HEX"
        case .rgb: "RGB"
        case .hsl: "HSL"
        }
    }
}

public enum ColorFormatter {
    /// Components are sRGB, 0…1.
    public static func string(red: Double, green: Double, blue: Double, format: ColorFormat) -> String {
        let r = clamp(red), g = clamp(green), b = clamp(blue)
        switch format {
        case .hex:
            return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
        case .rgb:
            return "rgb(\(byte(r)), \(byte(g)), \(byte(b)))"
        case .hsl:
            let maxC = max(r, g, b), minC = min(r, g, b), delta = maxC - minC
            let l = (maxC + minC) / 2
            var h = 0.0, s = 0.0
            if delta > 0 {
                s = delta / (1 - abs(2 * l - 1))
                switch maxC {
                case r: h = 60 * ((g - b) / delta).truncatingRemainder(dividingBy: 6)
                case g: h = 60 * ((b - r) / delta + 2)
                default: h = 60 * ((r - g) / delta + 4)
                }
                if h < 0 { h += 360 }
            }
            return "hsl(\(Int(h.rounded()) % 360), \(Int((s * 100).rounded()))%, \(Int((l * 100).rounded()))%)"
        }
    }

    private static func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
    private static func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
}

public enum RulerFormatter {
    /// "320 × 180 pt · 640 × 360 px"
    public static func label(_ size: CGSize, scale: CGFloat) -> String {
        let w = Int(size.width.rounded()), h = Int(size.height.rounded())
        let pw = Int((size.width * scale).rounded()), ph = Int((size.height * scale).rounded())
        return "\(w) × \(h) pt · \(pw) × \(ph) px"
    }
}
