//
//  KeychainManager.swift
//  InspiRail
//
//  Secure API key storage using Keychain Services
//

import Foundation
import Security
import OSLog

/// Manages secure storage of sensitive data in the iOS Keychain
actor KeychainManager {
    /// Both names identify data stored on users' devices. Changing either
    /// one without migrating the stored key loses every user's key.
    static let shared = KeychainManager(
        service: "annisu.inspirail.api",
        legacyService: "com.rnsapp.api"   // used up to 1.4.1
    )
    
    private let logger = Logger(subsystem: AppConfiguration.subsystem, category: "security")
    
    // Keychain constants
    private let service: String
    private let legacyService: String?
    private let apiKeyAccount = "ns-api-key"
    
    /// - Parameters:
    ///   - service: The Keychain service the API key is stored under.
    ///   - legacyService: The service an earlier version of the app stored the
    ///     key under, if it differs; a key found there moves to `service`.
    init(service: String, legacyService: String? = nil) {
        self.service = service
        self.legacyService = legacyService
    }
    
    // MARK: - API Key Methods
    
    /// Save API key securely to Keychain
    func saveAPIKey(_ key: String) async throws {
        let data = Data(key.utf8)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        // Delete any existing item first
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            logger.error("Failed to save API key: \(status)")
            throw KeychainError.saveFailed(status)
        }
        
        logger.debug("✅ API key saved to Keychain")
    }
    
    /// Retrieve API key from Keychain
    func getAPIKey() async throws -> String {
        migrateLegacyKeyIfNeeded()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                throw KeychainError.notFound
            }
            logger.error("Failed to retrieve API key: \(status)")
            throw KeychainError.retrievalFailed(status)
        }
        
        guard let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return key
    }
    
    /// Delete API key from Keychain
    func deleteAPIKey() async throws {
        // Clear the legacy service too, so a key removed here can't be
        // migrated back on the next launch.
        for itemService in [service, legacyService].compactMap({ $0 }) {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: itemService,
                kSecAttrAccount as String: apiKeyAccount
            ]
            
            let status = SecItemDelete(query as CFDictionary)
            
            guard status == errSecSuccess || status == errSecItemNotFound else {
                logger.error("Failed to delete API key: \(status)")
                throw KeychainError.deleteFailed(status)
            }
        }
        
        logger.debug("🗑️ API key deleted from Keychain")
    }
    
    /// Check if API key exists in Keychain
    func hasAPIKey() async -> Bool {
        migrateLegacyKeyIfNeeded()
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount,
            kSecReturnData as String: false
        ]
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess
    }
    
    // MARK: - Legacy Service Migration
    
    private var legacyKeyChecked = false
    
    /// Moves an API key stored under `legacyService` to `service`. A key
    /// already under `service` wins. The legacy copy is deleted only once the
    /// key is safely under `service`; on any Keychain error everything stays
    /// as it is, and the next call tries again.
    private func migrateLegacyKeyIfNeeded() {
        guard !legacyKeyChecked, let legacyService else { return }
        
        let legacyItem: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyService,
            kSecAttrAccount as String: apiKeyAccount
        ]
        
        var lookup = legacyItem
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let legacyStatus = SecItemCopyMatching(lookup as CFDictionary, &result)
        if legacyStatus == errSecItemNotFound {
            legacyKeyChecked = true
            return
        }
        guard legacyStatus == errSecSuccess, let data = result as? Data else {
            logger.error("Failed to read the API key under the legacy Keychain service: \(legacyStatus)")
            return
        }
        
        let currentItem: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: apiKeyAccount
        ]
        let currentStatus = SecItemCopyMatching(currentItem as CFDictionary, nil)
        switch currentStatus {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            var newItem = currentItem
            newItem[kSecValueData as String] = data
            newItem[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(newItem as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                logger.error("Failed to move the API key to the renamed Keychain service: \(addStatus)")
                return
            }
            logger.info("Moved the API key to the renamed Keychain service")
        default:
            logger.error("Failed to check the renamed Keychain service: \(currentStatus)")
            return
        }
        
        SecItemDelete(legacyItem as CFDictionary)
        legacyKeyChecked = true
    }
    
    // MARK: - Generic Keychain Storage
    
    /// Save any string value securely
    func save(_ value: String, forKey key: String) async throws {
        let data = Data(value.utf8)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }
    
    /// Retrieve any string value
    func get(forKey key: String) async throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess else {
            throw status == errSecItemNotFound ? KeychainError.notFound : KeychainError.retrievalFailed(status)
        }
        
        guard let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            throw KeychainError.invalidData
        }
        
        return value
    }
    
    /// Delete any value
    func delete(forKey key: String) async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

// MARK: - Keychain Error

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)
    case retrievalFailed(OSStatus)
    case deleteFailed(OSStatus)
    case notFound
    case invalidData
    
    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save to Keychain (status: \(status))"
        case .retrievalFailed(let status):
            return "Failed to retrieve from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete from Keychain (status: \(status))"
        case .notFound:
            return "Item not found in Keychain"
        case .invalidData:
            return "Invalid data format in Keychain"
        }
    }
}
