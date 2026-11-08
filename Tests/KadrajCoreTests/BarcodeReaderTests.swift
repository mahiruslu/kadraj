import Testing
@testable import KadrajCore

@Test func readsGeneratedQRCode() async throws {
    let results = try await BarcodeReader.read(RecognitionTestImages.qr("https://github.com/mahiruslu/kadraj"))
    #expect(results.count == 1)
    #expect(results.first?.payload == "https://github.com/mahiruslu/kadraj")
}

@Test func blankImageHasNoBarcodes() async throws {
    #expect(try await BarcodeReader.read(RecognitionTestImages.blank()).isEmpty)
}
