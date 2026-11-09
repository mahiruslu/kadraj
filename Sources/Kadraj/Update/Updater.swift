import AppKit
import CryptoKit
import KadrajCore
import Security

/// Manual update check ("Güncellemeleri Kontrol Et") and in-place, admin-free install:
/// the app lives in a folder the user can write to, so the bundle can simply be replaced.
@MainActor
final class Updater {
    static let latestURL = URL(string: "https://api.github.com/repos/mahiruslu/kadraj/releases/latest")!
    static let installCommand = "curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash"
    private let toast: ResultToastController
    private let isRecording: () -> Bool
    private var busy = false

    init(toast: ResultToastController, isRecording: @escaping () -> Bool) {
        self.toast = toast
        self.isRecording = isRecording
    }

    func check() {
        guard !busy else { return }
        let info = AppInfo(infoDictionary: Bundle.main.infoDictionary)
        guard let current = SemanticVersion(info.version), !current.isDevelopment else {
            toast.show(symbol: "hammer", title: "Geliştirme sürümü kullanıyorsunuz",
                       detail: "Son geliştirme sürümü için: …install.sh | bash -s -- main",
                       actions: [copyAction(Self.installCommand + " -s -- main")])
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                var request = URLRequest(url: Self.latestURL)
                request.setValue("Kadraj-Updater", forHTTPHeaderField: "User-Agent")
                request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
                case 200: break
                case 404:
                    toast.show(symbol: "arrow.down.circle", title: "Yayınlanmış sürüm bulunamadı", detail: nil)
                    return
                case 403, 429:
                    toast.show(symbol: "clock", title: "GitHub istek sınırına ulaşıldı",
                               detail: "Biraz sonra tekrar deneyin.")
                    return
                case let code:
                    throw UpdateError.http(code)
                }
                guard let release = ReleaseInfo.parse(data) else { throw URLError(.cannotParseResponse) }
                if release.version > current {
                    toast.show(symbol: "arrow.down.circle", title: "Kadraj \(release.version.text) mevcut",
                               detail: "Şu an \(info.version) kullanıyorsunuz.",
                               actions: [ToastAction(title: "Güncelle") { self.install(release) }]) // app-lifetime object
                } else {
                    toast.show(symbol: "checkmark.circle", title: "Kadraj güncel", detail: "Sürüm \(info.version)")
                }
            } catch {
                toast.show(symbol: "exclamationmark.triangle", title: "Güncelleme kontrol edilemedi",
                           detail: error.localizedDescription)
            }
        }
    }

    private func install(_ release: ReleaseInfo) {
        guard !busy else { return }
        let app = Bundle.main.bundleURL
        guard !isRecording() else {
            toast.show(symbol: "record.circle", title: "Önce kaydı durdurun", detail: "Kayıt sürerken güncellenemez.")
            return
        }
        guard Self.isDeveloperIDSigned() else {
            // Ad-hoc builds (forks, local) have no signing identity to check an update against.
            toast.show(symbol: "lock", title: "Bu derleme kendini güncelleyemez",
                       detail: "İmzasız bir derleme kullanıyorsunuz; resmi sürüm için kurulum komutunu çalıştırın.",
                       actions: [copyAction(Self.installCommand)])
            return
        }
        guard EditorWindowController.confirmCloseAll() else { return }
        let folder = app.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            toast.show(symbol: "lock", title: "Bu konuma yazılamıyor",
                       detail: "Kadraj \(folder.path) içinde; güncellemek için kurulum komutunu çalıştırın.",
                       actions: [copyAction(Self.installCommand)])
            return
        }
        busy = true
        toast.show(symbol: "arrow.down.circle", title: "Güncelleniyor…", detail: "Kadraj \(release.version.text)")
        Task {
            defer { busy = false }
            do {
                try await Self.download(release, replacing: app)
                Self.relaunchAfterExit(app)
            } catch {
                toast.show(symbol: "exclamationmark.triangle", title: "Güncelleme başarısız",
                           detail: "\(error.localizedDescription) Mevcut sürüm değiştirilmedi.")
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
        ToastAction(title: "Komutu Kopyala") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }

    enum UpdateError: LocalizedError {
        case checksumMismatch, badArchive, signatureMismatch, versionMismatch, http(Int)
        var errorDescription: String? {
            switch self {
            case .checksumMismatch: "İndirilen dosya doğrulanamadı (SHA-256 uyuşmuyor)."
            case .badArchive: "İndirilen arşiv açılamadı."
            case .signatureMismatch: "İndirilen sürümün imzası Kadraj geliştiricisine ait değil."
            case .versionMismatch: "İndirilen paket beklenen sürüm değil."
            case .http(let code): "Sunucu beklenmeyen bir yanıt verdi (HTTP \(code))."
            }
        }
    }
}

extension SemanticVersion {
    var text: String { "\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "") }
}
