import AppKit
import CryptoKit
import KadrajCore

/// Manual update check ("Güncellemeleri Kontrol Et") and in-place, admin-free install:
/// the app lives in a folder the user can write to, so the bundle can simply be replaced.
@MainActor
final class Updater {
    static let latestURL = URL(string: "https://api.github.com/repos/mahiruslu/kadraj/releases/latest")!
    static let installCommand = "curl -fsSL https://raw.githubusercontent.com/mahiruslu/kadraj/main/install.sh | bash"
    private let toast: ResultToastController
    private var busy = false

    init(toast: ResultToastController) { self.toast = toast }

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
                if (response as? HTTPURLResponse)?.statusCode == 404 {
                    toast.show(symbol: "arrow.down.circle", title: "Yayınlanmış sürüm bulunamadı", detail: nil)
                    return
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
        let app = Bundle.main.bundleURL
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
                Relauncher.relaunch()
            } catch {
                toast.show(symbol: "exclamationmark.triangle", title: "Güncelleme başarısız",
                           detail: "\(error.localizedDescription) Mevcut sürüm değiştirilmedi.")
            }
        }
    }

    /// Download → verify SHA-256 → unzip → swap bundles (the old one is restored on failure).
    nonisolated private static func download(_ release: ReleaseInfo, replacing app: URL) async throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("kadraj-update-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let (zipTemp, _) = try await URLSession.shared.download(from: release.zipURL)
        let zip = work.appendingPathComponent("Kadraj.zip")
        try fm.moveItem(at: zipTemp, to: zip)
        let (sumData, _) = try await URLSession.shared.data(from: release.checksumURL)
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

        let folder = app.deletingLastPathComponent()
        let staged = folder.appendingPathComponent(".Kadraj.app.new-\(UUID().uuidString)")
        let old = folder.appendingPathComponent(".Kadraj.app.old-\(UUID().uuidString)")
        try fm.copyItem(at: fresh, to: staged)
        do {
            try fm.moveItem(at: app, to: old)
        } catch {
            try? fm.removeItem(at: staged)
            throw error
        }
        do {
            try fm.moveItem(at: staged, to: app)
        } catch {
            try? fm.moveItem(at: old, to: app)
            try? fm.removeItem(at: staged)
            throw error
        }
        try? fm.removeItem(at: old)
    }

    private func copyAction(_ command: String) -> ToastAction {
        ToastAction(title: "Komutu Kopyala") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(command, forType: .string)
        }
    }

    enum UpdateError: LocalizedError {
        case checksumMismatch, badArchive
        var errorDescription: String? {
            switch self {
            case .checksumMismatch: "İndirilen dosya doğrulanamadı (SHA-256 uyuşmuyor)."
            case .badArchive: "İndirilen arşiv açılamadı."
            }
        }
    }
}

extension SemanticVersion {
    var text: String { "\(major).\(minor).\(patch)" + (prerelease.map { "-\($0)" } ?? "") }
}
