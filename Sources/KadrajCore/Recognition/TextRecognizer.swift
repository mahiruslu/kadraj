import CoreGraphics
import Vision

/// On-device OCR via Apple's Vision framework (no network).
public enum TextRecognizer {
    public static func supportedLanguages() -> [String] {
        (try? makeRequest().supportedRecognitionLanguages()) ?? []
    }

    public static func recognize(_ image: CGImage, languages: [String]) async throws -> String {
        try await VisionQueue.shared.run {
            let request = makeRequest()
            let supported = Set((try? request.supportedRecognitionLanguages()) ?? [])
            let usable = languages.filter(supported.contains)
            if !usable.isEmpty { request.recognitionLanguages = usable }
            try VNImageRequestHandler(cgImage: image).perform([request])
            let fragments = (request.results ?? []).compactMap { observation -> RecognizedFragment? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return RecognizedFragment(text: candidate.string, box: observation.boundingBox)
            }
            return TextAssembler.assemble(fragments)
        }
    }

    private static func makeRequest() -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Off: copied codes, IDs and URLs must match the screen exactly, not be "corrected".
        request.usesLanguageCorrection = false
        request.revision = VNRecognizeTextRequestRevision3
        return request
    }
}
