import AppKit

/// Handles drag & drop onto the menu bar status item
/// Accepts: text, image files, image data
@MainActor
final class StatusBarDragDelegate: NSObject, NSWindowDelegate, NSDraggingDestination {
    private let controllerProvider: () -> StatusBarController?

    init(_ controllerProvider: @escaping () -> StatusBarController?) {
        self.controllerProvider = controllerProvider
        super.init()
    }

    // MARK: - NSDraggingDestination

    nonisolated func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let types = sender.draggingPasteboard.types ?? []
        if types.contains(.string) || types.contains(.fileURL) ||
           types.contains(.tiff) || types.contains(.png)
        {
            return .copy
        }
        return []
    }

    nonisolated func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        // Extract data from pasteboard in nonisolated context
        let pasteboard = sender.draggingPasteboard
        let types = pasteboard.types ?? []

        var imageData: Data?
        var textData: String?
        var fileURL: URL?

        // Read everything synchronously before crossing actor boundary
        for type in [NSPasteboard.PasteboardType.tiff, .png] {
            if types.contains(type), let data = pasteboard.data(forType: type) {
                imageData = data
                break
            }
        }

        if imageData == nil, types.contains(.fileURL),
           let urlData = pasteboard.data(forType: .fileURL),
           let urlStr = String(data: urlData, encoding: .utf8),
           let url = URL(string: urlStr)
        {
            fileURL = url
        }

        if imageData == nil && fileURL == nil, types.contains(.string) {
            textData = pasteboard.string(forType: .string)
        }

        DispatchQueue.main.async { [weak self] in
            self?.handleDrop(imageData: imageData, fileURL: fileURL, textData: textData)
        }
        return true
    }

    private func handleDrop(imageData: Data?, fileURL: URL?, textData: String?) {
        guard let controller = controllerProvider() else { return }

        // 1. Direct image data
        if let data = imageData {
            let jpeg: Data? = autoreleasepool {
                guard let image = NSImage(data: data) else { return nil }
                return ImageConverter.jpegData(from: image)
            }
            if let jpeg {
                Log.debug("[DragDrop] Image data dropped (\(jpeg.count) bytes)")
                processImage(jpeg, controller: controller)
                return
            }
        }

        // 2. Image file URL
        if let url = fileURL {
            let ext = url.pathExtension.lowercased()
            let imageExts: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "bmp", "gif", "heic", "webp"]
            if imageExts.contains(ext) {
                // Validate: regular file, not symlink, under 50MB
                let fm = FileManager.default
                guard let attrs = try? fm.attributesOfItem(atPath: url.path),
                      attrs[.type] as? FileAttributeType != .typeSymbolicLink,
                      let size = attrs[.size] as? UInt64, size < 50 * 1024 * 1024
                else {
                    Log.debug("[DragDrop] File rejected: symlink or too large")
                    return
                }
                let jpeg: Data? = autoreleasepool {
                    guard let image = NSImage(contentsOf: url) else { return nil }
                    return ImageConverter.jpegData(from: image)
                }
                if let jpeg {
                    Log.debug("[DragDrop] Image file dropped: \(url.lastPathComponent)")
                    processImage(jpeg, controller: controller)
                    return
                }
            }
        }

        // 3. Text
        if let text = textData, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Log.debug("[DragDrop] Text dropped: \(text.count) chars")
            processText(text, controller: controller)
            return
        }

        Log.debug("[DragDrop] Unsupported drop content")
    }

    private func processText(_ text: String, controller: StatusBarController) {
        Task { @MainActor in
            controller.showProcessingPopover()
            await controller.inputCoordinator.extractFromText(text, state: controller.appState)
            controller.dismissProcessingPopover()
            controller.handleExtractionResult()
        }
    }

    private func processImage(_ data: Data, controller: StatusBarController) {
        Task { @MainActor in
            controller.showProcessingPopover()
            await controller.inputCoordinator.extractFromImage(data, state: controller.appState)
            controller.dismissProcessingPopover()
            controller.handleExtractionResult()
        }
    }
}
