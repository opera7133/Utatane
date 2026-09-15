import Foundation
import Security

public enum SpeechCredentialStore {
    public enum Provider: String, Sendable {
        case voisonaTalk = "voisona-talk"
        case openAI = "openai"
        case openAICompatibleLocal = "openai-compatible-local"
        case elevenLabs = "elevenlabs"
        case aivisCloud = "aivis-cloud"
    }

    public struct Credential: Codable, Equatable, Sendable {
        public var username: String
        public var password: String

        public init(username: String = "", password: String = "") {
            self.username = username
            self.password = password
        }

        public var isComplete: Bool {
            !username.isEmpty && !password.isEmpty
        }
    }

    private static let service = "dev.utatane.app.speech-provider"

    public static func load(provider: Provider = .voisonaTalk, scope: Int) -> Credential {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(provider: provider, scope: scope),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let credential = try? JSONDecoder().decode(Credential.self, from: data)
        else { return Credential() }
        return credential
    }

    public static func save(_ credential: Credential, provider: Provider = .voisonaTalk, scope: Int) {
        let key: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account(provider: provider, scope: scope)
        ]
        guard !credential.username.isEmpty || !credential.password.isEmpty,
              let data = try? JSONEncoder().encode(credential)
        else {
            SecItemDelete(key as CFDictionary)
            return
        }
        let attributes: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(key as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var insertion = key
            insertion[kSecValueData as String] = data
            SecItemAdd(insertion as CFDictionary, nil)
        }
    }

    private static func account(provider: Provider, scope: Int) -> String {
        "\(provider.rawValue).scope-\(scope)"
    }
}
