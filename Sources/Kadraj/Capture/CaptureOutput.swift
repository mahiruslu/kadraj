import AppKit
import KadrajCore

struct CaptureResult {
    let image: CGImage
    let fileURL: URL?
    let error: String?
    /// Pixels per point of the screen it was captured on (1 on non-Retina displays).
    var scale: CGFloat = 2

    /// On-screen size of the capture in points.
    var pointSize: CGSize { CGSize(width: CGFloat(image.width) / scale, height: CGFloat(image.height) / scale) }
}

@MainActor
enum CaptureOutput {
    /// Copies and/or saves the image according to settings. PNG is encoded once, off the main
    /// thread, and reused; the clipboard copy happens first so a failed save never loses it.
    static func deliver(_ image: CGImage, settings: CaptureSettings, scale: CGFloat, date: Date = Date()) async -> CaptureResult {
        let png = await Task.detached(priority: .userInitiated) { ImageEncoder.data(for: image, format: .png) }.value
        if settings.copyToClipboard { copyPNG(png, fallback: image) }
        guard settings.saveToFile else { return CaptureResult(image: image, fileURL: nil, error: nil, scale: scale) }
        do {
            let data = settings.format == .png ? png : nil
            let url = try await Task.detached(priority: .userInitiated) {
                try save(image, encoded: data, settings: settings, date: date)
            }.value
            return CaptureResult(image: image, fileURL: url, error: nil, scale: scale)
        } catch {
            NSLog("Kadraj: save failed: \(error.localizedDescription)")
            if !settings.copyToClipboard { copyPNG(png, fallback: image) }
            return CaptureResult(image: image, fileURL: nil,
                                 error: "Kaydedilemedi: \(error.localizedDescription). Görüntü panoya kopyalandı.",
                                 scale: scale)
        }
    }

    /// PNG only: every current macOS app reads it, and a full-screen TIFF would be ~60 MB.
    static func copyToClipboard(_ image: CGImage) {
        copyPNG(ImageEncoder.data(for: image, format: .png), fallback: image)
    }

    private static func copyPNG(_ png: Data?, fallback image: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let png {
            pb.setData(png, forType: .png)
        } else {
            pb.writeObjects([NSImage(cgImage: image, size: .zero)])
        }
    }

    nonisolated static func save(_ image: CGImage, encoded: Data? = nil, settings: CaptureSettings, date: Date) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: settings.saveDirectory, withIntermediateDirectories: true)
        let name = FileNamer.fileName(date: date, ext: settings.format.fileExtension)
        let url = FileNamer.uniqueURL(directory: settings.saveDirectory, fileName: name) {
            fm.fileExists(atPath: $0.path)
        }
        guard let data = encoded ?? ImageEncoder.data(for: image, format: settings.format) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return url
    }
}
