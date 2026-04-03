import AppKit

/// Reads text or image from the system clipboard
/// Supports: direct text, direct image (TIFF/PNG), Universal Clipboard (file URL reference)
enum ClipboardReader {

    enum ClipboardContent: Sendable {
        case text(String)
        case image(Data)  // JPEG data
        case empty
    }

    /// Read current clipboard content — text first, then image (including Universal Clipboard)
    static func read() -> ClipboardContent {
        let pasteboard = NSPasteboard.general
        let types = pasteboard.types ?? []
        Log.input.info("Clipboard types: \(types.map(\.rawValue))")

        // 1. Direct image data (TIFF, PNG) — local copy/paste
        if let imageData = readDirectImage(from: pasteboard, types: types) {
            Log.input.info("Clipboard: direct image (\(imageData.count) bytes)")
            return .image(imageData)
        }

        // 2. File URL pointing to an image — Universal Clipboard, screenshot, etc.
        if let imageData = readImageFromFileURL(from: pasteboard, types: types) {
            Log.input.info("Clipboard: image via file URL (\(imageData.count) bytes)")
            return .image(imageData)
        }

        // 3. Plain text
        if types.contains(.string),
           let text = pasteboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            Log.input.info("Clipboard: text (\(text.count) chars)")
            return .text(text)
        }

        Log.input.info("Clipboard: empty or unsupported type")
        return .empty
    }

    // MARK: - Direct Image (TIFF/PNG in pasteboard)

    private static func readDirectImage(from pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Data? {
        autoreleasepool {
            for type in [NSPasteboard.PasteboardType.tiff, .png] {
                if types.contains(type),
                   let data = pasteboard.data(forType: type),
                   let image = NSImage(data: data)
                {
                    return ImageConverter.jpegData(from: image)
                }
            }
            return nil
        }
    }

    // MARK: - Image from File URL (Universal Clipboard, etc.)

    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "bmp", "gif", "heic", "webp"]

    private static func readImageFromFileURL(from pasteboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Data? {
        autoreleasepool {
            let fileURLType = NSPasteboard.PasteboardType("public.file-url")
            guard types.contains(fileURLType),
                  let data = pasteboard.data(forType: fileURLType),
                  let urlStr = String(data: data, encoding: .utf8),
                  let url = URL(string: urlStr)
            else { return nil }

            let ext = url.pathExtension.lowercased()
            guard imageExtensions.contains(ext) else {
                Log.input.info("File URL is not an image: \(ext)")
                return nil
            }

            guard FileManager.default.fileExists(atPath: url.path) else {
                Log.input.info("File does not exist: \(url.path)")
                return nil
            }

            guard let image = NSImage(contentsOf: url) else {
                Log.input.error("Failed to load image from: \(url.path)")
                return nil
            }

            Log.input.info("Loaded image from file URL: \(url.lastPathComponent) (\(Int(image.size.width))x\(Int(image.size.height)))")
            return ImageConverter.jpegData(from: image)
        }
    }
}
