import AppKit
import KadrajCore
import SwiftUI

/// Which shortcuts could not be registered (owned by another app).
@MainActor
final class HotkeyStatus: ObservableObject {
    @Published var unavailable: Set<HotkeyAction> = []
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let store: SettingsStore
    private let status: HotkeyStatus
    private let recording = ShortcutRecording()
    private var observers: [NSObjectProtocol] = []

    init(store: SettingsStore, status: HotkeyStatus, onRecordingChange: @escaping (Bool) -> Void) {
        self.store = store
        self.status = status
        recording.onChange = onRecordingChange
    }

    func show() {
        if window == nil {
            let view = SettingsView(store: store, status: status, recording: recording)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Kadraj Ayarları"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
            // Never leave global shortcuts unregistered: end recording when focus leaves the window.
            for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main) { [recording] _ in
                        MainActor.assumeIsolated { recording.stop() }
                    })
            }
        }
        NSApp.activate()
        window?.orderFrontRegardless()
        window?.makeKey()
    }
}

private struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var status: HotkeyStatus
    let recording: ShortcutRecording

    var body: some View {
        TabView {
            GeneralTab(settings: $store.settings)
                .tabItem { Label("Genel", systemImage: "gearshape") }
            ShortcutsTab(settings: $store.settings, status: status, recording: recording)
                .tabItem { Label("Kısayollar", systemImage: "keyboard") }
        }
        .padding(20)
        .frame(width: 480)
    }
}

private struct GeneralTab: View {
    @Binding var settings: CaptureSettings

    var body: some View {
        Form {
            Section("Kaydetme") {
                LabeledContent("Klasör") {
                    HStack {
                        Text(settings.saveDirectory.path(percentEncoded: false)
                            .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Değiştir…", action: chooseFolder)
                    }
                }
                Picker("Biçim", selection: $settings.format) {
                    Text("PNG").tag(ImageFormat.png)
                    Text("JPEG").tag(ImageFormat.jpeg)
                }
                .pickerStyle(.segmented)
            }
            Section("Yakalamadan sonra") {
                Toggle("Dosyaya kaydet", isOn: $settings.saveToFile)
                Toggle("Panoya kopyala", isOn: $settings.copyToClipboard)
                Toggle("Quick Access küçük resmini göster", isOn: $settings.showQuickAccess)
            }
            Section("Yakalama") {
                Toggle("Pencere gölgesini dahil et", isOn: $settings.includeWindowShadow)
                Toggle("Alan seçerken büyüteci göster", isOn: $settings.showLoupe)
                Toggle("Fareyi bırakınca hemen yakala", isOn: $settings.captureOnRelease)
                    .help("Kapalıyken seçim ekranda kalır; Return, çift tık veya ✓ ile yakalanır.")
            }
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = settings.saveDirectory
        panel.prompt = "Seç"
        if panel.runModal() == .OK, let url = panel.url {
            settings.saveDirectory = url
        }
    }
}

private struct ShortcutsTab: View {
    @Binding var settings: CaptureSettings
    @ObservedObject var status: HotkeyStatus
    let recording: ShortcutRecording

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    LabeledContent(action.title) {
                        ShortcutRecorder(action: action, hotkey: binding(for: action),
                                         unavailable: status.unavailable.contains(action),
                                         recording: recording)
                    }
                }
            } footer: {
                Text("Kısayolu değiştirmek için tıklayıp yeni tuş kombinasyonuna basın. Esc iptal eder, ⌫ temizler.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Assigning a shortcut that another action uses moves it to this action.
    private func binding(for action: HotkeyAction) -> Binding<Hotkey?> {
        Binding(
            get: { settings.hotkeys[action] },
            set: { newValue in
                if let newValue {
                    for (other, hk) in settings.hotkeys where other != action && hk == newValue {
                        settings.hotkeys[other] = nil
                    }
                }
                settings.hotkeys[action] = newValue
            })
    }
}
