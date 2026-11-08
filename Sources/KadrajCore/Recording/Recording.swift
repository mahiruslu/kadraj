import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum RecordingGeometry {
    /// H.264 needs even pixel dimensions (at least 2).
    public static func evenPixelSize(_ points: CGSize, scale: CGFloat) -> (width: Int, height: Int) {
        func even(_ v: CGFloat) -> Int { max(2, Int(v * scale) / 2 * 2) }
        return (even(points.width), even(points.height))
    }
}

public enum GIFTiming {
    /// Sample times for a clip; long clips are thinned to `maxFrames` and the per-frame delay
    /// stretched so the GIF keeps the clip's duration.
    public static func frameTimes(duration: Double, fps: Double, maxFrames: Int) -> (times: [Double], delay: Double) {
        guard duration > 0, fps > 0, maxFrames > 0 else { return ([0], 1 / max(fps, 1)) }
        let natural = Int((duration * fps).rounded(.down))
        let count = max(1, min(natural, maxFrames))
        let delay = count == natural ? 1 / fps : duration / Double(count)
        return ((0..<count).map { Double($0) * delay }, delay)
    }
}

public enum GIFEncoder {
    /// An infinitely looping animated GIF.
    public static func encode(_ frames: [CGImage], delay: Double) -> Data? {
        guard !frames.isEmpty else { return nil }
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data, UTType.gif.identifier as CFString, frames.count, nil) else {
            return nil
        }
        CGImageDestinationSetProperties(dest, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)
        let frameProps = [kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: delay,
            kCGImagePropertyGIFUnclampedDelayTime: delay,
        ]] as CFDictionary
        for frame in frames { CGImageDestinationAddImage(dest, frame, frameProps) }
        guard CGImageDestinationFinalize(dest) else { return nil }
        return data as Data
    }
}
