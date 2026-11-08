import Foundation
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

@Test func userinfoURLsAreNotOpenable() {
    #expect(BarcodeAction.openableURL("https://good.com@evil.com") == nil)
    #expect(BarcodeAction.openableURL("https://user:pass@example.com/x") == nil)
}

@Test func preferredResultSkipsEmptyAndPrefersLinks() {
    let text = BarcodeResult(payload: "WIFI:S:Ev;T:WPA;P:1234;;", symbology: "QR")
    let link = BarcodeResult(payload: "https://kadraj.app", symbology: "QR")
    let empty = BarcodeResult(payload: "  ", symbology: "QR")
    #expect(BarcodeAction.preferred([empty, text, link]) == link)
    #expect(BarcodeAction.preferred([empty, text]) == text)
    #expect(BarcodeAction.preferred([empty]) == nil)
}

@Test func openButtonShowsHost() {
    #expect(BarcodeAction.openTitle(for: URL(string: "https://kadraj.app/indir")!) == "Aç: kadraj.app")
}
