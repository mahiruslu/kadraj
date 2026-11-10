import AppKit

/// The system's own "screen capture" sound, played when a screenshot is taken or a recording is
/// saved (Settings → "Play capture sound"). Recordings never contain it: Kadraj's own audio is
/// excluded from the stream.
@MainActor
enum CaptureSound {
    private static let sound: NSSound? = NSSound(
        contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/system/Screen Capture.aif",
        byReference: true) ?? NSSound(named: "Tink")

    static func play(if enabled: Bool) {
        guard enabled, let sound else { return }
        sound.stop() // rapid captures restart it instead of being dropped
        sound.play()
    }
}
