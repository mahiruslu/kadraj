import CoreGraphics
import Vision

public struct BarcodeResult: Equatable, Sendable {
    public let payload: String
    public let symbology: String

    public init(payload: String, symbology: String) {
        self.payload = payload
        self.symbology = symbology
    }
}

/// QR codes and other barcodes via Vision (no network).
public enum BarcodeReader {
    public static func read(_ image: CGImage) async throws -> [BarcodeResult] {
        try await VisionQueue.shared.run {
            let request = VNDetectBarcodesRequest()
            try VNImageRequestHandler(cgImage: image).perform([request])
            var seen = Set<String>()
            return (request.results ?? []).compactMap { observation -> BarcodeResult? in
                guard let payload = observation.payloadStringValue, seen.insert(payload).inserted else { return nil }
                return BarcodeResult(payload: payload, symbology: observation.symbology.rawValue)
            }
        }
    }
}
