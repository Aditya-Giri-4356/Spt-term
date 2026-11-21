import Foundation
import os.log
import Security

/// Generic-password wrapper. One service string for the whole app.
enum STKeychain {
    private static let service = Bundle.main.bundleIdentifier ?? "com.aditya.sptterm"

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        guard let data = value.data(using: .utf8) else {
            os_log("STKeychain.set: failed to encode string to utf8 data", log: OSLog.default, type: .error)
            return false
        }
        _ = SecItemDelete(baseQuery(key) as CFDictionary)
        var query = baseQuery(key)
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery = baseQuery(key)
            let updateAttributes: [String: Any] = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
            if updateStatus != errSecSuccess {
                os_log("STKeychain.set: SecItemUpdate failed with OSStatus %d", log: OSLog.default, type: .error, updateStatus)
            }
            return updateStatus == errSecSuccess
        }
        if status != errSecSuccess {
            os_log("STKeychain.set: SecItemAdd failed with OSStatus %d", log: OSLog.default, type: .error, status)
        }
        return status == errSecSuccess
    }

    static func get(_ key: String) -> String? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess, let data = out as? Data else {
            if status != errSecItemNotFound {
                os_log("STKeychain.get: SecItemCopyMatching failed with OSStatus %d for key %{public}@", log: OSLog.default, type: .error, status, key)
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            os_log("STKeychain.delete: SecItemDelete failed with OSStatus %d for key %{public}@", log: OSLog.default, type: .error, status, key)
            return false
        }
        return true
    }

    private static func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
    }
}
