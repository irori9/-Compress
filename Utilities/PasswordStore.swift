import Foundation
#if canImport(Security)
import Security
#endif

public enum PasswordScope: Equatable {
    case file(URL)
    case host(String)

    var key: String {
        switch self {
        case .file(let url):
            return "file::" + url.standardizedFileURL.path
        case .host(let host):
            return "host::" + host.lowercased()
        }
    }
}

public protocol PasswordStoring {
    func password(for scope: PasswordScope) -> String?
    func setPassword(_ password: String?, for scope: PasswordScope)
    func clearAll()
}

public final class PasswordStore: PasswordStoring {
    public static let shared = PasswordStore()
    private init() {}

    private let service = "ArchiveManager.Passwords"
    private let defaultsKey = "ArchiveManager.Passwords.Fallback"

    public func password(for scope: PasswordScope) -> String? {
        #if canImport(Security)
        if let data = readKeychain(account: scope.key), let str = String(data: data, encoding: .utf8) {
            return str
        }
        #endif
        let map = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
        return map[scope.key]
    }

    public func setPassword(_ password: String?, for scope: PasswordScope) {
        #if canImport(Security)
        if let pwd = password {
            _ = upsertKeychain(account: scope.key, value: Data(pwd.utf8))
        } else {
            _ = deleteKeychain(account: scope.key)
        }
        #endif
        var map = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
        map[scope.key] = password
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }

    public func clearAll() {
        #if canImport(Security)
        deleteAllKeychain()
        #endif
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    #if canImport(Security)
    private func upsertKeychain(account: String, value: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: value
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = value
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        return status == errSecSuccess
    }

    private func readKeychain(account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return nil }
        return result as? Data
    }

    private func deleteKeychain(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    private func deleteAllKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        SecItemDelete(query as CFDictionary)
    }
    #endif
}
