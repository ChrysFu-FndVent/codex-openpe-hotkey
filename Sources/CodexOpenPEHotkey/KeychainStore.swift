import Foundation
import Security

enum KeychainStore {
    static func string(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, service: String, account: String) throws {
        guard let data = value.data(using: .utf8), !data.isEmpty else {
            throw KeychainStoreError.emptyValue
        }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.securityStatus(updateStatus)
        }

        var item = query
        item[kSecValueData as String] = data
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.securityStatus(addStatus)
        }
    }

    static func randomToken(byteCount: Int = 32) throws -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw KeychainStoreError.securityStatus(status)
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

enum KeychainStoreError: LocalizedError {
    case emptyValue
    case securityStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .emptyValue:
            return "A Keychain value must not be empty"
        case .securityStatus(let status):
            return "Keychain operation failed (OSStatus \(status))"
        }
    }
}
