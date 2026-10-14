import Foundation
import Security

struct Credentials {
    let login: String
    let password: String

    /// Логин для Open API: без домена, если введён как почта.
    var apiLogin: String {
        String(login.split(separator: "@").first ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    }
}

/// Пароль и refresh-токены — в Keychain iPhone (доступны только этому приложению, после первой разблокировки).
enum Keychain {
    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AppConfig.keychainService,
            kSecAttrAccount as String: account,
        ]
    }

    static func get(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ account: String, _ value: String?) {
        SecItemDelete(query(account) as CFDictionary)
        guard let value, let data = value.data(using: .utf8) else { return }
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }

    static func loadCredentials() -> Credentials? {
        guard let login = get("login"), let password = get("password") else { return nil }
        return Credentials(login: login, password: password)
    }

    static func saveCredentials(_ credentials: Credentials) {
        clearCredentials()
        set("login", credentials.login)
        set("password", credentials.password)
    }

    static func clearCredentials() {
        for account in ["login", "password", "refresh_\(AppConfig.clientPlatform)", "refresh_\(AppConfig.clientOpenAPI)"] {
            set(account, nil)
        }
    }
}
