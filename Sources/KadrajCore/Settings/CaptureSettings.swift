import Foundation

public struct CaptureSettings: Codable, Equatable, Sendable {
    public var saveDirectory: URL
    public var format: ImageFormat
    public var saveToFile: Bool
    public var copyToClipboard: Bool
    public var showQuickAccess: Bool
    public var includeWindowShadow: Bool
    public var showLoupe: Bool
    public var hotkeys: [HotkeyAction: Hotkey]

    public static func defaults(home: URL) -> CaptureSettings {
        CaptureSettings(
            saveDirectory: home.appendingPathComponent("Pictures/Kadraj", isDirectory: true),
            format: .png,
            saveToFile: true,
            copyToClipboard: true,
            showQuickAccess: true,
            includeWindowShadow: true,
            showLoupe: true,
            hotkeys: Hotkey.defaults
        )
    }

    public init(saveDirectory: URL, format: ImageFormat, saveToFile: Bool, copyToClipboard: Bool,
                showQuickAccess: Bool, includeWindowShadow: Bool, showLoupe: Bool,
                hotkeys: [HotkeyAction: Hotkey]) {
        self.saveDirectory = saveDirectory
        self.format = format
        self.saveToFile = saveToFile
        self.copyToClipboard = copyToClipboard
        self.showQuickAccess = showQuickAccess
        self.includeWindowShadow = includeWindowShadow
        self.showLoupe = showLoupe
        self.hotkeys = hotkeys
    }

    /// Decodes stored settings; keys missing from older versions fall back to defaults.
    public static func decode(_ data: Data, home: URL) throws -> CaptureSettings {
        let decoder = JSONDecoder()
        decoder.userInfo[.kadrajHome] = home
        return try decoder.decode(CaptureSettings.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case saveDirectory, format, saveToFile, copyToClipboard, showQuickAccess,
             includeWindowShadow, showLoupe, hotkeys
    }

    public init(from decoder: Decoder) throws {
        let home = decoder.userInfo[.kadrajHome] as? URL ?? FileManager.default.homeDirectoryForCurrentUser
        let d = CaptureSettings.defaults(home: home)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        saveDirectory = try c.decodeIfPresent(URL.self, forKey: .saveDirectory) ?? d.saveDirectory
        format = (try? c.decodeIfPresent(ImageFormat.self, forKey: .format)) ?? d.format
        saveToFile = try c.decodeIfPresent(Bool.self, forKey: .saveToFile) ?? d.saveToFile
        copyToClipboard = try c.decodeIfPresent(Bool.self, forKey: .copyToClipboard) ?? d.copyToClipboard
        showQuickAccess = try c.decodeIfPresent(Bool.self, forKey: .showQuickAccess) ?? d.showQuickAccess
        includeWindowShadow = try c.decodeIfPresent(Bool.self, forKey: .includeWindowShadow) ?? d.includeWindowShadow
        showLoupe = try c.decodeIfPresent(Bool.self, forKey: .showLoupe) ?? d.showLoupe
        // Actions added in later versions get their default shortcut.
        let stored = (try? c.decodeIfPresent([HotkeyAction: Hotkey].self, forKey: .hotkeys)) ?? [:]
        hotkeys = d.hotkeys.merging(stored) { _, new in new }
    }
}

public extension CodingUserInfoKey {
    static let kadrajHome = CodingUserInfoKey(rawValue: "kadrajHome")!
}
