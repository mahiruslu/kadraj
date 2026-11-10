import AppKit
import CryptoKit
import KadrajCore
import Security

/// Manual update check ("Güncellemeleri Kontrol Et") and in-place, admin-free install:
/// the app lives in a folder the user can write to, so the bundle can simply be replaced.
@MainActor
final class Updater {
    static let latestURL = URL(string: "https://api.github.com/repos/mahiruslu/kadraj/releases/latest")!
    static let nightlyURL = URL(string: "https://api.github.com/repos/mahiruslu/kadraj/releases/tags/nightly")!
    static let installCommand = "curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash"
    private let toast: ResultToastController
    private let isRecording: () -> Bool
    private var busy = false

    init(toast: ResultToastController, isRecording: @escaping () -> Bool) {
        self.toast = toast
        self.isRecording = isRecording
    }

    /// Stable builds look for a newer release and offer the nightly channel; nightly (and local
    /// dev) builds look for a newer nightly and offer the way back to the stable release.
    ///
    /// `silent` (the automatic daily check) only speaks up when there is something to install:
    /// no "up to date", no errors, no rate-limit notices. `completion` gets whether GitHub answered.
    func check(silent: Bool = false, completion: @escaping (Bool) -> Void = { _ in }) {
        guard !busy else { return completion(false) }
        let info = AppInfo(infoDictionary: Bundle.main.infoDictionary)
        guard let current = SemanticVersion(info.version) else { return completion(false) }
        // A local build has nothing to compare against: never nag it automatically.
        if silent, current.isDevelopment, !current.isNightly { return completion(false) }
        busy = true
        Task {
            defer { busy = false }
            do {
                if current.isDevelopment {
                    try await checkNightly(current: current, silent: silent)
                } else {
                    try await checkStable(current: current, silent: silent)
                }
                completion(true)
            } catch {
                if !silent {
                    toast.show(symbol: "exclamationmark.triangle", title: String(localized: "Couldn't check for updates"),
                               detail: error.localizedDescription)
                }
                completion(false)
            }
        }
    }

    private static let lastCheckKey = "lastAutomaticUpdateCheck"

    /// The daily background check: runs if enabled and a day has passed since the last one
    /// that reached GitHub (offline attempts are simply retried later).
    func checkAutomaticallyIfDue(enabled: Bool) {
        guard enabled, !isRecording() else { return }
        let defaults = UserDefaults.standard
        let last = defaults.object(forKey: Self.lastCheckKey) as? Date
        guard UpdateSchedule.isDue(lastCheck: last, now: Date()) else { return }
        check(silent: true) { reached in
            if reached { defaults.set(Date(), forKey: Self.lastCheckKey) }
        }
    }

    private func checkStable(current: SemanticVersion, silent: Bool) async throws {
        guard let release = try await fetch(Self.latestURL, silent: silent) else { return }
        if release.version > current {
            toast.show(symbol: "arrow.down.circle", title: String(localized: "Kadraj \(release.version.label) is available"),
                       detail: String(localized: "You're on \(current.label)."),
                       actions: [ToastAction(title: String(localized: "Update")) { self.install(release) }]) // app-lifetime object
        } else if !silent {
            toast.show(symbol: "checkmark.circle", title: String(localized: "Kadraj is up to date"), detail: String(localized: "Version \(current.label)"),
                       actions: [ToastAction(title: String(localized: "Switch to Nightly")) { self.switchChannel(to: Self.nightlyURL) }])
        }
    }

    private func checkNightly(current: SemanticVersion, silent: Bool) async throws {
        let toStable = ToastAction(title: String(localized: "Switch to Stable")) { self.switchChannel(to: Self.latestURL) }
        guard let nightly = try await fetch(Self.nightlyURL, silent: silent) else { return }
        if !current.isNightly {
            // A local build: nothing to compare, just offer both channels.
            toast.show(symbol: "hammer", title: String(localized: "You're using a development build"),
                       detail: String(localized: "Latest nightly: \(nightly.version.label)"),
                       actions: [ToastAction(title: String(localized: "Switch to Nightly")) { self.install(nightly) }, toStable])
        } else if nightly.version != current {
            toast.show(symbol: "hammer", title: String(localized: "A new nightly is available"),
                       detail: String(localized: "\(nightly.version.label) · you're on \(current.label)."),
                       actions: [ToastAction(title: String(localized: "Update")) { self.install(nightly) }, toStable])
        } else if !silent {
            toast.show(symbol: "hammer", title: String(localized: "Nightly is up to date"), detail: current.label, actions: [toStable])
        }
    }

