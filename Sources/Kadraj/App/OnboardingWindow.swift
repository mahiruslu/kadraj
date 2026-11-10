import AppKit
import KadrajCore
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView())
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Welcome to Kadraj")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // Accessory uygulamalarda activate() macOS 14+ tarafından görmezden gelinebilir;
        // pencerenin diğer uygulamaların önüne gelmesini garanti et.
        NSApp.activate()
        window?.orderFrontRegardless()
        window?.makeKey()
    }
}

private struct OnboardingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Screen Recording permission required", systemImage: "viewfinder")
                .font(.title2.bold())
            Text("Kadraj needs the Screen Recording permission to take screenshots. If it is blocked on a company Mac, contact your IT team.")
                .fixedSize(horizontal: false, vertical: true)
            Text("After granting the permission, restart Kadraj.")
                .foregroundStyle(.secondary)
                .font(.callout)
            HStack {
                Button("Grant Permission") { ScreenCapturePermission.request() }
                    .keyboardShortcut(.defaultAction)
                Button("Open System Settings") {
                    NSWorkspace.shared.open(SystemSettingsLink.screenRecording)
                }
                Spacer()
                Button("Restart Kadraj") { Relauncher.relaunch() }
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

@MainActor
enum Relauncher {
    static func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        let url = Bundle.main.bundleURL
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            Task { @MainActor in NSApp.terminate(nil) }
        }
    }
}
