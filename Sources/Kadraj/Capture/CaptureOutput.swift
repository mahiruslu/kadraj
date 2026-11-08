import AppKit
import KadrajCore

struct CaptureResult {
    let image: CGImage
    let fileURL: URL?
    let error: String?
}

@MainActor
enum CaptureOutput {
    /// Copies and/or saves the image according to settings. The clipboard copy happens
    /// first, so a failed save never loses the capture.
    static func deliver(_ image: CGImage, settings: CaptureSettings, date: Date = Date()) -> CaptureResult {
        if settings.copyToClipboard {
            copyToClipboard(image)
        }
        guard settings.saveToFile else { return CaptureResult(image: image, fileURL: nil, error: nil) }

        do {
            let url = try save(image, settings: settings, date: date)
            return CaptureResult(image: image, fileURL: url, error: nil)
        } catch {
            NSLog("Kadraj: save failed: \(error.localizedDescription)")
            if !settings.copyToClipboard { copyToClipboard(image) }
            return CaptureResult(image: image, fileURL: nil,
                                 error: "Kaydedilemedi: \(error.localizedDescription). Görüntü panoya kopyalandı.")
        }
    }

    static func copyToClipboard(_ image: CGImage) {
        let pb = NSPasteboard.general
        pb.clearContents()
        let rep = NSBitmapImageRep(cgImage: image)
        if let png = rep.representation(using: .png, properties: [:]) {
            pb.setData(png, forType: .png)
        }
        if let tiff = rep.tiffRepresentation {
            pb.setData(tiff, forType: .tiff)
        }
    }

    static func save(_ image: CGImage, settings: CaptureSettings, date: Date) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: settings.saveDirectory, withIntermediateDirectories: true)
        let name = FileNamer.fileName(date: date, ext: settings.format.fileExtension)
        let url = FileNamer.uniqueURL(directory: settings.saveDirectory, fileName: name) {
            fm.fileExists(atPath: $0.path)
        }
        guard let data = ImageEncoder.data(for: image, format: settings.format) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try data.write(to: url, options: .atomic)
        return url
    }
}