    /// Installs the release behind `url` whatever its version: moving between the stable and
    /// the nightly channel is a deliberate choice, not an "update".
    private func switchChannel(to url: URL) {
        guard !busy else { return }
        busy = true
        Task {
            do {
                let release = try await fetch(url)
                busy = false
                if let release { install(release) }
            } catch {
                busy = false
                toast.show(symbol: "exclamationmark.triangle", title: String(localized: "Couldn't get release info"),
                           detail: error.localizedDescription)
            }
        }
    }

    /// GitHub release metadata; `nil` after telling the user why (none published, rate limit).
    private func fetch(_ url: URL, silent: Bool = false) async throws -> ReleaseInfo? {
        var request = URLRequest(url: url)
        request.setValue("Kadraj-Updater", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: break
        case 404:
            if !silent { toast.show(symbol: "arrow.down.circle", title: String(localized: "No published release found"), detail: nil) }
            return nil
        case 403, 429:
            if !silent {
                toast.show(symbol: "clock", title: String(localized: "GitHub rate limit reached"),
                           detail: String(localized: "Try again in a little while."))
            }
            return nil
        case let code:
            throw UpdateError.http(code)
        }
        guard let release = ReleaseInfo.parse(data) else { throw URLError(.cannotParseResponse) }
        return release
    }

