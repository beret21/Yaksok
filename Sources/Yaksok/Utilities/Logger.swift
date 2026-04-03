import Foundation
import os

enum Log {
    private static let subsystem = "com.beret21.yaksok"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let llm = Logger(subsystem: subsystem, category: "llm")
    static let calendar = Logger(subsystem: subsystem, category: "calendar")
    static let input = Logger(subsystem: subsystem, category: "input")

    // File-based debug log: ~/Library/Logs/Yaksok/yaksok_YYYY.log
    // Owner-only permissions (0600) to prevent other users from reading.
    private static let logFile: URL = {
        let year = Calendar.current.component(.year, from: Date())
        let logDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Yaksok", isDirectory: true)
        try? FileManager.default.createDirectory(at: logDir, withIntermediateDirectories: true)
        // Restrict directory to owner only
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: logDir.path)
        return logDir.appendingPathComponent("yaksok_\(year).log")
    }()

    static func debug(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
                // Restrict log file to owner only
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o600], ofItemAtPath: logFile.path)
            }
        }
    }
}
