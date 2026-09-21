import Foundation
import Security

/// Minimal Keychain wrapper for the app's secrets (Clockify API key, Google OAuth tokens).
final class KeychainStore {
    static let shared = KeychainStore()

    private let service = "com.jules.clockapp"

    /// Clockify API key.
    var apiKey: String? {
        get { value(for: "clockify-api-key") }
        set { setValue(newValue, for: "clockify-api-key") }
    }

    /// Google OAuth refresh token (long-lived) — presence means "connected".
    var googleRefreshToken: String? {
        get { value(for: "google-refresh-token") }
        set { setValue(newValue, for: "google-refresh-token") }
    }

    /// Google OAuth "Desktop app" client secret (needed to refresh access tokens).
    var googleClientSecret: String? {
        get { value(for: "google-client-secret") }
        set { setValue(newValue, for: "google-client-secret") }
    }

    // MARK: - Generic access

    func value(for account: String) -> String? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    func setValue(_ newValue: String?, for account: String) {
        if let newValue, !newValue.isEmpty {
            write(newValue, account: account)
        } else {
            SecItemDelete(baseQuery(account) as CFDictionary)
        }
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func write(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query = baseQuery(account)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }
}