    private func install(_ release: ReleaseInfo) {
        guard !busy else { return }
        let app = Bundle.main.bundleURL
        guard !isRecording() else {
            toast.show(symbol: "record.circle", title: String(localized: "Stop the recording first"), detail: String(localized: "Kadraj can't update while recording."))
            return
        }
        guard Self.isDeveloperIDSigned() else {
            // Ad-hoc builds (forks, local) have no signing identity to check an update against.
            toast.show(symbol: "lock", title: String(localized: "This build can't update itself"),
                       detail: String(localized: "You're using an unsigned build; run the install command to get the official release."),
                       actions: [copyAction(Self.installCommand)])
            return
        }
        guard EditorWindowController.confirmCloseAll() else { return }
        let folder = app.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            toast.show(symbol: "lock", title: String(localized: "Can't write to this location"),
                       detail: String(localized: "Kadraj is in \(folder.path); run the install command to update."),
                       actions: [copyAction(Self.installCommand)])
            return
        }
        busy = true
        toast.show(symbol: "arrow.down.circle", title: String(localized: "Updating…"), detail: "Kadraj \(release.version.label)")
        Task {
            defer { busy = false }
            do {
                try await Self.download(release, replacing: app)
                Self.relaunchAfterExit(app)
            } catch {
                toast.show(symbol: "exclamationmark.triangle", title: String(localized: "Update failed"),
                           detail: String(localized: "\(error.localizedDescription) The current version was not changed."))
            }
        }
    }

    /// Download → verify SHA-256 → unzip → swap bundles (the old one is restored on failure).
    @concurrent nonisolated private static func download(_ release: ReleaseInfo, replacing app: URL) async throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("kadraj-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let (zipTemp, zipResponse) = try await URLSession.shared.download(from: release.zipURL)
        try requireOK(zipResponse)
        let zip = work.appendingPathComponent("Kadraj.zip")
        try fm.moveItem(at: zipTemp, to: zip)
        let (sumData, sumResponse) = try await URLSession.shared.data(from: release.checksumURL)
        try requireOK(sumResponse)
        guard let expected = ReleaseInfo.expectedChecksum(from: String(decoding: sumData, as: UTF8.self)) else {
            throw URLError(.cannotParseResponse)
        }
        let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        guard actual == expected else { throw UpdateError.checksumMismatch }

        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", zip.path, work.path]
        try ditto.run()
        ditto.waitUntilExit()
        let fresh = work.appendingPathComponent("Kadraj.app")
        guard ditto.terminationStatus == 0, fm.fileExists(atPath: fresh.path) else { throw UpdateError.badArchive }
        try verify(fresh, expected: release.version)

        // Atomic exchange: the app path always holds a complete bundle, even if we crash here.
        let folder = app.deletingLastPathComponent()
        let staged = folder.appendingPathComponent(".Kadraj.app.new-\(UUID().uuidString)")
        try fm.copyItem(at: fresh, to: staged)
        guard renamex_np(staged.path, app.path, UInt32(RENAME_SWAP)) == 0 else {
            let code = errno
            try? fm.removeItem(at: staged)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        try? fm.removeItem(at: staged) // now holds the previous version
    }

    nonisolated private static func requireOK(_ response: URLResponse) throws {
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw UpdateError.http(code) }
    }

    /// Removes bundles left behind by an interrupted update.
    nonisolated static func sweepLeftovers() {
        let folder = Bundle.main.bundleURL.deletingLastPathComponent()
        let items = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in items where name.hasPrefix(".Kadraj.app.new-") || name.hasPrefix(".Kadraj.app.old-") {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    /// The running app must carry an Apple-anchored (Developer ID) designated requirement.
    nonisolated static func isDeveloperIDSigned() -> Bool {
        guard let requirement = try? runningRequirement() else { return false }
        var text: CFString?
        SecRequirementCopyString(requirement, [], &text)
        return (text as String?)?.contains("anchor apple") == true
    }

    nonisolated private static func runningRequirement() throws -> SecRequirement {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement
        else { throw UpdateError.signatureMismatch }
        return requirement
    }

    /// The downloaded bundle must satisfy the running app's designated requirement (same
    /// Developer ID team and bundle id), be intact, and be exactly the advertised version.
    /// A checksum from the same server alone wouldn't stop a tampered release.
    nonisolated private static func verify(_ bundle: URL, expected version: SemanticVersion) throws {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &staticCode) == errSecSuccess, let staticCode else {
            throw UpdateError.signatureMismatch
        }
        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(staticCode, flags, try runningRequirement()) == errSecSuccess else {
            throw UpdateError.signatureMismatch
        }
        let info = NSDictionary(contentsOf: bundle.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              let shipped = (info?["CFBundleShortVersionString"] as? String).flatMap(SemanticVersion.init),
              shipped == version else { throw UpdateError.versionMismatch }
    }

    /// Starts the new copy only after this process has exited, so two instances never run at once.
    private static func relaunchAfterExit(_ app: URL) {
        let waiter = Process()
        waiter.executableURL = URL(fileURLWithPath: "/bin/sh")
        waiter.arguments = ["-c", "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", app.path]
        try? waiter.run()
        NSApp.terminate(nil)
    }

    private func copyAction(_ command: String) -> ToastAction {
        ToastAction(title: String(localized: "Copy Command")) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }

    enum UpdateError: LocalizedError {
        case checksumMismatch, badArchive, signatureMismatch, versionMismatch, http(Int)
        var errorDescription: String? {
            switch self {
            case .checksumMismatch: String(localized: "The downloaded file couldn't be verified (SHA-256 mismatch).")
            case .badArchive: String(localized: "The downloaded archive couldn't be opened.")
            case .signatureMismatch: String(localized: "The downloaded version isn't signed by the Kadraj developer.")
            case .versionMismatch: String(localized: "The downloaded package isn't the expected version.")
            case .http(let code): String(localized: "The server returned an unexpected response (HTTP \(code)).")
            }
        }
    }
}

extension SemanticVersion {
    var text: String { "\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "") }
    /// "0.1.3", "Nightly 40a4055", String(localized: "development build").
    var label: String {
        if isNightly, let commit = prerelease?.split(separator: ".").last { return "Nightly \(commit)" }
        return isDevelopment ? String(localized: "development build") : text
    }
}
