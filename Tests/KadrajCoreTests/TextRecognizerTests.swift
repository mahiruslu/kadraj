import Testing
@testable import KadrajCore

@Test func recognizesEnglishAndDigits() async throws {
    let text = try await TextRecognizer.recognize(RecognitionTestImages.text("Merhaba Kadraj 2026"),
                                                  languages: ["tr-TR", "en-US"])
    #expect(text.contains("Merhaba"))
    #expect(text.contains("Kadraj"))
    #expect(text.contains("2026"))
}

/// Turkish OCR (and the newer, more exact recognition model) needs a recent macOS; older
/// systems such as GitHub's macOS 15 runners don't list tr-TR.
private let modernVision = TextRecognizer.supportedLanguages().contains("tr-TR")

@Test(.enabled(if: modernVision, "Vision on this macOS has no Turkish model"))
func recognizesTurkishCharacters() async throws {
    let text = try await TextRecognizer.recognize(RecognitionTestImages.text("Ağır Işık Güzel Şöyle Çiçek İzmir"),
                                                  languages: ["tr-TR"])
    let lower = text.lowercased(with: .init(identifier: "tr_TR"))
    for word in ["ağır", "ışık", "güzel", "şöyle", "çiçek"] {
        #expect(lower.contains(word), "missing \(word) in \(text)")
    }
    // Known Vision limitation: capital dotted İ is returned as I ("İzmir" → "Izmir").
    #expect(text.contains("zmir"))
}

@Test func blankImageGivesEmptyText() async throws {
    #expect(try await TextRecognizer.recognize(RecognitionTestImages.blank(), languages: ["tr-TR"]) == "")
}

@Test func supportedLanguagesAreListed() {
    #expect(TextRecognizer.supportedLanguages().contains("en-US"))
}

/// Codes, IDs and URLs must be copied exactly as shown, not "corrected" into words.
@Test(.enabled(if: modernVision, "older Vision models confuse 0 and O"))
func codesAreNotAutocorrected() async throws {
    // Known Vision limitation: underscores come back as spaces ("usr_id" → "usr id"), so none here.
    let samples = ["ERR-0x1F4A", "TR33 0006 1005", "kadraj.app/v2", "build 7Q9K-2026"]
    for sample in samples {
        let text = try await TextRecognizer.recognize(RecognitionTestImages.text(sample), languages: ["tr-TR", "en-US"])
        #expect(text == sample, "got \(text)")
    }
}
