//
//  APIKeyCheckTests.swift
//  InspiRailTests
//

import Foundation
import Security
import SwiftUI
import Testing
@testable import InspiRail

/// What Settings says about the API key, from asking the shared station store
/// (#19). These tests extend the serialized "Station store" suite, since they
/// share its stub, and never reach the network.
extension StationStoreTests {
    /// A store whose API reads the key from a store in memory, holding `key`.
    func keyCheckRepository(key: String = "test-key") -> (StationsRepository, TestKeyStorage) {
        let storage = TestKeyStorage(key: key)
        return (StationsRepository(backend: api(keyProvider: provider(storage))), storage)
    }

    // MARK: - What each status shows

    @Test("Each key status has its text and controls, and each error its status")
    func eachStatusSaysWhatItShows() {
        let shown: [(APIKeyStatus, String?, entry: Bool, removal: Bool, retry: Bool)] = [
            (.working, nil, false, false, false),
            (.noKey, "Not configured", true, false, false),
            (.rejected, "NS didn't accept this key.", true, true, false),
            (.refused, "NS refused your API key. It may be over its usage limit. Try again later.", true, false, false),
            (.keychainUnavailable, "Your NS API key can't be read right now. Try again in a moment.", true, false, false),
            (.cantCheck("Can't reach NS. Check your internet connection."), "Can't reach NS. Check your internet connection.", false, false, true),
        ]
        for (status, message, entry, removal, retry) in shown {
            #expect(status.message == message, "\(status)")
            #expect(status.offersKeyEntry == entry, "\(status)")
            #expect(status.offersRemoval == removal, "\(status)")
            #expect(status.offersRetry == retry, "\(status)")
        }

        let statuses: [(Error, APIKeyStatus?)] = [
            (NetworkError.noKey, .noKey),
            (NetworkError.keyRejected, .rejected),
            (NetworkError.forbidden, .refused),
            (NetworkError.keychainUnavailable, .keychainUnavailable),
            (NetworkError.offline(.notConnectedToInternet), .cantCheck("Can't reach NS. Check your internet connection.")),
            (NetworkError.tooManyRequests, .cantCheck("NS is getting too many requests. Try again in a minute.")),
            (NetworkError.serviceUnavailable(status: 503), .cantCheck("NS isn't available right now. Try again later.")),
            (NetworkError.unreadableData, .cantCheck("NS sent data this version of InspiRail can't read. Try again later.")),
            (CocoaError(.fileNoSuchFile), .cantCheck("Couldn't load stations. Try again later.")),
            (CancellationError(), nil),
            (URLError(.cancelled), nil),
        ]
        for (error, status) in statuses {
            #expect(APIKeyStatus(for: error) == status, "\(error)")
        }
    }

    @Test("Settings offers Retry exactly where every other screen does, and the key field where they lead to key entry (#21)")
    func keyStatusOffersWhatTheRecoveryActionSays() {
        let errors: [any Error] = [
            NetworkError.noKey, NetworkError.keychainUnavailable, NetworkError.keyRejected, NetworkError.forbidden,
            NetworkError.tooManyRequests, NetworkError.serviceUnavailable(status: 503), NetworkError.offline(.notConnectedToInternet),
            NetworkError.offline(.timedOut), NetworkError.unreadableData, NetworkError.invalidURL,
            CocoaError(.fileNoSuchFile), CancellationError(), URLError(.cancelled),
        ]
        for error in errors {
            let action = NetworkError.recoveryAction(for: error)
            let status = APIKeyStatus(for: error)
            #expect((status == nil) == (action == nil), "\(error)")
            if let status {
                #expect(status.offersRetry == (action == .retry), "\(error)")
                #expect(status.offersKeyEntry == (action == .keyEntry), "\(error)")
            }
        }
    }

    // MARK: - Checking the key

    @Test("No connection, a 429, a 5xx or unreadable data doesn't say the key is rejected, or offer to remove it", arguments: [
        (StubURLProtocol.Reply.failure(.notConnectedToInternet), "Can't reach NS. Check your internet connection."),
        (.status(429), "NS is getting too many requests. Try again in a minute."),
        (.status(503), "NS isn't available right now. Try again later."),
        (.body("{}"), "NS sent data this version of InspiRail can't read. Try again later."),
    ])
    func problemsAKeyCantFixDontOfferRemoval(reply: StubURLProtocol.Reply, message: String) async throws {
        StubURLProtocol.reset(replies: [reply])
        let (repository, _) = keyCheckRepository()
        let keyCheck = APIKeyCheck()

        await keyCheck.refresh(using: repository)

        let status = try #require(keyCheck.status)
        #expect(status == .cantCheck(message))
        #expect(status != .rejected)
        #expect(!status.offersRemoval)
        #expect(!status.offersKeyEntry)
    }

