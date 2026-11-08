import AppKit
import KadrajCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusMenu: StatusMenu?
    private let onboarding = OnboardingWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let info = AppInfo(infoDictionary: Bundle.main.infoDictionary)
        statusMenu = StatusMenu(appInfo: info) { [onboarding] in onboarding.show() }

        if ScreenCapturePermission.status == .notGranted {
            onboarding.show()
        }
    }
}
