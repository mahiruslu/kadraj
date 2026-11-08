import Testing
@testable import KadrajCore

@Test func recognizesEnglishAndDigits() async throws {
    let text = try await TextRecognizer.recognize(RecognitionTestImages.text("Merhaba Kadraj 2026"),
                                                  languages: ["tr-TR", "en-US"])
    #expect(text.contains("Merhaba"))
    #expect(text.contains("Kadraj"))
    #expect(text.contains("2026"))
}

@Test func recognizesTurkishCharacters() async throws {
    let text = try await TextRecognizer.recognize(RecognitionTestImages.text("Ağır Işık Güzel Şöyle Çiçek"),
                                                  languages: ["tr-TR"])
    let lower = text.lowercased(with: .init(identifier: "tr_TR"))
    for word in ["ağır", "ışık", "güzel", "şöyle", "çiçek"] {
        #expect(lower.contains(word), "missing \(word) in \(text)")
    }
}

@Test func blankImageGivesEmptyText() async throws {
    #expect(try await TextRecognizer.recognize(RecognitionTestImages.blank(), languages: ["tr-TR"]) == "")
}

@Test func turkishIsSupported() {
    #expect(TextRecognizer.supportedLanguages().contains("tr-TR"))
}
