//
//  APIKeyProviderTests.swift
//  InspiRailTests
//

import Foundation
import Testing
@testable import InspiRail

/// The API key comes from the Keychain or, in Debug builds, the `NS_API_KEY`
/// environment variable (#14). These tests run against the real Keychain,
/// each under its own throwaway service name.
@Suite("API key sources")
final class APIKeyProviderTests {
    let service: String
    let keychain: KeychainManager

    init() {
        service = "test.\(UUID().uuidString).provider"
        keychain = KeychainManager(service: service)
    }

    deinit {
        removeKeychainItems(service: service)
    }

    func provider(environment: [String: String] = [:], allowsEnvironmentOverride: Bool = true) -> APIKeyProvider {
        APIKeyProvider(keychain: keychain, environment: environment, allowsEnvironmentOverride: allowsEnvironmentOverride)
    }

    @Test("A stored key is used when the environment has none")
    func storedKeyIsUsed() async throws {
        try await keychain.saveAPIKey("stored")

        #expect(try await provider().currentKey() == "stored")
    }

    @Test("In Debug builds the environment variable wins over a stored key and replaces it")
    func debugEnvironmentWinsAndIsSaved() async throws {
        try await keychain.saveAPIKey("stale")

        #expect(try await provider(environment: ["NS_API_KEY": "fresh"]).currentKey() == "fresh")
        #expect(try await keychain.getAPIKey() == "fresh")
    }

    @Test("The environment variable primes an empty Keychain")
    func environmentPrimesEmptyKeychain() async throws {
        #expect(try await provider(environment: ["NS_API_KEY": "fresh"]).currentKey() == "fresh")
        #expect(try await keychain.getAPIKey() == "fresh")
    }

    @Test("Release builds ignore the environment variable")
    func releaseIgnoresEnvironment() async throws {
        try await keychain.saveAPIKey("stored")

        let release = provider(environment: ["NS_API_KEY": "fresh"], allowsEnvironmentOverride: false)
        #expect(try await release.currentKey() == "stored")
        #expect(try await keychain.getAPIKey() == "stored")
    }

    @Test("A blank environment variable counts as unset")
    func blankEnvironmentIsUnset() async throws {
        try await keychain.saveAPIKey("stored")

        #expect(try await provider(environment: ["NS_API_KEY": "   "]).currentKey() == "stored")
    }

    @Test("The provider reports when the environment variable supplies the key")
    func reportsEnvironmentKeyInUse() {
        #expect(provider(environment: ["NS_API_KEY": "fresh"]).usesEnvironmentKey)
        #expect(!provider().usesEnvironmentKey)
        #expect(!provider(environment: ["NS_API_KEY": "   "]).usesEnvironmentKey)
        #expect(!provider(environment: ["NS_API_KEY": "fresh"], allowsEnvironmentOverride: false).usesEnvironmentKey)
    }

    @Test("With no key anywhere, the request is unauthorized")
    func noKeyThrowsUnauthorized() async throws {
        let error = await #expect(throws: NetworkError.self) {
            try await self.provider().currentKey()
        }
        guard case .unauthorized? = error else {
            Issue.record("expected .unauthorized, got \(String(describing: error))")
            return
        }
    }
}
