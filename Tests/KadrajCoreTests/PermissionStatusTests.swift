import Testing
@testable import KadrajCore

@Test func menuTitles() {
    #expect(PermissionStatus.granted.menuTitle == "Ekran Kaydı izni: verildi ✓")
    #expect(PermissionStatus.notGranted.menuTitle == "Ekran Kaydı izni gerekli…")
}

@Test func settingsLink() {
    #expect(SystemSettingsLink.screenRecording.absoluteString ==
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
}
