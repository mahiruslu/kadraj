import Foundation

public enum FileNamer {
    /// "Kadraj 2026-11-08 at 14.03.22.png"
    public static func fileName(date: Date, ext: String, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "Kadraj \(formatter.string(from: date)).\(ext)"
    }

    /// Returns `directory/fileName`, or `name (2).ext`, `name (3).ext`… if it is taken.
    public static func uniqueURL(directory: URL, fileName: String, exists: (URL) -> Bool) -> URL {
        let candidate = directory.appendingPathComponent(fileName)
        guard exists(candidate) else { return candidate }
        let base = (fileName as NSString).deletingPathExtension
        let ext = (fileName as NSString).pathExtension
        var n = 2
        while true {
            let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            let url = directory.appendingPathComponent(name)
            if !exists(url) { return url }
            n += 1
        }
    }
}
