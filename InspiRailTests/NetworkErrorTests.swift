//
//  NetworkErrorTests.swift
//  InspiRailTests
//

import CryptoKit
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

    @Test("A load whose task is cancelled mid-request passes through as a cancellation, and isn't reported")
    func cancelledRequestPassesThroughAsCancellation() async {
        let api = api()
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        let load = Task { try await api.getStations() }
        await StubURLProtocol.waitForRequests(1)
        load.cancel()

        await #expect(throws: CancellationError.self) {
            try await load.value
        }
        #expect(StubURLProtocol.requests.count == 1)
        #expect(failures.values.isEmpty)
    }

    @Test("A request the system cancels, when no task asked, means NS can't be reached")
    func requestCancelledByTheSystemIsOffline() async {
        StubURLProtocol.reset(replies: [.failure(.cancelled)])

        #expect(await networkError(from: api()) == .offline(.cancelled))
        #expect(StubURLProtocol.requests.count == 1)
        #expect(failures.values == [.offline(.cancelled)])
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

    // MARK: - Retries

    /// The error a 429 or 5xx ends in.
    func failure(forStatus status: Int) -> NetworkError {
        status == 429 ? .tooManyRequests : .serviceUnavailable(status: status)
    }

    @Test("A 429 or 5xx is tried at most three times, 1 s and then 2 s apart", arguments: [429, 500, 502, 503, 504])
    func retriedAtMostThreeTimes(status: Int) async {
        StubURLProtocol.reset(replies: [.status(status)])

        #expect(await networkError(from: api()) == failure(forStatus: status))
        #expect(StubURLProtocol.requests.count == 3)
        #expect(sleeps.values == [1, 2])
    }

    @Test("A 429 or 503 waits as long as Retry-After asks, in seconds, up to 10", arguments: [429, 503], ["7", "10"])
    func retryAfterInSecondsIsHonoured(status: Int, value: String) async throws {
        StubURLProtocol.reset(replies: [.status(status, headers: ["Retry-After": value]), .stations])

        _ = try await api().getStations()
        #expect(sleeps.values == [TimeInterval(value)!])
        #expect(StubURLProtocol.requests.count == 2)
    }

    @Test("A 429 or 503 waits until the date Retry-After names", arguments: [429, 503])
    func retryAfterAsADateIsHonoured(status: Int) async throws {
        // Seven seconds after the test clock's start.
        StubURLProtocol.reset(replies: [.status(status, headers: ["Retry-After": "Mon, 01 Jan 2001 00:00:07 GMT"]), .stations])

        _ = try await api().getStations()
        #expect(sleeps.values == [7])
        #expect(StubURLProtocol.requests.count == 2)
    }

    @Test("A Retry-After longer than 10 s fails at once", arguments: [429, 503], ["11", "Mon, 01 Jan 2001 00:00:11 GMT"])
    func retryAfterOverTheCapFailsAtOnce(status: Int, value: String) async {
        StubURLProtocol.reset(replies: [.status(status, headers: ["Retry-After": value]), .stations])

        #expect(await networkError(from: api()) == failure(forStatus: status))
        #expect(StubURLProtocol.requests.count == 1)
        #expect(sleeps.values.isEmpty)
    }

    @Test("A refused key, a missing resource and unreadable data aren't retried", arguments: [
        StubURLProtocol.Reply.status(401), .status(403), .status(404), .body("{}"),
    ])
    func refusedMissingAndUnreadableAreNotRetried(reply: StubURLProtocol.Reply) async {
        StubURLProtocol.reset(replies: [reply, .stations])

        _ = await networkError(from: api())
        #expect(StubURLProtocol.requests.count == 1)
        #expect(sleeps.values.isEmpty)
    }

    @Test("A lost connection, or a failed lookup or connection, is retried", arguments: [
        URLError.Code.networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
    ])
    func transientFailuresAreRetried(code: URLError.Code) async {
        StubURLProtocol.reset(replies: [.failure(code)])

        #expect(await networkError(from: api()) == .offline(code))
        #expect(StubURLProtocol.requests.count == 3)
        #expect(sleeps.values == [1, 2])
    }

    @Test("No internet, a timeout or a TLS failure isn't retried", arguments: [
        URLError.Code.notConnectedToInternet, .timedOut, .secureConnectionFailed, .serverCertificateUntrusted,
    ])
    func otherTransportFailuresAreNotRetried(code: URLError.Code) async {
        StubURLProtocol.reset(replies: [.failure(code)])

        #expect(await networkError(from: api()) == .offline(code))
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("Cancelling a load while it waits stops the retries, as a cancellation")
    func cancellationDuringAWaitStopsTheLoop() async throws {
        StubURLProtocol.reset(replies: [.status(503, headers: ["Retry-After": "5"])])
        let sleeps = sleeps
        let api = api(sleep: { seconds in
            sleeps.append(seconds)
            try await Task.sleep(for: .seconds(3600))
        })

        let load = Task { try await api.getStations() }
        for _ in 0..<500 where sleeps.values.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        load.cancel()

        await #expect(throws: CancellationError.self) {
            try await load.value
        }
        #expect(sleeps.values == [5])
        #expect(StubURLProtocol.requests.count == 1)
        #expect(failures.values.isEmpty)
    }

    @Test("A failed load is reported once, not once per attempt")
    func failureIsReportedOncePerLoad() async throws {
        let api = api()

        StubURLProtocol.reset(replies: [.status(503)])
        _ = await networkError(from: api)
        #expect(failures.values == [.serviceUnavailable(status: 503)])

        StubURLProtocol.reset(replies: [.status(429), .stations])
        _ = try await api.getStations()
        #expect(failures.values.count == 1)

        // Two screens sharing one failed download: one more report.
        StubURLProtocol.reset(replies: [.status(503)])
        let repository = StationsRepository(backend: api)
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }
        async let first = try? repository.dutchStations()
        await StubURLProtocol.waitForRequests(1)
        async let second = try? repository.dutchStations()
        try await Task.sleep(for: .milliseconds(300))
        StubURLProtocol.release()
        _ = await (first, second)
        #expect(failures.values.count == 2)
        #expect(StubURLProtocol.requests.count == 3)
    }

    @Test("Loads in quick succession aren't held back")
    func manyLoadsInAMinuteAreNotHeldBack() async {
        StubURLProtocol.reset(replies: [.status(404)])
        let api = api()
        let start = Date()

        for _ in 0..<31 {
            _ = await networkError(from: api)
        }
        #expect(StubURLProtocol.requests.count == 31)
        #expect(sleeps.values.isEmpty)
        #expect(Date().timeIntervalSince(start) < 5)
    }

    // MARK: - A refused key

    @Test("After a 401 the same key isn't sent again, by the store or by Settings' key check")
    func rejectedKeyIsNotSentAgain() async throws {
        StubURLProtocol.reset(replies: [.status(401), .stations])
        let repository = StationsRepository(backend: api(keyProvider: provider(TestKeyStorage(key: "rejected-test-key"))))

        await #expect(throws: NetworkError.keyRejected) { try await repository.dutchStations() }
        await #expect(throws: NetworkError.keyRejected) { try await repository.dutchStations() }
        await #expect(throws: NetworkError.keyRejected) { try await repository.backend.getStations() }

        #expect(StubURLProtocol.requests.count == 1)
        #expect(failures.values == [.keyRejected, .keyRejected, .keyRejected])
        let refusal = try #require(await repository.keyRefusal)
        #expect(refusal.reason == .rejected)
        #expect(refusal.until == refusal.since + AppConfiguration.API.refusedKeyPause)
    }

    @Test("After a 401 or 403, another key is sent at once", arguments: [401, 403])
    func changedKeyIsSentAfterARefusal(status: Int) async throws {
        StubURLProtocol.reset(replies: [.status(status), .stations])
        let storage = TestKeyStorage(key: "refused-test-key")
        let repository = StationsRepository(backend: api(keyProvider: provider(storage)))

        await #expect(throws: NetworkError.self) { try await repository.dutchStations() }
        await storage.setKey("accepted-test-key")

        #expect(try await repository.dutchStations().map(\.identifiers.code) == dutchCodes)
        #expect(sentKeys == ["refused-test-key", "accepted-test-key"])
        #expect(await repository.keyRefusal == nil)
    }

    /// The error a load with a key refused with `status` fails with.
    func refusedKeyError(forStatus status: Int) -> NetworkError {
        status == 401 ? .keyRejected : .forbidden
    }

    @Test("After a 401 or 403 the same key is sent again once the 15-minute pause ends", arguments: [401, 403])
    func refusedKeyPausesUntilTheCoolOffEnds(status: Int) async throws {
        StubURLProtocol.reset(replies: [.status(status), .stations])
        let repository = StationsRepository(backend: api(keyProvider: provider(TestKeyStorage(key: "refused-test-key"))))
        let error = refusedKeyError(forStatus: status)

        await #expect(throws: error) { try await repository.dutchStations() }
        clock.advance(by: AppConfiguration.API.refusedKeyPause - 1)
        await #expect(throws: error) { try await repository.dutchStations() }
        #expect(StubURLProtocol.requests.count == 1)

        clock.advance(by: 1)
        #expect(try await repository.dutchStations().map(\.identifiers.code) == dutchCodes)
        #expect(StubURLProtocol.requests.count == 2)
        #expect(await repository.keyRefusal == nil)
    }

    @Test("After a 401 or 403, saving the same key again sends it at once", arguments: [401, 403])
    func sameKeySavedAgainIsSentAfterARefusal(status: Int) async throws {
        StubURLProtocol.reset(replies: [.status(status), .stations])
        let storage = TestKeyStorage(key: "refused-test-key")
        let repository = StationsRepository(backend: api(keyProvider: provider(storage)))

        await #expect(throws: refusedKeyError(forStatus: status)) { try await repository.dutchStations() }
        // What Settings does when a key is saved.
        await storage.saveAPIKey("refused-test-key")
        await repository.backend.forgetKeyRefusal()

        #expect(try await repository.dutchStations().map(\.identifiers.code) == dutchCodes)
        #expect(sentKeys == ["refused-test-key", "refused-test-key"])
        #expect(await repository.keyRefusal == nil)
    }

    @Test("A late success for an old key leaves the refusal of the key saved since")
    func lateSuccessForAnOldKeyKeepsANewerRefusal() async throws {
        StubURLProtocol.reset(replies: [.stations, .status(401)])
        let storage = TestKeyStorage(key: "old-test-key")
        let api = api(keyProvider: provider(storage))
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        // The old key's load waits for its answer while NS rejects the new key.
        let oldLoad = Task { try await api.getStations() }
        await StubURLProtocol.waitForRequests(1)
        await storage.setKey("new-test-key")
        StubURLProtocol.stopHolding()
        #expect(await networkError(from: api) == .keyRejected)
        StubURLProtocol.release()
        _ = try await oldLoad.value

        #expect(await api.keyRefusal?.reason == .rejected)
        #expect(await networkError(from: api) == .keyRejected)
        #expect(sentKeys == ["old-test-key", "new-test-key"])
    }

    @Test("A late success for the refused key itself clears its refusal")
    func lateSuccessForTheRefusedKeyClearsItsRefusal() async throws {
        StubURLProtocol.reset(replies: [.stations, .status(401), .stations])
        let api = api(keyProvider: provider(TestKeyStorage(key: "flaky-test-key")))
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        // Two loads with the same key: NS rejects the second, then accepts
        // the first.
        let firstLoad = Task { try await api.getStations() }
        await StubURLProtocol.waitForRequests(1)
        StubURLProtocol.stopHolding()
        #expect(await networkError(from: api) == .keyRejected)
        StubURLProtocol.release()
        _ = try await firstLoad.value

        #expect(await api.keyRefusal == nil)
        _ = try await api.getStations()
        #expect(StubURLProtocol.requests.count == 3)
    }

    @Test("The refused-key memory shows nothing of the key, not even its hash")
    func keyRefusalHoldsNothingOfTheKey() async throws {
        let key = "QWERTY-test-key"
        StubURLProtocol.reset(replies: [.status(401)])
        let api = api(keyProvider: provider(TestKeyStorage(key: key)))
        _ = await networkError(from: api)

        let refusal = try #require(await api.keyRefusal)
        var dumped = ""
        dump(refusal, to: &dumped)
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        for text in [String(describing: refusal), String(reflecting: refusal), dumped] {
            #expect(!text.contains("QWERTY"))
            #expect(!text.lowercased().contains(hash.prefix(12)))
        }
    }

    // MARK: - Stations that can't be read

    @Test("The fixture, in the documented shape with extra keys, decodes in full")
    func documentedShapeFixtureDecodes() async throws {
        let response = try await api().getStations()

        #expect(response.payload.map(\.identifiers.code) == ["UT", "ASD", "HT", "ZL", "BHF", "BRUZ"])
        #expect(response.skipped.isEmpty)
        let denBosch = try #require(response.payload.first { $0.identifiers.code == "HT" })
        #expect(denBosch.names.long == "'s-Hertogenbosch")
        #expect(denBosch.names.synonyms?.first == "Den Bosch")
        #expect(response.payload.first { $0.identifiers.code == "BHF" }?.country == "D")
        let utrecht = try #require(response.payload.first)
        #expect(utrecht.tracks?.isEmpty == false)
        #expect(utrecht.hasKnownFacilities == true)
    }

    @Test("A station that can't be read is skipped, by its code, and the rest load")
    func malformedStationIsSkippedAndTheRestLoad() async throws {
        StubURLProtocol.reset(replies: [.body("""
        {"payload":[
        {"id":{"code":"UT"},"stationType":"MEGA_STATION","names":{"long":"Utrecht Centraal","medium":"Utrecht C.","short":"Utrecht C"},"location":{"lat":52.08901,"lng":5.110268},"country":"NL"},
        {"id":{"code":"BAD"},"stationType":"STOPTREIN_STATION","names":{"long":"Broken","medium":"Broken","short":"Broken"},"country":"NL"},
        null,
        {"stationType":"STOPTREIN_STATION","names":{"long":"No Code","medium":"No Code","short":"No Code"},"location":{"lat":52.0,"lng":5.0},"country":"NL"},
        {"id":{"code":"NM"},"stationType":"INTERCITY_STATION","names":{"long":"Nijmegen","short":"Nijmegen"},"location":{"lat":51.84376,"lng":5.85276},"country":"NL"},
        {"id":{"code":"ASD"},"stationType":"MEGA_STATION","names":{"long":"Amsterdam Centraal","medium":"Amsterdam C.","short":"Amsterdm C"},"location":{"lat":52.37888,"lng":4.900277},"country":"NL"}
        ]}
        """)])

        let response = try await api().getStations()
        #expect(response.payload.map(\.identifiers.code) == ["UT", "NM", "ASD"])
        #expect(response.skipped == [
            SkippedStation(code: "BAD", field: "location"),
            SkippedStation(code: nil, field: ""),
            SkippedStation(code: nil, field: "id"),
        ])
        #expect(try await repository().dutchStations().map(\.identifiers.code) == ["ASD", "NM", "UT"])
    }

    @Test("A list where no station can be read, or an empty one, is unreadable data, and isn't kept", arguments: [
        #"{"payload":[{"id":{"code":"BAD"}},null]}"#,
        #"{"payload":[]}"#,
    ])
    func listWhereNothingDecodesIsUnreadable(body: String) async throws {
        StubURLProtocol.reset(replies: [.body(body), .stations])
        let repository = repository()

        await #expect(throws: NetworkError.unreadableData) { try await repository.dutchStations() }
        #expect(try await repository.dutchStations().map(\.identifiers.code) == dutchCodes)
        #expect(StubURLProtocol.requests.count == 2)
    }

    @Test("A list whose Dutch stations can't be read, though others can, is unreadable data, reported once and not kept")
    func listWithNoReadableDutchStationIsUnreadable() async throws {
        // Utrecht has no location and Amsterdam's is in text, which the map
        // can't use. Berlin is whole.
        StubURLProtocol.reset(replies: [.body("""
        {"payload":[
        {"id":{"code":"UT"},"stationType":"MEGA_STATION","names":{"long":"Utrecht Centraal","short":"Utrecht C"},"country":"NL"},
        {"id":{"code":"ASD"},"stationType":"MEGA_STATION","names":{"long":"Amsterdam Centraal","short":"Amsterdm C"},"location":{"lat":"52.37888","lng":"4.900277"},"country":"NL"},
        {"id":{"code":"BHF"},"stationType":"MEGA_STATION","names":{"long":"Berlin Hbf","short":"Berlin Hbf"},"location":{"lat":52.52508,"lng":13.369402},"country":"D"}
        ]}
        """), .stations])
        let repository = repository()

        await #expect(throws: NetworkError.unreadableData) { try await repository.dutchStations() }
        #expect(failures.values == [.unreadableData])
        #expect(try await repository.dutchStations().map(\.identifiers.code) == dutchCodes)
        #expect(StubURLProtocol.requests.count == 2)
    }

    @Test("Dutch stations whose unused fields changed type, such as tracks as numbers, still load")
    func unusedFieldsOfAnotherTypeDontSkipAStation() async throws {
        // Every station's tracks are numbers. Utrecht's UIC code is a number
        // too, and Amsterdam's medium name an object. No screen uses these.
        StubURLProtocol.reset(replies: [.body("""
        {"payload":[
        {"id":{"code":"UT","uicCode":8400621},"stationType":"MEGA_STATION","names":{"long":"Utrecht Centraal","medium":"Utrecht C.","short":"Utrecht C"},"location":{"lat":52.08901,"lng":5.110268},"tracks":[5,7,11],"hasKnownFacilities":true,"country":"NL"},
        {"id":{"code":"ASD","uicCode":"8400058"},"stationType":"MEGA_STATION","names":{"long":"Amsterdam Centraal","medium":{"text":"Amsterdam C."},"short":"Amsterdm C"},"location":{"lat":52.37888,"lng":4.900277},"tracks":[2,4],"country":"NL"},
        {"id":{"code":"HT","uicCode":"8400319"},"stationType":"KNOOPPUNT_INTERCITY_STATION","names":{"long":"'s-Hertogenbosch","medium":"'s-Hertogenb.","short":"Den Bosch","synonyms":["Den Bosch"]},"location":{"lat":51.69048,"lng":5.29362},"tracks":[1,3],"country":"NL"},
        {"id":{"code":"ZL","uicCode":"8400747"},"stationType":"KNOOPPUNT_INTERCITY_STATION","names":{"long":"Zwolle","medium":"Zwolle","short":"Zwolle"},"location":{"lat":52.50474,"lng":6.091102},"tracks":[1],"country":"NL"},
        {"id":{"code":"BHF","uicCode":"8011160"},"stationType":"MEGA_STATION","names":{"long":"Berlin Hbf","medium":"Berlin Hbf","short":"Berlin Hbf"},"location":{"lat":52.52508,"lng":13.369402},"tracks":[1,2],"country":"D"}
        ]}
        """)])

        let response = try await api().getStations()
        #expect(response.payload.map(\.identifiers.code) == ["UT", "ASD", "HT", "ZL", "BHF"])
        #expect(response.skipped.isEmpty)
        let utrecht = try #require(response.payload.first)
        #expect(utrecht.tracks == nil)
        #expect(utrecht.identifiers.uicCode == nil)
        #expect(utrecht.hasKnownFacilities == true)
        #expect(response.payload[1].names.medium == nil)
        #expect(response.payload[2].names.synonyms == ["Den Bosch"])
        #expect(try await repository().dutchStations().map(\.identifiers.code) == dutchCodes)
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
