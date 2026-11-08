import Foundation
import Testing
@testable import KadrajCore

@Test func fileNameUsesTemplate() {
    var c = DateComponents()
    c.year = 2026; c.month = 11; c.day = 8; c.hour = 14; c.minute = 3; c.second = 22
    let tz = TimeZone(identifier: "Europe/Istanbul")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    #expect(FileNamer.fileName(date: cal.date(from: c)!, ext: "png", timeZone: tz)
        == "Kadraj 2026-11-08 at 14.03.22.png")
}

@Test func uniqueURLAppendsCounter() {
    let dir = URL(fileURLWithPath: "/tmp/x")
    let taken: Set<String> = ["a.png", "a (2).png"]
    #expect(FileNamer.uniqueURL(directory: dir, fileName: "a.png") { taken.contains($0.lastPathComponent) }
        .lastPathComponent == "a (3).png")
    #expect(FileNamer.uniqueURL(directory: dir, fileName: "b.png") { _ in false }.lastPathComponent == "b.png")
}
