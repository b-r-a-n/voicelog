import Foundation
import Security

actor KeychainManager {
    static let shared = KeychainManager()

    private let service = "com.voicelog.app"
    private let accessTokenKey = "access_token"
    private let refreshTokenKey = "refresh_token"

    private init() {}

    // MARK: - Token Management

    func saveTokens(_ token: AuthToken) {
        save(key: accessTokenKey, value: token.accessToken)
        save(key: refreshTokenKey, value: token.refreshToken)
    }

    func getAccessToken() -> String? {
        get(key: accessTokenKey)
    }

    func getRefreshToken() -> String? {
        get(key: refreshTokenKey)
    }

    func deleteTokens() {
        delete(key: accessTokenKey)
        delete(key: refreshTokenKey)
    }

    func hasValidTokens() -> Bool {
        getAccessToken() != nil && getRefreshToken() != nil
    }

    // MARK: - Private Keychain Operations

    private func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }

        delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        SecItemAdd(query as CFDictionary, nil)
    }

    private func get(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }

        return string
    }

    private func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }
}
