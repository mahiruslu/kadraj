import Foundation

/// `MAJOR.MINOR.PATCH[-prerelease]`, optional leading `v`. A prerelease sorts before its release.
public struct SemanticVersion: Comparable, Hashable, Sendable {
    public let major: Int, minor: Int, patch: Int
    public let prerelease: String?

    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        let parts = s.split(separator: "-", maxSplits: 1).map(String.init)
        guard let core = parts.first else { return nil }
        let numbers = core.split(separator: ".").map { Int($0) }
        guard (1...3).contains(numbers.count), numbers.allSatisfy({ $0 != nil }) else { return nil }
        let n = numbers.map { $0! } + Array(repeating: 0, count: 3 - numbers.count)
        major = n[0]; minor = n[1]; patch = n[2]
        prerelease = parts.count > 1 ? parts[1] : nil
    }

    /// Local builds and nightlies (version 0.0.0-…) are not compared against releases.
    public var isDevelopment: Bool { major == 0 && minor == 0 && patch == 0 && prerelease != nil }

    public static func < (a: SemanticVersion, b: SemanticVersion) -> Bool {
        if (a.major, a.minor, a.patch) != (b.major, b.minor, b.patch) {
            return (a.major, a.minor, a.patch) < (b.major, b.minor, b.patch)
        }
        switch (a.prerelease, b.prerelease) {
        case (nil, nil): return false
        case (nil, _): return false
        case (_, nil): return true
        case let (x?, y?): return x.compare(y, options: .numeric) == .orderedAscending
        }
    }
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
        let assets: [Asset]
    }

    public static func parse(_ data: Data) -> ReleaseInfo? {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let version = SemanticVersion(payload.tag_name),
              let zip = payload.assets.first(where: { $0.name == "Kadraj.zip" })?.browser_download_url,
              let sum = payload.assets.first(where: { $0.name == "Kadraj.zip.sha256" })?.browser_download_url
        else { return nil }
        return ReleaseInfo(version: version, zipURL: zip, checksumURL: sum)
    }

    /// First field of a `shasum -a 256` line.
    public static func expectedChecksum(from text: String) -> String? {
        text.split(whereSeparator: \.isWhitespace).first.map { String($0).lowercased() }
    }
}
