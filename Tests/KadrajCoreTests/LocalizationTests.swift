import Foundation
import Testing

// The UI is written in English; Resources/tr.lproj holds the Turkish translation.
// These checks keep the two in step: a new string without a translation, or a translation
// whose placeholders don't match its key, fails here instead of showing up in the app.

private let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

private func turkish() throws -> [String: String] {
    let url = root.appendingPathComponent("Resources/tr.lproj/Localizable.strings")
    return try #require(NSDictionary(contentsOf: url) as? [String: String])
}

private let specifier = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?(@|lld|ld|d|lf|f)"#)

/// Placeholder types in argument order (positional `%2$@` is put back in place).
private func placeholders(_ s: String) -> [String] {
    let ns = s as NSString
    let matches = specifier.matches(in: s, range: NSRange(location: 0, length: ns.length))
    return matches.enumerated().map { index, m -> (Int, String) in
        let position = m.range(at: 1).location == NSNotFound ? index + 1 : Int(ns.substring(with: m.range(at: 1)))!
        return (position, ns.substring(with: m.range(at: 2)))
    }.sorted { $0.0 < $1.0 }.map(\.1)
}

/// A Swift literal as a lookup pattern: every `\(…)` interpolation, and every format specifier
/// in a key, becomes the same marker.
private func normalized(swiftLiteral s: String) -> String {
    var out = "", chars = Array(s), i = 0
    while i < chars.count {
        if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == "(" {
            var depth = 1
            i += 2
            while i < chars.count, depth > 0 {
                if chars[i] == "(" { depth += 1 } else if chars[i] == ")" { depth -= 1 }
                i += 1
            }
            out += "§"
        } else if chars[i] == "\\", i + 1 < chars.count {
            out.append(chars[i + 1] == "n" ? "\n" : chars[i + 1])
            i += 2
        } else {
            out.append(chars[i])
            i += 1
        }
    }
    return out
}

private func normalized(key: String) -> String {
    specifier.stringByReplacingMatches(in: key, range: NSRange(location: 0, length: (key as NSString).length), withTemplate: "§")
}

/// Strings the app looks up: `String(localized:)` and the SwiftUI initializers that take a
/// LocalizedStringKey literal.
private func localizedLiterals() throws -> Set<String> {
    let literal = #""((?:[^"\\]|\\.)*)""#
    let patterns = [
        #"String\(localized: "# + literal,
        #"\b(?:Text|Button|Toggle|Label|Section|LabeledContent|Picker)\("# + literal,
        #"\.help\("# + literal + #"\)"#,
    ].map { try! NSRegularExpression(pattern: $0) }
    var found: Set<String> = []
    let sources = root.appendingPathComponent("Sources")
    let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
        .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    for file in files {
        let text = try String(contentsOf: file, encoding: .utf8)
        let ns = text as NSString
        for pattern in patterns {
            for m in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let value = ns.substring(with: m.range(at: 1))
                if !value.isEmpty { found.insert(value) }
            }
        }
    }
    return found
}

@Test func everyUIStringHasATurkishTranslation() throws {
    let keys = Set(try turkish().keys.map(normalized(key:)))
    let missing = try localizedLiterals().filter { !keys.contains(normalized(swiftLiteral: $0)) }.sorted()
    #expect(missing.isEmpty, "Add to Resources/tr.lproj/Localizable.strings: \(missing)")
}

@Test func translationsKeepTheirPlaceholders() throws {
    for (key, value) in try turkish() {
        #expect(placeholders(key) == placeholders(value), "\(key) → \(value)")
    }
}

@Test func translationsAreNotStale() throws {
    let used = Set(try localizedLiterals().map(normalized(swiftLiteral:)))
    let stale = try turkish().keys.filter { !used.contains(normalized(key: $0)) }.sorted()
    #expect(stale.isEmpty, "Unused keys in Resources/tr.lproj/Localizable.strings: \(stale)")
}

@Test func translationKeysAreUnique() throws {
    // NSDictionary keeps the last of two equal keys silently; catch the duplicate instead.
    let text = try String(contentsOf: root.appendingPathComponent("Resources/tr.lproj/Localizable.strings"), encoding: .utf8)
    let keys = text.split(separator: "\n").compactMap { line -> String? in
        guard line.hasPrefix("\""), let end = line.range(of: "\" = \"") else { return nil }
        return String(line[line.index(after: line.startIndex)..<end.lowerBound])
    }
    let duplicates = Dictionary(grouping: keys, by: { $0 }).filter { $0.value.count > 1 }.keys.sorted()
    #expect(duplicates.isEmpty, "Duplicate keys: \(duplicates)")
}
