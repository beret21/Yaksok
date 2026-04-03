import Foundation
import Security

/// API key storage using macOS Keychain (encrypted by the system)
///
/// On first launch, migrates any existing plain-text keys from ~/.yaksok/ then
/// deletes the files. All subsequent reads/writes go through SecItem APIs.
enum KeychainManager {
    private static let service = "com.beret21.yaksok"

    // MARK: - Public API

    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }

        // Delete existing item first (update = delete + add)
        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
            kSecAttrSynchronizable as String: false,  // iCloud Keychain 동기화 금지
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(key: String) -> String? {
        // Try Keychain first
        if let value = loadFromKeychain(key: key) {
            return value
        }
        // Fall back: migrate from legacy file if it exists
        if let value = loadFromLegacyFile(key: key) {
            try? save(key: key, value: value)
            deleteLegacyFile(key: key)
            Log.debug("[Keychain] Migrated \(key) from file to Keychain")
            return value
        }
        return nil
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Keychain read

    private static func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    // MARK: - Legacy file migration

    private static var legacyDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".yaksok", isDirectory: true)
    }

    private static func loadFromLegacyFile(key: String) -> String? {
        let url = legacyDir.appendingPathComponent(key)
        guard let value = try? String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }

    private static func deleteLegacyFile(key: String) {
        let url = legacyDir.appendingPathComponent(key)
        try? FileManager.default.removeItem(at: url)
        // Remove directory if empty
        let contents = try? FileManager.default.contentsOfDirectory(atPath: legacyDir.path)
        if contents?.isEmpty == true {
            try? FileManager.default.removeItem(at: legacyDir)
            Log.debug("[Keychain] Removed empty ~/.yaksok/ directory")
        }
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            let msg = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown"
            return "Keychain save failed: \(msg) (\(status))"
        }
    }
}
