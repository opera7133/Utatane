import Foundation
import Security

enum AIAPIKeyStore {
    private static let service = "dev.utatane.app.ai-provider"

    static func load(account: String = "default") -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func save(_ value: String, account: String = "default") {
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if value.isEmpty {
            SecItemDelete(key as CFDictionary)
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
        if SecItemUpdate(key as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insertion = key
            insertion[kSecValueData as String] = Data(value.utf8)
            SecItemAdd(insertion as CFDictionary, nil)
        }
    }
}
