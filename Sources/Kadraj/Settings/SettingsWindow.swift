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
            window.title = String(localized: "Kadraj Settings")
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
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutsTab(settings: $store.settings, status: status, recording: recording)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            RecognitionTab(settings: $store.settings)
                .tabItem { Label("Text Recognition", systemImage: "text.viewfinder") }
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
            Section("Saving") {
                LabeledContent("Folder") {
                    HStack {
                        Text(settings.saveDirectory.path(percentEncoded: false)
                            .replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundStyle(.secondary)
                        Button("Change…", action: chooseFolder)
                    }
                }
                Picker("Format", selection: $settings.format) {
                    Text(verbatim: "PNG").tag(ImageFormat.png)
                    Text(verbatim: "JPEG").tag(ImageFormat.jpeg)
                }
                .pickerStyle(.segmented)
            }
            Section("After capture") {
                Toggle("Save to file", isOn: $settings.saveToFile)
                Toggle("Copy to clipboard", isOn: $settings.copyToClipboard)
                Toggle("Show the Quick Access thumbnail", isOn: $settings.showQuickAccess)
            }
            Section("System") {
                Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                Toggle("Show in menu bar", isOn: $settings.showMenuBarIcon)
                if !settings.showMenuBarIcon {
                    Text("Shortcuts keep working. To get back to Settings, open Kadraj again from Applications or Spotlight.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if loginItem.needsApproval {
                    HStack {
                        Text("Waiting for approval in System Settings.").font(.caption).foregroundStyle(.secondary)
                        Button("Open") { loginItem.openSystemSettings() }.controlSize(.small)
                    }
                } else if let error = loginItem.error {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Capture") {
                Toggle("Include window shadow", isOn: $settings.includeWindowShadow)
                Toggle("Show the magnifier while selecting", isOn: $settings.showLoupe)
                Picker("Color format", selection: $settings.colorFormat) {
                    ForEach(ColorFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Capture on mouse release", isOn: $settings.captureOnRelease)
                    .help("When off, the selection stays on screen and is captured with Return, a double-click or ✓.")
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
        panel.prompt = String(localized: "Choose")
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
                Text("Click a shortcut and press the new key combination. Esc cancels, ⌫ clears.")
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
    // Computed once: building a Vision request on every settings change is wasteful.
    private static let supportedLanguages = TextRecognizer.supportedLanguages()
    private var supported: [String] { Self.supportedLanguages }
    /// Language names in the language the UI is shown in.
    private let locale = Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")

    var body: some View {
        Form {
            Section {
                List {
                    ForEach(selectedLanguages, id: \.self) { code in
                        Label(name(for: code), systemImage: "line.3.horizontal")
                    }
                    .onMove(perform: moveLanguages)
                }
                .frame(height: CGFloat(max(selectedLanguages.count, 1)) * 28 + 8)
            } header: {
                Text("Priority order (drag to reorder)")
            }
            Section {
                List {
                    ForEach(sortedLanguages, id: \.self) { code in
                        Toggle(name(for: code), isOn: binding(for: code))
                            .disabled(settings.ocrLanguages.filter(supported.contains) == [code])
                    }
                }
                .frame(height: 220)
            } header: {
                Text("Languages to recognize")
            } footer: {
                Text("Text recognition runs entirely on this Mac and never goes online. The order of the selected languages sets their priority; at least one must be selected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var selectedLanguages: [String] { settings.ocrLanguages.filter(supported.contains) }

    private func moveLanguages(from source: IndexSet, to destination: Int) {
        var selected = selectedLanguages
        selected.move(fromOffsets: source, toOffset: destination)
        settings.ocrLanguages = selected + settings.ocrLanguages.filter { !supported.contains($0) }
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
                } else if settings.ocrLanguages.filter(supported.contains).count > 1 {
                    settings.ocrLanguages.removeAll { $0 == code }
                }
            })
    }
}
