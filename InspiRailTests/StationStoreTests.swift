//
//  StationStoreTests.swift
//  InspiRailTests
//

import Foundation
import Testing
@testable import InspiRail

/// The app's one API session and station store (#18). Every request goes to
/// `StubURLProtocol`, never to the network. The stub's state is shared, so
/// the suite is serialized. Tests that store a key use the real Keychain,
/// under a throwaway service, and are skipped when the test host isn't signed.
@Suite("Station store", .serialized)
final class StationStoreTests {
    let service: String
    let keychain: KeychainManager

    init() {
        StubURLProtocol.reset()
        service = "test.\(UUID().uuidString).stations"
        keychain = KeychainManager(service: service)
    }

    deinit {
        removeKeychainItems(service: service)
    }

    /// Supplies `test-key` through the environment override, with or without
    /// a usable Keychain.
    func environmentKeyProvider() -> APIKeyProvider {
        APIKeyProvider(keychain: keychain, environment: ["NS_API_KEY": "test-key"], allowsEnvironmentOverride: true)
    }

    /// Reads the key from the Keychain only, as Release builds do.
    func keychainKeyProvider() -> APIKeyProvider {
        APIKeyProvider(keychain: keychain, environment: [:], allowsEnvironmentOverride: false)
    }

    func api(keyProvider: APIKeyProvider? = nil) -> BackendAPI {
        BackendAPI(
            keyProvider: keyProvider ?? environmentKeyProvider(),
            sessionConfiguration: StubURLProtocol.configuration()
        )
    }

    var sentKeys: [String?] {
        StubURLProtocol.requests.map { $0.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") }
    }

    // MARK: - The API session

    @Test("The session keeps no URL cache, since its requests ignore cached data")
    func sessionKeepsNoURLCache() async {
        let configuration = await api().session.configuration

        #expect(configuration.urlCache == nil)
        #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
    }

    @Test("A key saved after a request is used by the next request on the same API", .requiresKeychain)
    func changedKeyIsUsedByTheNextRequest() async throws {
        let api = api(keyProvider: keychainKeyProvider())

        try await keychain.saveAPIKey("first-test-key")
        _ = try await api.getStations()
        try await keychain.saveAPIKey("second-test-key")
        _ = try await api.getStations()

        #expect(sentKeys == ["first-test-key", "second-test-key"])
    }
}
