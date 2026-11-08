import Foundation

/// Uygulamanın sürüm bilgisi (Info.plist'ten okunur).
public struct AppInfo: Equatable, Sendable {
    public let version: String
    public let build: String

    public init(infoDictionary: [String: Any]?) {
        version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        build = infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    public var displayString: String { "Kadraj \(version) (\(build))" }
}
