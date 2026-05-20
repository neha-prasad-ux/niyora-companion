import Foundation
import Security

/// iOS Keychain storage for two kinds of secrets:
///
/// 1. The stable per-install `client_id` UUID. Persisted so re-launching
///    the app still identifies as the same paired device. Lives under
///    account `self.client_id`.
/// 2. The per-Mac shared secret minted during pairing. Lives under
///    account `mac.<server_id>` so a phone paired with two Macs holds
///    two distinct secrets.
///
/// Service identifier matches the bundle ID. Items are not synced to
/// iCloud Keychain ‑ `kSecAttrSynchronizable = false` ‑ because Niyora's
/// privacy stance is "stays on the user's devices, no cloud."
enum KeychainStore {
    static let service = "com.niyora.companion"

    // MARK: - Stable client_id

    /// Return the stable per-install `client_id`, minting one on first
    /// call. The same UUID is returned on every subsequent launch so the
    /// Mac sees a consistent identity for this phone.
    static func clientId() -> String {
        if let existing = readString(account: "self.client_id") {
            return existing
        }
        let id = UUID().uuidString
        _ = writeString(id, account: "self.client_id")
        return id
    }

    // MARK: - Per-Mac shared secret

    static func storeSecret(_ secret: Data, forServerId serverId: String) -> Bool {
        write(secret, account: "mac.\(serverId)")
    }

    static func loadSecret(forServerId serverId: String) -> Data? {
        read(account: "mac.\(serverId)")
    }

    static func deleteSecret(forServerId serverId: String) {
        delete(account: "mac.\(serverId)")
    }

    // MARK: - Generic helpers

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    private static func read(account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = kCFBooleanTrue as Any
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private static func readString(account: String) -> String? {
        guard let data = read(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    private static func write(_ data: Data, account: String) -> Bool {
        // Try update first; if no item exists, add.
        let updateStatus = SecItemUpdate(
            baseQuery(account: account) as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return true }
        if updateStatus != errSecItemNotFound { return false }

        var addQuery = baseQuery(account: account)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    private static func writeString(_ s: String, account: String) -> Bool {
        guard let data = s.data(using: .utf8) else { return false }
        return write(data, account: account)
    }

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
