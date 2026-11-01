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
@MainActor
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

    func repository(keyProvider: APIKeyProvider? = nil) -> StationsRepository {
        StationsRepository(backend: api(keyProvider: keyProvider))
    }

    /// The fixture's Dutch stations, sorted by name.
    let dutchCodes = ["HT", "ASD", "UT", "ZL"]

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

    // MARK: - The station store

    @Test("Two callers at once share one request")
    func concurrentCallersShareOneRequest() async throws {
        let repository = repository()
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        async let first = repository.dutchStations()
        await StubURLProtocol.waitForRequests(1)
        async let count = repository.dutchStationCount()
        try await Task.sleep(for: .milliseconds(300))
        #expect(StubURLProtocol.requests.count == 1)
        StubURLProtocol.release()

        #expect(try await first.map(\.identifiers.code) == dutchCodes)
        #expect(try await count == 4)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("A second screen gets the stored list, with no new request")
    func secondConsumerGetsTheStoredList() async throws {
        let repository = repository()

        let first = try await repository.dutchStations()
        let count = try await repository.dutchStationCount()
        let again = try await repository.dutchStations()

        #expect(first.map(\.identifiers.code) == dutchCodes)
        #expect(again.map(\.identifiers.code) == dutchCodes)
        #expect(count == 4)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("A failed download isn't kept: the next call makes a request")
    func failedDownloadIsNotKept() async throws {
        StubURLProtocol.reset(replies: [.status(404), .stations])
        let repository = repository()

        await #expect(throws: NetworkError.self) {
            try await repository.dutchStations()
        }
        #expect(try await repository.dutchStations().map(\.identifiers.code) == dutchCodes)
        #expect(StubURLProtocol.requests.count == 2)
    }

    @Test("After a rejected key, the next load uses the key saved since", .requiresKeychain)
    func rejectedKeyIsNotKeptAndTheNextLoadUsesTheNewKey() async throws {
        StubURLProtocol.reset(replies: [.status(401), .stations])
        let repository = repository(keyProvider: keychainKeyProvider())

        try await keychain.saveAPIKey("rejected-test-key")
        let error = await #expect(throws: NetworkError.self) {
            try await repository.dutchStations()
        }
        guard case .unauthorized? = error else {
            Issue.record("expected .unauthorized, got \(String(describing: error))")
            return
        }
        try await keychain.saveAPIKey("accepted-test-key")

        #expect(try await repository.dutchStations().map(\.identifiers.code) == dutchCodes)
        #expect(sentKeys == ["rejected-test-key", "accepted-test-key"])
    }

    @Test("A screen that leaves mid-load doesn't cancel the download others wait for")
    func leavingScreenKeepsTheSharedDownload() async throws {
        let repository = repository()
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        let leaving = Task { try await repository.dutchStations() }
        await StubURLProtocol.waitForRequests(1)
        leaving.cancel()
        async let staying = repository.dutchStations()
        try await Task.sleep(for: .milliseconds(300))
        StubURLProtocol.release()

        #expect(try await staying.map(\.identifiers.code) == dutchCodes)
        #expect(StubURLProtocol.requests.count == 1)
        #expect(try await repository.dutchStations().map(\.identifiers.code) == dutchCodes)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("The Dutch stations come filtered and sorted by name, with their count")
    func dutchStationsAreFilteredAndSortedByName() async throws {
        let repository = repository()

        // The plain comparison the pickers use puts the apostrophe name
        // first. #25 changes the sort.
        #expect(try await repository.dutchStations().map(\.identifiers.code) == ["HT", "ASD", "UT", "ZL"])
        #expect(try await repository.dutchStationCount() == 4)
    }
}
