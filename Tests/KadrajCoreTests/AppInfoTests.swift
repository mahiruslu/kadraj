import Testing
@testable import KadrajCore

@Test func readsVersionAndBuild() {
    let info = AppInfo(infoDictionary: ["CFBundleShortVersionString": "1.2.0", "CFBundleVersion": "42"])
    #expect(info.version == "1.2.0")
    #expect(info.build == "42")
    #expect(info.displayString == "Kadraj 1.2.0 (42)")
}

@Test func fallsBackToDev() {
    #expect(AppInfo(infoDictionary: nil).displayString == "Kadraj dev (0)")
    #expect(AppInfo(infoDictionary: [:]).version == "dev")
}
