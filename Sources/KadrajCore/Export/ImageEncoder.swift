import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageFormat: String, Codable, CaseIterable, Sendable {
    case png, jpeg

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        }
    }

    public var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        }
    }
}

public enum ImageEncoder {
    public static func data(for image: CGImage, format: ImageFormat, jpegQuality: Double = 0.9) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, format.utType.identifier as CFString, 1, nil) else {
            return nil
        }
        var props: [CFString: Any] = [:]
        if format == .jpeg { props[kCGImageDestinationLossyCompressionQuality] = jpegQuality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
