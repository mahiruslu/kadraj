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
            window.title = "Kadraj'a Hoş Geldiniz"
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
            Label("Ekran Kaydı izni gerekli", systemImage: "viewfinder")
                .font(.title2.bold())
            Text("Kadraj ekran görüntüsü alabilmek için Ekran Kaydı iznine ihtiyaç duyar. Şirket bilgisayarında bu izin kapalıysa IT ekibinize başvurun.")
                .fixedSize(horizontal: false, vertical: true)
            Text("İzni verdikten sonra Kadraj'ı yeniden başlatmanız gerekir.")
                .foregroundStyle(.secondary)
                .font(.callout)
            HStack {
                Button("İzin Ver") { ScreenCapturePermission.request() }
                    .keyboardShortcut(.defaultAction)
                Button("Sistem Ayarlarını Aç") {
                    NSWorkspace.shared.open(SystemSettingsLink.screenRecording)
                }
                Spacer()
                Button("Kadraj'ı Yeniden Başlat") { Relauncher.relaunch() }
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
