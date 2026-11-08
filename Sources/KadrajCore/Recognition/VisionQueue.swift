import Foundation

/// Runs Vision requests one at a time. Concurrent VNRecognizeTextRequest calls can fail
/// while the on-device model is being loaded (e5rtError), e.g. two "Copy Text" clicks at once.
actor VisionQueue {
    static let shared = VisionQueue()

    func run<T: Sendable>(_ body: @Sendable () throws -> T) throws -> T {
        try body()
    }
}
