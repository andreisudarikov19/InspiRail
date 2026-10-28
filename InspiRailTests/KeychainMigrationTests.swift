//
//  KeychainMigrationTests.swift
//  InspiRailTests
//

import Foundation
import Security
import Testing
@testable import InspiRail

/// The Keychain service holding the NS API key was renamed from
/// `com.rnsapp.api` (#7). These tests run against the real Keychain, each
/// under its own throwaway service names.
@Suite("API key migration to the renamed Keychain service")
final class KeychainMigrationTests {
    let oldService: String
    let newService: String
    /// The app as it was before the rename: it only knows the old service.
    let oldApp: KeychainManager
    /// The app after the rename.
    let newApp: KeychainManager

    init() {
        let id = UUID().uuidString
        oldService = "test.\(id).old"
        newService = "test.\(id).new"
        oldApp = KeychainManager(service: oldService)
        newApp = KeychainManager(service: newService, legacyService: oldService)
    }

    deinit {
        removeKeychainItems(service: oldService)
        removeKeychainItems(service: newService)
    }

    @Test("A key saved before the rename is still found after it")
    func findsKeySavedBeforeRename() async throws {
        try await oldApp.saveAPIKey("key-from-1.4.1")

        #expect(try await newApp.getAPIKey() == "key-from-1.4.1")
    }

    @Test("The key moves to the new service and leaves the old one")
    func movesKeyToNewService() async throws {
        try await oldApp.saveAPIKey("key-from-1.4.1")

        _ = try await newApp.getAPIKey()

        #expect(try await KeychainManager(service: newService).getAPIKey() == "key-from-1.4.1")
        #expect(await oldApp.hasAPIKey() == false)
    }

    @Test("A key already under the new service wins, and the old copy is removed")
    func keepsKeyAlreadyUnderNewService() async throws {
        try await oldApp.saveAPIKey("stale-key")
        try await KeychainManager(service: newService).saveAPIKey("current-key")

        #expect(try await newApp.getAPIKey() == "current-key")
        #expect(await oldApp.hasAPIKey() == false)
    }

    @Test("Settings sees a key saved before the rename")
    func hasAPIKeyFindsKeySavedBeforeRename() async throws {
        try await oldApp.saveAPIKey("key-from-1.4.1")

        #expect(await newApp.hasAPIKey())
    }

    @Test("A key removed in Settings doesn't come back on the next launch")
    func removedKeyStaysRemoved() async throws {
        try await oldApp.saveAPIKey("key-from-1.4.1")

        try await newApp.deleteAPIKey()

        let nextLaunch = KeychainManager(service: newService, legacyService: oldService)
        #expect(await nextLaunch.hasAPIKey() == false)
    }
}

/// Deletes every generic-password item under `service`.
private func removeKeychainItems(service: String) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
    ]
    SecItemDelete(query as CFDictionary)
}
