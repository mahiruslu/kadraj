import Foundation

public struct CaptureSettings: Codable, Equatable, Sendable {
    public var saveDirectory: URL
    public var format: ImageFormat
    public var saveToFile: Bool
    public var copyToClipboard: Bool
    public var showQuickAccess: Bool
    public var includeWindowShadow: Bool
    public var showLoupe: Bool
    /// false: the selection stays after release and is confirmed with Return / double-click (iShot style).
    public var captureOnRelease: Bool
    public var hotkeys: [HotkeyAction: Hotkey]
    /// Vision language codes in priority order.
    public var ocrLanguages: [String]
    public var colorFormat: ColorFormat

    public static func defaults(home: URL) -> CaptureSettings {
        CaptureSettings(
            saveDirectory: home.appendingPathComponent("Pictures/Kadraj", isDirectory: true),
            format: .png,
            saveToFile: true,
            copyToClipboard: true,
            showQuickAccess: true,
            includeWindowShadow: true,
            showLoupe: true,
            captureOnRelease: false,
            hotkeys: Hotkey.defaults,
            ocrLanguages: ["tr-TR", "en-US"],
            colorFormat: .hex
        )
    }

    public init(saveDirectory: URL, format: ImageFormat, saveToFile: Bool, copyToClipboard: Bool,
                showQuickAccess: Bool, includeWindowShadow: Bool, showLoupe: Bool,
                captureOnRelease: Bool, hotkeys: [HotkeyAction: Hotkey], ocrLanguages: [String],
                colorFormat: ColorFormat) {
        self.saveDirectory = saveDirectory
        self.format = format
        self.saveToFile = saveToFile
        self.copyToClipboard = copyToClipboard
        self.showQuickAccess = showQuickAccess
        self.includeWindowShadow = includeWindowShadow
        self.showLoupe = showLoupe
        self.captureOnRelease = captureOnRelease
        self.hotkeys = hotkeys
        self.ocrLanguages = ocrLanguages
        self.colorFormat = colorFormat
    }

    /// Decodes stored settings; keys missing from older versions fall back to defaults.
    public static func decode(_ data: Data, home: URL) throws -> CaptureSettings {
        let decoder = JSONDecoder()
        decoder.userInfo[.kadrajHome] = home
        return try decoder.decode(CaptureSettings.self, from: data)
    }

    private enum CodingKeys: String, CodingKey {
        case saveDirectory, format, saveToFile, copyToClipboard, showQuickAccess,
             includeWindowShadow, showLoupe, captureOnRelease, hotkeys, ocrLanguages, colorFormat
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
        captureOnRelease = try c.decodeIfPresent(Bool.self, forKey: .captureOnRelease) ?? d.captureOnRelease
        // Stored null = cleared by the user; absent = action added in a later version → default.
        // Keys are decoded as strings so an action from a newer version (after a downgrade)
        // doesn't discard every stored shortcut.
        let raw = (try? c.decodeIfPresent([String: Hotkey?].self, forKey: .hotkeys)) ?? [:]
        var stored: [HotkeyAction: Hotkey?] = [:]
        for (key, value) in raw { if let action = HotkeyAction(rawValue: key) { stored[action] = value } }
        var merged: [HotkeyAction: Hotkey] = [:]
        for (action, value) in stored { if let value { merged[action] = value } }
        // New actions get their default only if the user hasn't already put that combo elsewhere.
        for (action, hotkey) in d.hotkeys where stored[action] == nil && !merged.values.contains(hotkey) {
            merged[action] = hotkey
        }
        hotkeys = merged
        let languages = (try? c.decodeIfPresent([String].self, forKey: .ocrLanguages)) ?? nil
        ocrLanguages = (languages?.isEmpty == false ? languages : nil) ?? d.ocrLanguages
        colorFormat = (try? c.decodeIfPresent(ColorFormat.self, forKey: .colorFormat)) ?? nil ?? d.colorFormat
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(saveDirectory, forKey: .saveDirectory)
        try c.encode(format, forKey: .format)
        try c.encode(saveToFile, forKey: .saveToFile)
        try c.encode(copyToClipboard, forKey: .copyToClipboard)
        try c.encode(showQuickAccess, forKey: .showQuickAccess)
        try c.encode(includeWindowShadow, forKey: .includeWindowShadow)
        try c.encode(showLoupe, forKey: .showLoupe)
        try c.encode(captureOnRelease, forKey: .captureOnRelease)
        // Write every known action so a cleared shortcut is stored as null, not as "missing".
        var all: [HotkeyAction: Hotkey?] = [:]
        for action in HotkeyAction.allCases { all[action] = .some(hotkeys[action]) }
        try c.encode(all, forKey: .hotkeys)
        try c.encode(ocrLanguages, forKey: .ocrLanguages)
        try c.encode(colorFormat, forKey: .colorFormat)
    }
}

public extension CodingUserInfoKey {
    static let kadrajHome = CodingUserInfoKey(rawValue: "kadrajHome")!
}
