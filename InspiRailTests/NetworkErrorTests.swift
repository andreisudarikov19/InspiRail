//
//  NetworkErrorTests.swift
//  InspiRailTests
//

import Foundation
import Security
import Testing
@testable import InspiRail

/// What a failed station load is reported as (#20). These tests extend the
/// serialized "Station store" suite, since they share its stub, and never
/// reach the network.
extension StationStoreTests {
    /// Reads the key from `storage` only, as Release builds read the Keychain.
    func provider(_ storage: TestKeyStorage) -> APIKeyProvider {
        APIKeyProvider(keychain: storage, environment: [:], allowsEnvironmentOverride: false)
    }

    /// The `NetworkError` a load through `api` throws. Records an issue when
    /// it throws none, or another error.
    func networkError(from api: BackendAPI) async -> NetworkError? {
        await #expect(throws: NetworkError.self) {
            try await api.getStations()
        }
    }

    // MARK: - One case per cause

    @Test("A 401 means NS rejected the key")
    func keyRejectedFor401() async {
        StubURLProtocol.reset(replies: [.status(401)])

        #expect(await networkError(from: api()) == .keyRejected)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("A 403 means NS refused the key, which may be over its quota")
    func forbiddenFor403() async {
        StubURLProtocol.reset(replies: [.status(403)])

        #expect(await networkError(from: api()) == .forbidden)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("A 404, or another status the app doesn't expect, means unreadable data")
    func otherStatusIsUnreadableData() async {
        StubURLProtocol.reset(replies: [.status(404)])

        #expect(await networkError(from: api()) == .unreadableData)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("A success whose body doesn't decode means unreadable data")
    func undecodableReplyIsUnreadableData() async {
        StubURLProtocol.reset(replies: [.body("{}")])

        #expect(await networkError(from: api()) == .unreadableData)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("A transport failure means NS can't be reached, never an NS outage", arguments: [
        URLError.Code.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
        .dnsLookupFailed, .cannotConnectToHost, .secureConnectionFailed, .serverCertificateUntrusted,
    ])
    func transportFailuresMeanOffline(code: URLError.Code) async {
        StubURLProtocol.reset(replies: [.failure(code)])

        #expect(await networkError(from: api()) == .offline(code))
    }

    @Test("A cancelled request passes through as a cancellation, not an error")
    func cancelledRequestPassesThroughAsCancellation() async {
        StubURLProtocol.reset(replies: [.failure(.cancelled)])
        let api = api()

        await #expect(throws: CancellationError.self) {
            try await api.getStations()
        }
    }

    @Test("With no key stored, the load fails as no key, and nothing is sent")
    func noStoredKeyIsNoKey() async {
        let api = api(keyProvider: provider(TestKeyStorage()))

        #expect(await networkError(from: api) == .noKey)
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test("When the Keychain can't be read, the load fails as Keychain unavailable, and nothing is sent")
    func unreadableKeychainIsKeychainUnavailable() async {
        let storage = TestKeyStorage(failure: .retrievalFailed(errSecInteractionNotAllowed))
        let api = api(keyProvider: provider(storage))

        #expect(await networkError(from: api) == .keychainUnavailable)
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test("Each error has its own message, and a cancellation has none")
    func eachErrorHasItsMessage() {
        let messages: [(NetworkError, String)] = [
            (.noKey, "No NS API key is set. Add one in Settings."),
            (.keychainUnavailable, "Your NS API key can't be read right now. Try again in a moment."),
            (.keyRejected, "NS didn't accept your API key. Check it in Settings."),
            (.forbidden, "NS refused your API key. It may be over its usage limit. Try again later."),
            (.tooManyRequests, "NS is getting too many requests. Try again in a minute."),
            (.serviceUnavailable(status: 503), "NS isn't available right now. Try again later."),
            (.offline(.cannotFindHost), "Can't reach NS. Check your internet connection."),
            (.unreadableData, "NS sent data this version of InspiRail can't read. Try again later."),
            (.invalidURL, "Invalid URL"),
        ]
        for (error, text) in messages {
            #expect(NetworkError.message(for: error) == text)
        }
        #expect(NetworkError.message(for: CancellationError()) == nil)
        #expect(NetworkError.message(for: URLError(.cancelled)) == nil)
        #expect(NetworkError.message(for: CocoaError(.fileNoSuchFile)) == "Couldn't load stations. Try again later.")

        let keyCases: [NetworkError] = [.noKey, .keychainUnavailable, .keyRejected, .forbidden]
        #expect(messages.map(\.0).filter(\.concernsTheKey) == keyCases)
    }
}

/// An API key store in memory: empty, holding a key, or failing as the
/// Keychain can. Needs no Keychain.
actor TestKeyStorage: APIKeyStorage {
    private var key: String?
    private let failure: KeychainError?

    init(key: String? = nil, failure: KeychainError? = nil) {
        self.key = key
        self.failure = failure
    }

    func setKey(_ key: String) {
        self.key = key
    }

    func getAPIKey() throws -> String {
        if let failure { throw failure }
        guard let key else { throw KeychainError.notFound }
        return key
    }

    func saveAPIKey(_ key: String) {
        self.key = key
    }
}
