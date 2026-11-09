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
            RecognitionTab(settings: $store.settings)
                .tabItem { Label("Metin Tanıma", systemImage: "text.viewfinder") }
        }
        // Grouped forms have no intrinsic height; without a fixed size the window collapses.
        .padding(20)
        .frame(width: 540, height: 560)
    }
}

private struct GeneralTab: View {
    @Binding var settings: CaptureSettings
    @StateObject private var loginItem = LoginItem()

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
            Section("Sistem") {
                Toggle("Girişte başlat", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                if loginItem.needsApproval {
                    HStack {
                        Text("Sistem Ayarları'nda onay bekliyor.").font(.caption).foregroundStyle(.secondary)
                        Button("Aç") { loginItem.openSystemSettings() }.controlSize(.small)
                    }
                } else if let error = loginItem.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Yakalama") {
                Toggle("Pencere gölgesini dahil et", isOn: $settings.includeWindowShadow)
                Toggle("Alan seçerken büyüteci göster", isOn: $settings.showLoupe)
                Picker("Renk biçimi", selection: $settings.colorFormat) {
                    ForEach(ColorFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Fareyi bırakınca hemen yakala", isOn: $settings.captureOnRelease)
                    .help("Kapalıyken seçim ekranda kalır; Return, çift tık veya ✓ ile yakalanır.")
            }
        }
        .formStyle(.grouped)
        .onAppear { loginItem.refresh() }
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

private struct RecognitionTab: View {
    @Binding var settings: CaptureSettings
    private let supported = TextRecognizer.supportedLanguages()
    private let locale = Locale(identifier: "tr_TR")

    var body: some View {
        Form {
            Section {
                List {
                    ForEach(sortedLanguages, id: \.self) { code in
                        Toggle(name(for: code), isOn: binding(for: code))
                            .disabled(settings.ocrLanguages == [code])
                    }
                }
                .frame(height: 360)
            } header: {
                Text("Tanınacak diller")
            } footer: {
                Text("Metin tanıma tamamen bu Mac'te yapılır, internete bağlanmaz. Seçtiğiniz dillerin sırası önceliği belirler; en az bir dil seçili olmalı.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Selected languages first (in priority order), then the rest alphabetically.
    private var sortedLanguages: [String] {
        let selected = settings.ocrLanguages.filter(supported.contains)
        let rest = supported.filter { !selected.contains($0) }.sorted { name(for: $0) < name(for: $1) }
        return selected + rest
    }

    private func name(for code: String) -> String {
        locale.localizedString(forIdentifier: code)?.capitalized(with: locale) ?? code
    }

    private func binding(for code: String) -> Binding<Bool> {
        Binding(
            get: { settings.ocrLanguages.contains(code) },
            set: { on in
                if on {
                    if !settings.ocrLanguages.contains(code) { settings.ocrLanguages.append(code) }
                } else if settings.ocrLanguages.count > 1 {
                    settings.ocrLanguages.removeAll { $0 == code }
                }
            })
    }
}