    @Test("An answer that takes longer than two seconds is still an answer")
    func slowAnswerIsAnAnswer() async throws {
        let (repository, _) = keyCheckRepository()
        let keyCheck = APIKeyCheck()
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        let check = Task { await keyCheck.refresh(using: repository) }
        await StubURLProtocol.waitForRequests(1)
        // Longer than the 2 s after which the old check called the key broken.
        try await Task.sleep(for: .milliseconds(2100))
        StubURLProtocol.release()
        await check.value

        #expect(keyCheck.status == .working)
    }

    @Test("A 401 says NS rejected the key, and offers to remove it; a 403 says NS refused it, and offers only another key", arguments: [401, 403])
    func onlyARejectedKeyOffersRemoval(status: Int) async throws {
        StubURLProtocol.reset(replies: [.status(status)])
        let (repository, _) = keyCheckRepository()
        let keyCheck = APIKeyCheck()

        await keyCheck.refresh(using: repository)

        let shown = try #require(keyCheck.status)
        #expect(shown == (status == 401 ? .rejected : .refused))
        // A key over its quota is still a valid key.
        #expect(shown.offersRemoval == (status == 401))
        #expect(shown.offersKeyEntry)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("With no key, or a Keychain that can't be read, nothing is sent and the key can't be removed")
    func missingOrUnreadableKeySendsNothing() async throws {
        let noKey = APIKeyCheck()
        await noKey.refresh(using: StationsRepository(backend: api(keyProvider: provider(TestKeyStorage()))))
        #expect(noKey.status == .noKey)

        let unreadable = APIKeyCheck()
        let storage = TestKeyStorage(failure: .retrievalFailed(errSecInteractionNotAllowed))
        await unreadable.refresh(using: StationsRepository(backend: api(keyProvider: provider(storage))))
        let status = try #require(unreadable.status)
        #expect(status == .keychainUnavailable)
        #expect(status.offersKeyEntry)
        #expect(!status.offersRemoval)

        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test("When the key can't be checked, Settings offers Retry, which checks again through the store (#21)")
    func cantCheckOffersRetryAndRetryChecksAgain() async throws {
        StubURLProtocol.reset(replies: [.failure(.notConnectedToInternet), .stations])
        let (repository, _) = keyCheckRepository()
        let keyCheck = APIKeyCheck()
        await keyCheck.refresh(using: repository)
        let status = try #require(keyCheck.status)
        #expect(status.offersRetry)
        #expect(!status.offersKeyEntry)

        await keyCheck.retry(using: repository)

        #expect(keyCheck.status == .working)
        #expect(StubURLProtocol.requests.count == 2)
    }

    @Test("A second check within the hour sends nothing")
    func secondCheckWithinTheHourSendsNothing() async {
        let (repository, _) = keyCheckRepository()
        let keyCheck = APIKeyCheck()

        await keyCheck.refresh(using: repository)
        #expect(keyCheck.status == .working)
        await keyCheck.refresh(using: repository)
        #expect(keyCheck.status == .working)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("A check cut short, for example by leaving Settings, leaves the status as it was, and reports nothing")
    func cancelledCheckLeavesTheStatusUnchanged() async throws {
        StubURLProtocol.reset(replies: [.failure(.notConnectedToInternet)])
        let (repository, _) = keyCheckRepository()
        let keyCheck = APIKeyCheck()
        let offline = APIKeyStatus.cantCheck("Can't reach NS. Check your internet connection.")
        await keyCheck.refresh(using: repository)
        #expect(keyCheck.status == offline)

        StubURLProtocol.reset(replies: [.stations])
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }
        let check = Task { await keyCheck.refresh(using: repository) }
        await StubURLProtocol.waitForRequests(1)
        check.cancel()
        StubURLProtocol.release()
        await check.value

        #expect(keyCheck.status == offline)
        #expect(failures.values == [.offline(.notConnectedToInternet)])
        // The download the cancelled check waited on stored the list.
        await keyCheck.refresh(using: repository)
        #expect(keyCheck.status == .working)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("Settings and the store agree that a list with no readable Dutch station is unreadable")
    func settingsAndTheStoreAgreeOnAListWithNoReadableDutchStation() async throws {
        // Utrecht has no location and Amsterdam's is in text. Berlin is whole.
        StubURLProtocol.reset(replies: [.body("""
        {"payload":[
        {"id":{"code":"UT"},"stationType":"MEGA_STATION","names":{"long":"Utrecht Centraal","short":"Utrecht C"},"country":"NL"},
        {"id":{"code":"ASD"},"stationType":"MEGA_STATION","names":{"long":"Amsterdam Centraal","short":"Amsterdm C"},"location":{"lat":"52.37888","lng":"4.900277"},"country":"NL"},
        {"id":{"code":"BHF"},"stationType":"MEGA_STATION","names":{"long":"Berlin Hbf","short":"Berlin Hbf"},"location":{"lat":52.52508,"lng":13.369402},"country":"D"}
        ]}
        """)])
        let (repository, _) = keyCheckRepository()
        let keyCheck = APIKeyCheck()

        await keyCheck.refresh(using: repository)

        #expect(keyCheck.status == .cantCheck("NS sent data this version of InspiRail can't read. Try again later."))
        await #expect(throws: NetworkError.unreadableData) { try await repository.dutchStations() }
    }

    // MARK: - A saved or removed key

    @Test("Forgetting the stations downloads them again")
    func forgettingTheStationsDownloadsThemAgain() async throws {
        let (repository, _) = keyCheckRepository()

        #expect(try await repository.dutchStations().map(\.identifiers.code) == dutchCodes)
        await repository.forgetStations(keyChanged: false)
        #expect(try await repository.dutchStations().map(\.identifiers.code) == dutchCodes)
        #expect(StubURLProtocol.requests.count == 2)
    }

    @Test("Forgetting the stations, the key unchanged, still joins the download in flight")
    func forgettingTheStationsJoinsTheDownloadInFlight() async throws {
        let (repository, _) = keyCheckRepository()
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        async let first = repository.dutchStations()
        await StubURLProtocol.waitForRequests(1)
        await repository.forgetStations(keyChanged: false)
        async let second = repository.dutchStations()
        try await Task.sleep(for: .milliseconds(300))
        #expect(StubURLProtocol.requests.count == 1)
        StubURLProtocol.release()

        #expect(try await first.map(\.identifiers.code) == dutchCodes)
        #expect(try await second.map(\.identifiers.code) == dutchCodes)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("Forgetting the stations, the key unchanged, still holds back a key NS rejected")
    func forgettingTheStationsKeepsARefusal() async throws {
        StubURLProtocol.reset(replies: [.status(401), .stations])
        let (repository, _) = keyCheckRepository()

        await #expect(throws: NetworkError.keyRejected) { try await repository.dutchStations() }
        // A Retry (#21) doesn't send the rejected key again.
        await repository.forgetStations(keyChanged: false)
        await #expect(throws: NetworkError.keyRejected) { try await repository.dutchStations() }
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("After a key change, a download with the old key is neither joined nor kept")
    func keyChangeLetsGoOfTheOldDownload() async throws {
        StubURLProtocol.reset(replies: [.stations, .status(404)])
        let (repository, storage) = keyCheckRepository(key: "old-test-key")
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        let oldLoad = Task { try await repository.dutchStations() }
        await StubURLProtocol.waitForRequests(1)
        await storage.setKey("new-test-key")
        StubURLProtocol.stopHolding()
        await repository.forgetStations(keyChanged: true)
        await #expect(throws: NetworkError.unreadableData) { try await repository.dutchStations() }
        StubURLProtocol.release()

        // The old load's caller still gets its list, but the list isn't kept.
        #expect(try await oldLoad.value.map(\.identifiers.code) == dutchCodes)
        await #expect(throws: NetworkError.unreadableData) { try await repository.dutchStations() }
        #expect(sentKeys == ["old-test-key", "new-test-key", "new-test-key"])
    }

    @Test("An old key's download that ends late leaves the new key's download in flight for later callers to join")
    func oldDownloadEndingLeavesTheNewKeysDownload() async throws {
        // The old key's list, then a 503 for the new key, whose wait before
        // the next attempt lasts until the gate opens, then the list.
        StubURLProtocol.reset(replies: [.stations, .status(503), .stations])
        let storage = TestKeyStorage(key: "old-test-key")
        let (gate, openGate) = AsyncStream<Void>.makeStream()
        defer { openGate.finish() }
        let sleeps = sleeps
        let repository = StationsRepository(backend: api(keyProvider: provider(storage), sleep: { wait in
            sleeps.append(wait)
            for await _ in gate {}
        }))
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        let oldLoad = Task { try await repository.dutchStations() }
        await StubURLProtocol.waitForRequests(1)
        await storage.setKey("new-test-key")
        StubURLProtocol.stopHolding()
        await repository.forgetStations(keyChanged: true)
        let newLoad = Task { try await repository.dutchStations() }
        for _ in 0..<500 where sleeps.values.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(StubURLProtocol.requests.count == 2)

        // The old download ends while the new one waits to try again: a
        // third load joins the new one.
        StubURLProtocol.release()
        #expect(try await oldLoad.value.map(\.identifiers.code) == dutchCodes)
        let thirdLoad = Task { try await repository.dutchStations() }
        try await Task.sleep(for: .milliseconds(300))
        #expect(StubURLProtocol.requests.count == 2)
        openGate.finish()

        #expect(try await newLoad.value.map(\.identifiers.code) == dutchCodes)
        #expect(try await thirdLoad.value.map(\.identifiers.code) == dutchCodes)
        #expect(StubURLProtocol.requests.count == 3)
        #expect(sentKeys == ["old-test-key", "new-test-key", "new-test-key"])
    }

    @Test("A saved key is checked with a request that sends it, though a list is stored")
    func savedKeyIsCheckedWithIt() async {
        StubURLProtocol.reset(replies: [.stations, .status(401)])
        let (repository, storage) = keyCheckRepository()
        let keyCheck = APIKeyCheck()
        await keyCheck.refresh(using: repository)
        #expect(keyCheck.status == .working)

        await storage.setKey("new-test-key")
        await keyCheck.keyChanged(in: repository)

        #expect(keyCheck.status == .rejected)
        #expect(sentKeys == ["test-key", "new-test-key"])
    }

    @Test("A saved key is checked with it while the old key's download runs, and the old answer never shows")
    func savedKeyIsCheckedWithItWhileAnOldDownloadRuns() async throws {
        StubURLProtocol.reset(replies: [.stations, .status(401)])
        let (repository, storage) = keyCheckRepository()
        let keyCheck = APIKeyCheck()
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        // The visit's check waits for the old key's answer while a new key is saved.
        let visitCheck = Task { await keyCheck.refresh(using: repository) }
        await StubURLProtocol.waitForRequests(1)
        await storage.setKey("new-test-key")
        StubURLProtocol.stopHolding()
        await keyCheck.keyChanged(in: repository)
        #expect(keyCheck.status == .rejected)
        StubURLProtocol.release()
        await visitCheck.value
        #expect(keyCheck.status == .rejected)

        await keyCheck.refresh(using: repository)
        #expect(keyCheck.status == .rejected)
        #expect(sentKeys == ["test-key", "new-test-key"])
    }

    @Test("A late refusal of the old key doesn't show for the key saved since")
    func lateRefusalOfAnOldKeyDoesntShow() async throws {
        StubURLProtocol.reset(replies: [.status(401), .stations])
        let (repository, storage) = keyCheckRepository()
        let keyCheck = APIKeyCheck()
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        let visitCheck = Task { await keyCheck.refresh(using: repository) }
        await StubURLProtocol.waitForRequests(1)
        await storage.setKey("new-test-key")
        StubURLProtocol.stopHolding()
        await keyCheck.keyChanged(in: repository)
        #expect(keyCheck.status == .working)
        StubURLProtocol.release()
        await visitCheck.value

        #expect(keyCheck.status == .working)
        // The API remembers the old key's refusal, which Settings doesn't read.
        #expect(await repository.keyRefusal != nil)
        await keyCheck.refresh(using: repository)
        #expect(keyCheck.status == .working)
        #expect(sentKeys == ["test-key", "new-test-key"])
    }

    @Test("A check cut short after a key is saved doesn't void the saved key's check")
    func cancelledCheckAfterAKeyChangeLeavesTheSavedKeysCheck() async throws {
        StubURLProtocol.reset(replies: [.status(401), .stations])
        let (repository, storage) = keyCheckRepository(key: "old-test-key")
        let keyCheck = APIKeyCheck()
        await keyCheck.refresh(using: repository)
        #expect(keyCheck.status == .rejected)
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        // Settings saves a key, is left, opened again and left again while
        // the saved key's check waits for its answer.
        await storage.setKey("new-test-key")
        let save = Task { await keyCheck.keyChanged(in: repository) }
        await StubURLProtocol.waitForRequests(2)
        let visit = Task { await keyCheck.refresh(using: repository) }
        try await Task.sleep(for: .milliseconds(200))
        visit.cancel()
        StubURLProtocol.release()
        await save.value
        await visit.value

        #expect(keyCheck.status == .working)
        #expect(sentKeys == ["old-test-key", "new-test-key"])
    }

    @Test("While a saved key is checked, no window offers to remove a key, and a 401 for it offers removal again")
    func noRemovalWhileASavedKeyIsChecked() async throws {
        StubURLProtocol.reset(replies: [.status(401)])
        let (repository, storage) = keyCheckRepository(key: "old-test-key")
        let keyCheck = APIKeyCheck()
        await keyCheck.refresh(using: repository)
        #expect(keyCheck.status == .rejected)
        #expect(keyCheck.offersRemoval)
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        await storage.setKey("new-test-key")
        let save = Task { await keyCheck.keyChanged(in: repository) }
        await StubURLProtocol.waitForRequests(2)
        // The status is still the old key's, but the key stored now is the
        // new one, so another window must not offer to remove it.
        #expect(keyCheck.status == .rejected)
        #expect(!keyCheck.offersRemoval)
        StubURLProtocol.release()
        await save.value

        #expect(keyCheck.status == .rejected)
        #expect(keyCheck.offersRemoval)
        #expect(sentKeys == ["old-test-key", "new-test-key"])
    }

    @Test("A saved key's check that ends after another key is saved doesn't offer removal while the newer key is checked")
    func noRemovalUntilTheNewestSavedKeyIsChecked() async throws {
        // The old key's 401; the first saved key's list, held; a 503 for the
        // second saved key, whose wait before the next attempt lasts until
        // the gate opens; then a 401 for it.
        StubURLProtocol.reset(replies: [.status(401), .stations, .status(503), .status(401)])
        let storage = TestKeyStorage(key: "old-test-key")
        let (gate, openGate) = AsyncStream<Void>.makeStream()
        defer { openGate.finish() }
        let sleeps = sleeps
        let repository = StationsRepository(backend: api(keyProvider: provider(storage), sleep: { wait in
            sleeps.append(wait)
            for await _ in gate {}
        }))
        let keyCheck = APIKeyCheck()
        await keyCheck.refresh(using: repository)
        #expect(keyCheck.offersRemoval)
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        await storage.setKey("first-test-key")
        let firstSave = Task { await keyCheck.keyChanged(in: repository) }
        await StubURLProtocol.waitForRequests(2)
        await storage.setKey("second-test-key")
        StubURLProtocol.stopHolding()
        let secondSave = Task { await keyCheck.keyChanged(in: repository) }
        for _ in 0..<500 where sleeps.values.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        // The first saved key's check ends while the second's waits.
        StubURLProtocol.release()
        await firstSave.value
        #expect(keyCheck.status == .rejected)
        #expect(!keyCheck.offersRemoval)
        openGate.finish()
        await secondSave.value

        #expect(keyCheck.status == .rejected)
        #expect(keyCheck.offersRemoval)
        #expect(sentKeys == ["old-test-key", "first-test-key", "second-test-key", "second-test-key"])
    }

    @Test("A removed key reads as not configured, not as the stored list's success")
    func removedKeyIsNotConfigured() async {
        let (repository, storage) = keyCheckRepository()
        let keyCheck = APIKeyCheck()
        await keyCheck.refresh(using: repository)
        #expect(keyCheck.status == .working)

        await storage.removeKey()
        await keyCheck.keyChanged(in: repository)

        #expect(keyCheck.status == .noKey)
        #expect(StubURLProtocol.requests.count == 1)
    }

    // MARK: - The app's one key check

    @Test("Reading the environment without the App's key check builds none")
    func environmentHasNoKeyCheckByDefault() {
        #expect(EnvironmentValues().apiKeyCheck == nil)
    }

    @Test("While hosting the unit tests, which have no key check by design, a missing key check isn't reported")
    func missingKeyCheckIsNotReportedInTheTestHost() {
        // Outside the test host this stops a Debug build, and so would stop
        // this test run.
        reportMissingKeyCheck(in: "A test")
    }
}
