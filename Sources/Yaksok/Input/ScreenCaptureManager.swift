import AppKit

/// Screen capture with region selection overlay
/// Uses macOS screencapture command for reliable permission handling
@MainActor
final class ScreenCaptureManager {

    /// Capture a user-selected screen region and return as JPEG data
    func captureRegion() async -> Data? {
        // Use macOS built-in screencapture -i (interactive selection)
        // This handles screen recording permissions natively
        let tempPath = NSTemporaryDirectory() + "yaksok_capture_\(ProcessInfo.processInfo.globallyUniqueString).png"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", tempPath]  // -i: interactive, -x: no sound

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                Log.input.info("Screen capture cancelled by user")
                return nil
            }

            // Read captured image
            guard FileManager.default.fileExists(atPath: tempPath) else {
                Log.input.info("Screen capture file not created (cancelled)")
                return nil
            }

            defer {
                try? FileManager.default.removeItem(atPath: tempPath)
            }

            guard let image = NSImage(contentsOfFile: tempPath) else {
                Log.input.error("Failed to load captured image")
                return nil
            }

            let jpegData = autoreleasepool {
                ImageConverter.jpegData(from: image, quality: 0.85)
            }

            if let jpegData {
                Log.input.info("Screen capture: \(jpegData.count) bytes")
            }
            return jpegData

        } catch {
            Log.input.error("Screen capture failed: \(error.localizedDescription)")
            return nil
        }
    }
}
