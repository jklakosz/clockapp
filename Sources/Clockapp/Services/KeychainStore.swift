import Foundation
import Security

/// Minimal Keychain wrapper for the single Clockify API key.
final class KeychainStore {
    static let shared = KeychainStore()

    private let service = "com.jules.clockapp"
    private let account = "clockify-api-key"

    var apiKey: String? {
        get { read() }
        set {
            if let newValue, !newValue.isEmpty {
                write(newValue)
            } else {
                delete()
            }
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read() -> String? {
        var query = baseQuery()
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

    private func write(_ value: String) {
        let data = Data(value.utf8)
        let query = baseQuery()
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    private func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
