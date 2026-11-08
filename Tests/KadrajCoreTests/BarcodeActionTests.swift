import Testing
@testable import KadrajCore

@Test func onlyWebURLsAreOpenable() {
    #expect(BarcodeAction.openableURL("https://kadraj.app/x")?.host == "kadraj.app")
    #expect(BarcodeAction.openableURL("http://example.com") != nil)
    #expect(BarcodeAction.openableURL("javascript:alert(1)") == nil)
    #expect(BarcodeAction.openableURL("file:///etc/passwd") == nil)
    #expect(BarcodeAction.openableURL("merhaba") == nil)
    #expect(BarcodeAction.openableURL("https://") == nil)
}
