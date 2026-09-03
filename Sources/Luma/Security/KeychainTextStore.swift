import Foundation
import Security

protocol SecureTextStoring {
    func set(_ text: String, for id: UUID) throws
    func text(for id: UUID) throws -> String
    func delete(for id: UUID) throws
}

enum KeychainStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "未知错误"
            return "钥匙串操作失败：\(message)（\(status)）"
        case .invalidData:
            return "钥匙串中的记录无法解码。"
        }
    }
}

final class KeychainTextStore: SecureTextStoring {
    private let service: String

    init(service: String = "com.luma.app.records") {
        self.service = service
    }

    func set(_ text: String, for id: UUID) throws {
        let account = id.uuidString
        let data = Data(text.utf8)
        let lookup: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        let update: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrLabel: "Luma 文本记录"
        ]

        let updateStatus = SecItemUpdate(lookup as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(updateStatus)
        }

        var insert = lookup
        insert[kSecValueData] = data
        insert[kSecAttrLabel] = "Luma 文本记录"
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(addStatus)
        }
    }

    func text(for id: UUID) throws -> String {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id.uuidString,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data, let text = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidData
        }
        return text
    }

    func delete(for id: UUID) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: id.uuidString
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
    }
}
