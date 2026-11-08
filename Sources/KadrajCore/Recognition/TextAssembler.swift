import Foundation
import CoreGraphics

/// One piece of recognized text. `box` is in Vision's normalized space (0…1, bottom-left origin).
public struct RecognizedFragment: Equatable, Sendable {
    public let text: String
    public let box: CGRect

    public init(text: String, box: CGRect) {
        self.text = text
        self.box = box
    }
}

/// Turns Vision's unordered observations into reading-order text.
public enum TextAssembler {
    public static func assemble(_ fragments: [RecognizedFragment]) -> String {
        let pieces = fragments
            .map { RecognizedFragment(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), box: $0.box) }
            .filter { !$0.text.isEmpty }
            .sorted { $0.box.midY > $1.box.midY }

        var lines: [[RecognizedFragment]] = []
        for piece in pieces {
            if let last = lines.last, let anchor = last.first {
                let tolerance = (anchor.box.height + piece.box.height) / 4 // half the average height
                if abs(anchor.box.midY - piece.box.midY) < tolerance {
                    lines[lines.count - 1].append(piece)
                    continue
                }
            }
            lines.append([piece])
        }
        return lines
            .map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
            .joined(separator: "\n")
    }
}
