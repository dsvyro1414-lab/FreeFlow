import Foundation
import FreeFlowCore
import Security

enum KeychainStoreError: LocalizedError {
  case unexpectedStatus(OSStatus)

  var errorDescription: String? {
    switch self {
    case .unexpectedStatus(let status):
      SecCopyErrorMessageString(status, nil) as String?
        ?? "Keychain error \(status)"
    }
  }
}

enum KeychainStore {
  static func save(_ value: String, service: String, account: String) throws {
    let data = Data(value.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]

    let updateStatus = SecItemUpdate(
      query as CFDictionary,
      [kSecValueData as String: data] as CFDictionary
    )
    switch KeychainReplacementPolicy.afterUpdate(
      status: updateStatus,
      success: errSecSuccess,
      itemNotFound: errSecItemNotFound
    ) {
    case .complete:
      return
    case .add:
      break
    case .retryUpdate:
      throw KeychainStoreError.unexpectedStatus(updateStatus)
    case .fail(let status):
      throw KeychainStoreError.unexpectedStatus(status)
    }

    var attributes = query
    attributes[kSecValueData as String] = data
    attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    let addStatus = SecItemAdd(attributes as CFDictionary, nil)
    switch KeychainReplacementPolicy.afterAdd(
      status: addStatus,
      success: errSecSuccess,
      duplicateItem: errSecDuplicateItem
    ) {
    case .complete:
      return
    case .retryUpdate:
      // Another writer may create the same item between the update and add.
      // Resolve that race without deleting the value that won it.
      let retryStatus = SecItemUpdate(
        query as CFDictionary,
        [kSecValueData as String: data] as CFDictionary
      )
      guard retryStatus == errSecSuccess else {
        throw KeychainStoreError.unexpectedStatus(retryStatus)
      }
      return
    case .add:
      throw KeychainStoreError.unexpectedStatus(addStatus)
    case .fail(let status):
      throw KeychainStoreError.unexpectedStatus(status)
    }
  }

  static func read(service: String, account: String) throws -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = result as? Data else {
      throw KeychainStoreError.unexpectedStatus(status)
    }
    return String(data: data, encoding: .utf8)
  }

  static func delete(service: String, account: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainStoreError.unexpectedStatus(status)
    }
  }
}
