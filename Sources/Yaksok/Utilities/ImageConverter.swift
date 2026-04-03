import AppKit

enum ImageConverter {
    /// NSImage → JPEG Data (quality 0.8)
    static func jpegData(from image: NSImage, quality: Double = 0.8) -> Data? {
        autoreleasepool {
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData)
            else { return nil }
            return bitmap.representation(
                using: .jpeg,
                properties: [.compressionFactor: quality]
            )
        }
    }

    /// Data → base64 encoded string
    static func base64String(from data: Data) -> String {
        data.base64EncodedString()
    }

    /// NSImage → base64 JPEG string
    static func base64JPEG(from image: NSImage, quality: Double = 0.8) -> String? {
        guard let data = jpegData(from: image, quality: quality) else { return nil }
        return base64String(from: data)
    }
}
