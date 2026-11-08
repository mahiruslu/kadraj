import CoreGraphics
import Testing
@testable import KadrajCore

@Test func convertsCGToAppKitOnPrimary() {
    #expect(ScreenCoordinates.appKitRect(fromCG: CGRect(x: 100, y: 0, width: 200, height: 50), primaryScreenHeight: 900)
        == CGRect(x: 100, y: 850, width: 200, height: 50))
}

@Test func convertsSecondaryScreenAbovePrimary() {
    #expect(ScreenCoordinates.appKitRect(fromCG: CGRect(x: 0, y: -1080, width: 1920, height: 1080), primaryScreenHeight: 900)
        == CGRect(x: 0, y: 900, width: 1920, height: 1080))
}
