import Foundation
import Security

enum MailPasswordStore {
    private static let service = "dev.utatane.app.mail"

    static func load(account: String) -> String {
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

    static func save(_ value: String, account: String) {
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if value.isEmpty {
            SecItemDelete(key as CFDictionary)
            return
        }
        let attributes = [kSecValueData as String: Data(value.utf8)]
        if SecItemUpdate(key as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insertion = key
            insertion[kSecValueData as String] = Data(value.utf8)
            SecItemAdd(insertion as CFDictionary, nil)
        }
    }
}
