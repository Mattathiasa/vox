import Foundation
import Security

/// Small Keychain wrapper for sensitive values (API keys).
enum Keychain {
    static func read(_ key: String) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.vox",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let str = String(data: data, encoding: .utf8) else {
            return nil
        }
        return str
    }

    static func set(_ key: String, _ value: String) -> Bool {
        let data = value.data(using: .utf8)!
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.vox",
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemAdd(q as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let update: [String: Any] = [kSecValueData as String: data]
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "com.vox",
                kSecAttrAccount as String: key
            ]
            #if canImport(ObjectiveC)
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
            #else
            let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary, nil, nil)
            #endif
            return updateStatus == errSecSuccess
        }
        return status == errSecSuccess
    }
}
