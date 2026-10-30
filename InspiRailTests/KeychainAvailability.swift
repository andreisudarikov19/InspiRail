//
//  KeychainAvailability.swift
//  InspiRailTests
//

import Foundation
import Security
import Testing

/// Whether the test host can use the Keychain.
///
/// A host built without code signing (`CODE_SIGNING_ALLOWED=NO`, as CI builds
/// often are) has no entitlements, so every Keychain call fails with
/// errSecMissingEntitlement (-34018). Only that status counts as unavailable:
/// any other Keychain error still fails the tests that hit it.
enum TestKeychain {
    static let isAvailable: Bool = {
        // A lookup of an item that doesn't exist: errSecItemNotFound when the
        // Keychain works.
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "test.\(UUID().uuidString).probe",
        ]
        return SecItemCopyMatching(query as CFDictionary, nil) != errSecMissingEntitlement
    }()
}

extension Trait where Self == ConditionTrait {
    /// Skips a test, with a reason, when the test host can't use the Keychain.
    static var requiresKeychain: Self {
        .enabled(
            if: TestKeychain.isAvailable,
            "The Keychain is unavailable: the test host isn't signed (errSecMissingEntitlement, -34018)"
        )
    }
}
