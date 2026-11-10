import Testing
@testable import KadrajCore

@Test func menuTitles() {
    #expect(PermissionStatus.granted.menuTitle == "Screen Recording permission: granted ✓")
    #expect(PermissionStatus.notGranted.menuTitle == "Screen Recording permission required…")
}

@Test func settingsLink() {
    #expect(SystemSettingsLink.screenRecording.absoluteString ==
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
}
