import AppKit
import AVFoundation
import CoreMedia
import KadrajCore

/// Owns the active recording, the menu bar indicator state and the result toast.
@MainActor
final class RecordingController {
    private var session: RecordingSession?
    private(set) var startedAt: Date?
    private let toast: ResultToastController
    private let settings: () -> CaptureSettings
    var onStateChange: (Bool) -> Void = { _ in }

    init(toast: ResultToastController, settings: @escaping () -> CaptureSettings) {
        self.toast = toast
        self.settings = settings
    }

    var isRecording: Bool { session != nil }

    var elapsedText: String {
        guard let startedAt else { return "" }
        let s = Int(Date().timeIntervalSince(startedAt))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    func start(region: CGRect, screen: NSScreen) async throws {
        let settings = settings()
        try FileManager.default.createDirectory(at: settings.saveDirectory, withIntermediateDirectories: true)
        let name = FileNamer.fileName(date: Date(), ext: "mp4", prefix: String(localized: "Kadraj Recording"))
        let url = FileNamer.uniqueURL(directory: settings.saveDirectory, fileName: name) {
            FileManager.default.fileExists(atPath: $0.path)
        }
        let audio = await audioOptions(settings)
        let session = try await RecordingSession.start(region: region, screen: screen, url: url, audio: audio) { [weak self] in
            Task { @MainActor in
                // Only stop if this is still the current recording (identified by its file).
                if let self, self.session?.url == url { self.stop() }
            }
        }
        self.session = session
        startedAt = Date()
        onStateChange(true)
    }

    /// The sound to record. A refused microphone doesn't block the recording: it goes ahead
    /// without it and says how to allow it.
    private func audioOptions(_ settings: CaptureSettings) async -> RecordingAudio {
        var audio = RecordingAudio(system: settings.recordSystemAudio)
        guard settings.recordMicrophone, #available(macOS 15.0, *) else { return audio }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: audio.microphone = true
        case .notDetermined: audio.microphone = await AVCaptureDevice.requestAccess(for: .audio)
        default: audio.microphone = false
        }
        if !audio.microphone {
            toast.show(symbol: "mic.slash", title: String(localized: "Recording without the microphone"),
                       detail: String(localized: "Allow Kadraj in System Settings → Privacy & Security → Microphone."),
                       actions: [ToastAction(title: String(localized: "Open System Settings")) {
                           NSWorkspace.shared.open(SystemSettingsLink.microphone)
                       }])
        }
        return audio
    }

    func stop() {
        Task { await stopAndWait() }
    }

    /// Finalizes the file (also used when quitting, so the MP4 stays playable).
    func stopAndWait() async {
        guard let session else { return }
        let endTime = CMClockGetTime(CMClockGetHostTimeClock()) // before any await
        let elapsed = elapsedText
        self.session = nil
        startedAt = nil
        onStateChange(false)
        do {
            let url = try await session.stop(endTime: endTime)
            showResult(url, elapsed: elapsed)
        } catch {
            RecognitionOutput.showError(error.localizedDescription, toast: toast)
        }
    }

    private func showResult(_ url: URL, elapsed: String) {
        toast.show(symbol: "record.circle", title: String(localized: "Recording saved (\(elapsed))"), detail: url.lastPathComponent, actions: [
            ToastAction(title: String(localized: "Open")) { NSWorkspace.shared.open(url) },
            ToastAction(title: String(localized: "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([url]) },
            ToastAction(title: String(localized: "Convert to GIF")) { [weak self] in self?.exportGIF(url) },
        ])
    }

    private func exportGIF(_ url: URL) {
        toast.show(symbol: "photo.stack", title: String(localized: "Preparing GIF…"), detail: url.lastPathComponent, sticky: true)
        Task {
            do {
                let gif = try await GIFExporter.export(url)
                toast.show(symbol: "photo.stack", title: String(localized: "GIF ready"), detail: gif.lastPathComponent, actions: [
                    ToastAction(title: String(localized: "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([gif]) },
                ])
            } catch {
                NSLog("Kadraj: GIF export failed: \(error)")
                RecognitionOutput.showError(error.localizedDescription, toast: toast)
            }
        }
    }
}
