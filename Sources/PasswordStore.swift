import Foundation
import Security

protocol PasswordStoring {
    func isSaved() throws -> Bool
    func save(_ password: String) throws
    func read() throws -> String
    func delete() throws
}

struct PasswordStoreError: LocalizedError {
    let code: OSStatus
    var errorDescription: String? {
        if code == errSecItemNotFound { return "No password is saved. Save one in AIPromptBridge or use manual input." }
        return "Keychain could not complete the request (\(code)). Unlock or authorize access directly in macOS, then try again."
    }
}

/// Local macOS Keychain item. No secret is written to preferences or returned by IPC.
/// File-based Keychain supports the project's locally signed macOS builds.
final class KeychainPasswordStore: PasswordStoring {
    let service: String
    init(service: String = "io.github.bj97301.aipromptbridge.saved-password") { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service, kSecAttrAccount as String: "default",
         kSecUseDataProtectionKeychain as String: false,
         kSecAttrSynchronizable as String: false,
         kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
    }

    func isSaved() throws -> Bool {
        var attributes = query
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        attributes[kSecReturnAttributes as String] = true
        let status = SecItemCopyMatching(attributes as CFDictionary, nil)
        if status == errSecItemNotFound { return false }
        guard status == errSecSuccess else { throw PasswordStoreError(code: status) }
        return true
    }

    func save(_ password: String) throws {
        guard !password.isEmpty, password.utf8.count <= 16_384 else { throw BridgeInputError("invalid_request", "Enter between 1 and 16384 UTF-8 bytes.") }
        var bytes = Data(password.utf8)
        defer { bytes.resetBytes(in: bytes.startIndex..<bytes.endIndex) }
        let updated = SecItemUpdate(query as CFDictionary, [kSecValueData as String: bytes] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw PasswordStoreError(code: updated) }
        var access: SecAccess?
        // A nil trusted list means only the creating app, never all applications.
        let created = SecAccessCreate("AIPromptBridge saved password" as CFString, nil, &access)
        guard created == errSecSuccess, let access else { throw PasswordStoreError(code: created) }
        var attributes = query
        attributes[kSecAttrLabel as String] = "AIPromptBridge saved password"
        attributes[kSecAttrAccess as String] = access
        attributes[kSecValueData as String] = bytes
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw PasswordStoreError(code: status) }
    }

    func read() throws -> String {
        var attributes = query
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        attributes[kSecReturnData as String] = true
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        guard status == errSecSuccess else { throw PasswordStoreError(code: status) }
        guard var bytes = item as? Data else { throw PasswordStoreError(code: errSecDecode) }
        defer { bytes.resetBytes(in: bytes.startIndex..<bytes.endIndex) }
        guard let value = String(data: bytes, encoding: .utf8), !value.isEmpty, bytes.count <= 16_384 else {
            throw PasswordStoreError(code: errSecDecode)
        }
        return value
    }

    func delete() throws {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PasswordStoreError(code: status) }
    }
}
