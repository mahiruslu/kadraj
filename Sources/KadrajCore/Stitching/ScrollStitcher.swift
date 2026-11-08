import CoreGraphics
import Foundation

/// Joins frames of a region the user scrolls into one tall image.
///
/// Each frame is reduced to a grayscale signature (32 columns per row). For every new frame
/// the rows that stayed identical at the top and bottom (sticky headers/footers) are excluded,
/// and the vertical shift of the middle part is found by minimizing the mean absolute
/// difference (coarse every 4th row, then refined). Only newly revealed rows are appended.
/// Not thread-safe: use it from one queue.
public final class ScrollStitcher {
    public enum AddResult: Equatable, Sendable {
        case first
        case appended(Int)
        case unchanged
        /// No reliable match (scrolled up, too fast, or the content changed).
        case noMatch
        case limitReached
    }

    static let bins = 32
    /// Mean luminance difference (0…255) below which two rows count as identical.
    static let sameRowThreshold: Float = 1.0
    /// Mean difference below which a shift is accepted.
    static let matchThreshold: Float = 8.0

    public let maxHeight: Int
    private var width = 0
    private var frameHeight = 0
    private var first: CGImage?
    private var last: CGImage?
    private var lastSignature: [Float] = []
    private var chunks: [CGImage] = []
    private var appendedRows = 0
    private var footer = 0
    private var finished = false

    public init(maxHeight: Int = 30_000) {
        self.maxHeight = maxHeight
    }

    /// Current stitched height in pixels.
    public var height: Int { first == nil ? 0 : frameHeight + appendedRows }

    public func add(_ frame: CGImage) -> AddResult {
        if finished { return .limitReached }
        guard first != nil else {
            first = frame
            last = frame
            width = frame.width
            frameHeight = frame.height
            lastSignature = Self.signature(frame)
            return .first
        }
        guard frame.width == width, frame.height == frameHeight else { return .noMatch }

        let signature = Self.signature(frame)
        let h = frameHeight
        let previous = lastSignature

        var top = 0
        while top < h, Self.rowDiff(previous, top, signature, top) < Self.sameRowThreshold { top += 1 }
        if top == h { return .unchanged }
        var bottom = 0
        while bottom < h - top, Self.rowDiff(previous, h - 1 - bottom, signature, h - 1 - bottom) < Self.sameRowThreshold {
            bottom += 1
        }
        let middle = h - top - bottom
        guard middle >= max(h / 5, 8) else { return .unchanged } // e.g. only a blinking cursor changed
        let maxShift = middle - max(middle / 4, 8)
        guard maxShift >= 1 else { return .noMatch }

        func error(_ shift: Int, step: Int) -> Float {
            var total: Float = 0, count = 0
            var row = top + shift
            while row < h - bottom {
                total += Self.rowDiff(previous, row, signature, row - shift)
                count += 1
                row += step
            }
            return count > 0 ? total / Float(count) : .infinity
        }

        var best = 1, bestError = Float.infinity
        for shift in 1...maxShift {
            let e = error(shift, step: 4)
            if e < bestError { bestError = e; best = shift }
        }
        let coarse = best
        bestError = .infinity
        for shift in max(1, coarse - 4)...min(maxShift, coarse + 4) {
            let e = error(shift, step: 1)
            if e < bestError { bestError = e; best = shift }
        }
        guard bestError < Self.matchThreshold else { return .noMatch }

        var take = best
        var result = AddResult.appended(best)
        if height + best > maxHeight {
            take = max(0, maxHeight - height)
            result = .limitReached
            finished = true
        }
        if take > 0, let chunk = Self.copyRows(frame, from: h - bottom - best, count: take) {
            chunks.append(chunk)
            appendedRows += take
        }
        footer = bottom
        last = frame
        lastSignature = signature
        return result
    }

    /// First frame (without its footer) + appended rows + the latest footer.
    public func image() -> CGImage? {
        guard let first, let last else { return nil }
        let total = height
        guard let ctx = CGContext(data: nil, width: width, height: total, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        var y = 0 // from the top
        func place(_ image: CGImage) {
            ctx.draw(image, in: CGRect(x: 0, y: total - y - image.height, width: image.width, height: image.height))
            y += image.height
        }
        if let head = Self.copyRows(first, from: 0, count: frameHeight - footer) { place(head) }
        chunks.forEach(place)
        if footer > 0, let foot = Self.copyRows(last, from: frameHeight - footer, count: footer) { place(foot) }
        return ctx.makeImage()
    }

    // MARK: Helpers

    static func rowDiff(_ a: [Float], _ ra: Int, _ b: [Float], _ rb: Int) -> Float {
        var sum: Float = 0
        let ia = ra * bins, ib = rb * bins
        for i in 0..<bins { sum += abs(a[ia + i] - b[ib + i]) }
        return sum / Float(bins)
    }

    /// Grayscale, `bins` columns wide (horizontal area average), one value per pixel row.
    static func signature(_ image: CGImage) -> [Float] {
        let h = image.height
        var buffer = [UInt8](repeating: 0, count: bins * h)
        buffer.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: bins, height: h, bitsPerComponent: 8, bytesPerRow: bins,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: bins, height: h))
        }
        return buffer.map(Float.init)
    }

    /// A standalone copy of rows [from, from+count) (top-left origin), so the full frame can be released.
    static func copyRows(_ image: CGImage, from: Int, count: Int) -> CGImage? {
        guard count > 0, let cropped = image.cropping(to: CGRect(x: 0, y: from, width: image.width, height: count)),
              let ctx = CGContext(data: nil, width: cropped.width, height: cropped.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: cropped.width, height: cropped.height))
        return ctx.makeImage()
    }
}
