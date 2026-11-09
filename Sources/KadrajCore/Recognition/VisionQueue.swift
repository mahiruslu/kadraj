import Foundation

/// Runs Vision requests one at a time on a private serial queue. Concurrent
/// VNRecognizeTextRequest calls can fail while the on-device model loads (e5rtError), and
/// long OCR runs shouldn't block a thread of Swift's shared task pool.
final class VisionQueue: Sendable {
    static let shared = VisionQueue()
    private let queue = DispatchQueue(label: "app.kadraj.vision", qos: .userInitiated)

    func run<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try body() }) }
        }
    }
}
