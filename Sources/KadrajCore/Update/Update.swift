import Foundation

/// `MAJOR.MINOR.PATCH[-prerelease][+build]`, optional leading `v`, compared per SemVer 2.0:
/// build metadata is ignored, a prerelease sorts before its release, numeric identifiers
/// compare numerically and before alphanumeric ones.
public struct SemanticVersion: Comparable, Hashable, Sendable {
    public let major: Int, minor: Int, patch: Int
    /// Normalized identifiers (numeric ones without leading zeros); nil for a release.
    public let prerelease: String?

    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        if let plus = s.firstIndex(of: "+") { s = String(s[..<plus]) }
        let parts = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let core = parts.first else { return nil }
        let fields = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(fields.count),
              fields.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isASCIIDigit) }) else { return nil }
        let n = fields.compactMap { Int($0) } + Array(repeating: 0, count: 3 - fields.count)
        major = n[0]; minor = n[1]; patch = n[2]
        if parts.count > 1 {
            let ids = parts[1].split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            guard ids.allSatisfy({ !$0.isEmpty }) else { return nil }
            prerelease = ids.map { id in id.allSatisfy(\.isASCIIDigit) ? String(Int(id) ?? 0) : id }.joined(separator: ".")
        } else {
            prerelease = nil
        }
    }

    /// Local builds and nightlies (version 0.0.0-…) are not compared against releases.
    public var isDevelopment: Bool { major == 0 && minor == 0 && patch == 0 && prerelease != nil }
    /// A build from the nightly workflow (`0.0.0-nightly.<sha7>`), as opposed to a local dev build.
    public var isNightly: Bool { isDevelopment && prerelease?.hasPrefix("nightly.") == true }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) {
            return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
        }
        switch (a.prerelease, b.prerelease) {
        case (nil, _): return false
        case (_, nil): return true
        case let (x?, y?):
            let xs = x.split(separator: "."), ys = y.split(separator: ".")
            for (p, q) in zip(xs, ys) where p != q {
                switch (Int(p), Int(q)) {
                case let (i?, j?): return i < j
                case (_?, nil): return true   // numeric < alphanumeric
                case (nil, _?): return false
                default: return p < q
                }
            }
            return xs.count < ys.count
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

/// The parts of GitHub's `releases/latest` response the updater needs.
public struct ReleaseInfo: Equatable, Sendable {
    public let version: SemanticVersion
    public let zipURL: URL
    public let checksumURL: URL

    private struct Payload: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let target_commitish: String?
        let assets: [Asset]
    }

    /// The nightly release has a fixed tag; its version is the one the nightly workflow stamps
    /// into the bundle (`0.0.0-nightly.<sha7>`), taken from the commit it was built from.
    private static func version(of payload: Payload) -> SemanticVersion? {
        guard payload.tag_name == "nightly" else { return SemanticVersion(payload.tag_name) }
        guard let commit = payload.target_commitish, commit.count == 40,
              commit.allSatisfy(\.isHexDigit) else { return nil }
        return SemanticVersion("0.0.0-nightly.\(commit.prefix(7))")
    }

    public static func parse(_ data: Data) -> ReleaseInfo? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let version = version(of: payload),
              let zip = payload.assets.first(where: { $0.name == "Kadraj.zip" })?.browser_download_url,
              let sum = payload.assets.first(where: { $0.name == "Kadraj.zip.sha256" })?.browser_download_url,
              isOfficialAsset(zip, tag: payload.tag_name), isOfficialAsset(sum, tag: payload.tag_name)
        else { return nil }
        return ReleaseInfo(version: version, zipURL: zip, checksumURL: sum)
    }

    /// Downloads only from this repository's release of exactly this tag, over HTTPS.
    static func isOfficialAsset(_ url: URL, tag: String) -> Bool {
        url.scheme == "https" && url.host == "github.com"
            && url.path.hasPrefix("/mahiruslu/kadraj/releases/download/\(tag)/")
    }

    /// First field of a `shasum -a 256` line.
    public static func expectedChecksum(from text: String) -> String? {
        text.split(whereSeparator: \.isWhitespace).first.map { String($0).lowercased() }
    }
}

/// When the automatic update check runs: at most once a day.
public enum UpdateSchedule {
    public static let interval: TimeInterval = 24 * 60 * 60

    /// Due if it never ran, a day has passed, or the clock was set back past the last check.
    public static func isDue(lastCheck: Date?, now: Date, interval: TimeInterval = interval) -> Bool {
        guard let lastCheck else { return true }
        let elapsed = now.timeIntervalSince(lastCheck)
        return elapsed >= interval || elapsed < 0
    }
}
