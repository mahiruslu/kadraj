import CoreGraphics
import Foundation

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
///
/// Fragments are grouped into lines by vertical overlap. If the selection holds two (or more)
/// columns of running text, each column is read top to bottom before the next one; tables,
/// whose rows line up across the gap, stay row by row.
public enum TextAssembler {
    /// Minimum horizontal gap (fraction of the selection width) that can separate columns.
    static let minimumColumnGap: CGFloat = 0.03
    static let minimumLinesPerColumn = 3

    public static func assemble(_ fragments: [RecognizedFragment]) -> String {
        let pieces = fragments
            .map { RecognizedFragment(text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines), box: $0.box) }
            .filter { !$0.text.isEmpty }
        return columns(pieces)
            .map { lines($0).map { $0.map(\.text).joined(separator: " ") }.joined(separator: "\n") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    // MARK: Lines

    private struct Line {
        var box: CGRect
        var items: [RecognizedFragment]
    }

    /// Vertical overlap relative to the smaller height (1 = one fully inside the other's band).
    static func overlapRatio(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let overlap = min(a.maxY, b.maxY) - max(a.minY, b.minY)
        let smaller = min(a.height, b.height)
        guard smaller > 0 else { return 0 }
        return max(0, overlap) / smaller
    }

    /// Lines top to bottom, each line's fragments left to right.
    static func lines(_ pieces: [RecognizedFragment]) -> [[RecognizedFragment]] {
        var result: [Line] = []
        for piece in pieces.sorted(by: { $0.box.midY > $1.box.midY }) {
            let best = result.indices
                .map { ($0, overlapRatio(piece.box, result[$0].box)) }
                .filter { $0.1 > 0.5 }
                .max { $0.1 < $1.1 }
            if let (index, _) = best {
                result[index].items.append(piece)
                result[index].box = result[index].box.union(piece.box)
            } else {
                result.append(Line(box: piece.box, items: [piece]))
            }
        }
        return result
            .sorted { $0.box.midY > $1.box.midY }
            .map { $0.items.sorted { $0.box.minX < $1.box.minX } }
    }

    // MARK: Columns

    static func columns(_ pieces: [RecognizedFragment]) -> [[RecognizedFragment]] {
        guard let splitX = widestGapCenter(pieces) else { return [pieces] }
        let left = pieces.filter { $0.box.midX < splitX }
        let right = pieces.filter { $0.box.midX >= splitX }
        let leftLines = lines(left), rightLines = lines(right)
        guard leftLines.count >= minimumLinesPerColumn, rightLines.count >= minimumLinesPerColumn else { return [pieces] }

        // Table rows line up across the gap; columns of running text mostly don't.
        let (fewer, more) = leftLines.count <= rightLines.count ? (leftLines, rightLines) : (rightLines, leftLines)
        let aligned = fewer.filter { line in
            let box = line.map(\.box).reduce(CGRect.null) { $0.union($1) }
            return more.contains { other in
                overlapRatio(box, other.map(\.box).reduce(CGRect.null) { $0.union($1) }) > 0.5
            }
        }.count
        guard Double(aligned) / Double(fewer.count) < 0.5 else { return [pieces] }
        return columns(left) + columns(right)
    }

    /// Center of the widest vertical strip that no fragment crosses, if wide enough.
    private static func widestGapCenter(_ pieces: [RecognizedFragment]) -> CGFloat? {
        let spans = pieces.map { ($0.box.minX, $0.box.maxX) }.sorted { $0.0 < $1.0 }
        guard var reach = spans.first?.1 else { return nil }
        var best: (width: CGFloat, center: CGFloat)?
        for (start, end) in spans.dropFirst() {
            if start > reach {
                let width = start - reach
                if width >= minimumColumnGap, width > (best?.width ?? 0) { best = (width, (start + reach) / 2) }
            }
            reach = max(reach, end)
        }
        return best?.center
    }
}
