//
//  OnboardingTests.swift
//  InspiRailTests
//

import Foundation
import Security
import Testing
@testable import InspiRail

/// Why a station load fails with an error only a key can fix (#21's mapping).
enum KeyEntryCause: Sendable {
    case noKey, unreadable, rejected, refused
}

/// Onboarding's two steps, its key step, and its choice of home station
/// (#22, #42). These tests extend the serialized "Station store" suite, since
/// they share its stub, and never reach the network. Each onboarding writes
/// to a defaults suite of its own, never the app's, and keys live in memory.
extension StationStoreTests {
    /// A defaults suite of its own, and its name, so a test can remove it.
    func scratchDefaults() -> (defaults: UserDefaults, suite: String) {
        let suite = "test.\(UUID().uuidString).onboarding"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    // MARK: - Which step shows

    @Test("A first load shows the station step, loading, then the list with its search field")
    func firstLoadShowsTheStationStepThenTheList() async {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let onboarding = Onboarding(defaults: defaults)
        #expect(onboarding.step == .station)
        #expect(onboarding.stationList.isLoading)
        #expect(!onboarding.offersSearch)
        #expect(onboarding.keyProblem == nil)

        await onboarding.load(from: repository(), following: APIKeyCheck())

        #expect(onboarding.step == .station)
        #expect(onboarding.offersSearch)
        #expect(onboarding.stationList.stations.map(\.identifiers.code) == dutchCodes)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("Each error only a key can fix shows the key step, with what Settings' key section says above the field; with no key, the title says it", arguments: [
        (KeyEntryCause.noKey, nil as String?, 0),
        (.unreadable, "Your NS API key can't be read right now. Try again in a moment.", 0),
        (.rejected, "NS didn't accept this key.", 1),
        (.refused, "NS refused your API key. It may be over its usage limit. Try again later.", 1),
    ])
    func keyErrorsShowTheKeyStep(_ cause: KeyEntryCause, message: String?, requests: Int) async {
        let storage: TestKeyStorage
        switch cause {
        case .noKey:
            storage = TestKeyStorage()
        case .unreadable:
            storage = TestKeyStorage(failure: .retrievalFailed(errSecInteractionNotAllowed))
        case .rejected:
            StubURLProtocol.reset(replies: [.status(401)])
            storage = TestKeyStorage(key: "test-key")
        case .refused:
            StubURLProtocol.reset(replies: [.status(403)])
            storage = TestKeyStorage(key: "test-key")
        }
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let onboarding = Onboarding(defaults: defaults)

        await onboarding.load(from: StationsRepository(backend: api(keyProvider: provider(storage))), following: APIKeyCheck())

        #expect(onboarding.step == .key)
        #expect(onboarding.keyProblem == message)
        #expect(onboarding.stationList.failure?.action == .keyEntry)
        #expect(!onboarding.offersSearch)
        #expect(StubURLProtocol.requests.count == requests)
    }

    @Test("Each error another try can fix shows the station step, with its message and Retry, and no search field", arguments: [
        (StubURLProtocol.Reply.failure(.notConnectedToInternet), "Can't reach NS. Check your internet connection."),
        (.status(429), "NS is getting too many requests. Try again in a minute."),
        (.status(503), "NS isn't available right now. Try again later."),
        (.body("{}"), "NS sent data this version of InspiRail can't read. Try again later."),
    ])
    func retryErrorsShowTheStationStepWithRetry(reply: StubURLProtocol.Reply, message: String) async {
        StubURLProtocol.reset(replies: [reply])
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let onboarding = Onboarding(defaults: defaults)

        await onboarding.load(from: repository(), following: APIKeyCheck())

        #expect(onboarding.step == .station)
        #expect(onboarding.stationList.failure == LoadFailure(message: message, action: .retry))
        #expect(onboarding.keyProblem == nil)
        #expect(!onboarding.offersSearch)
    }

    @Test("An answer that is a cancellation leaves onboarding as it was, on either step or loading")
    func aCancellationChangesNothing() async {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let keyStep = Onboarding(defaults: defaults)
        await keyStep.load(from: StationsRepository(backend: api(keyProvider: provider(TestKeyStorage()))), following: APIKeyCheck())
        StubURLProtocol.reset(replies: [.failure(.notConnectedToInternet)])
        let stationStep = Onboarding(defaults: defaults)
        await stationStep.load(from: repository(), following: APIKeyCheck())
        let loading = Onboarding(defaults: defaults)

        let cancellations: [any Error] = [CancellationError(), URLError(.cancelled)]
        for cancellation in cancellations {
            keyStep.stationList.show(.failure(cancellation))
            stationStep.stationList.show(.failure(cancellation))
            loading.stationList.show(.failure(cancellation))
        }

        #expect(keyStep.step == .key)
        #expect(keyStep.stationList.failure == LoadFailure(message: "No NS API key is set. Add one in Settings.", action: .keyEntry))
        #expect(keyStep.keyProblem == nil)
        #expect(stationStep.step == .station)
        #expect(stationStep.stationList.failure == LoadFailure(message: "Can't reach NS. Check your internet connection.", action: .retry))
        #expect(loading.step == .station)
        #expect(loading.stationList.isLoading)
        #expect(loading.stationList.failure == nil)
    }

    // MARK: - Saving a key

    @Test("Saving a key shows the key step's loading state, then the stations, loaded with one request that sends the new key")
    func savingAKeyLoadsTheStationsWithIt() async throws {
        let storage = TestKeyStorage()
        let repository = StationsRepository(backend: api(keyProvider: provider(storage)))
        let keyCheck = APIKeyCheck()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let onboarding = Onboarding(defaults: defaults)
        await onboarding.load(from: repository, following: keyCheck)
        #expect(onboarding.step == .key)
        #expect(!onboarding.canSaveKey)
        onboarding.keyInput = "  new-test-key \n"
        #expect(onboarding.canSaveKey)
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        let save = Task { await onboarding.saveKey(to: storage, checkingWith: keyCheck, in: repository) }
        await StubURLProtocol.waitForRequests(1)
        #expect(onboarding.isSavingKey)
        #expect(onboarding.step == .key)
        #expect(onboarding.keyProblem == nil)
        // The field clears once the key is written, and can't save again
        // while it is checked.
        #expect(onboarding.keyInput == "")
        onboarding.keyInput = "another-test-key"
        #expect(!onboarding.canSaveKey)
        onboarding.keyInput = ""
        // Through the app's one key check, which every window shares.
        #expect(keyCheck.isCheckingNewKey)
        StubURLProtocol.release()
        await save.value

        #expect(onboarding.step == .station)
        #expect(onboarding.offersSearch)
        #expect(onboarding.stationList.stations.map(\.identifiers.code) == dutchCodes)
        #expect(!onboarding.isSavingKey)
        #expect(keyCheck.status == .working)
        #expect(await storage.storedKey == "new-test-key")
        #expect(sentKeys == ["new-test-key"])
    }

    @Test("A saved key NS rejects keeps the key step, with the rejection above the field, hidden while the next key is checked")
    func savingAKeyNSRejectsStaysOnTheKeyStep() async throws {
        StubURLProtocol.reset(replies: [.status(401), .stations])
        let storage = TestKeyStorage()
        let repository = StationsRepository(backend: api(keyProvider: provider(storage)))
        let keyCheck = APIKeyCheck()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let onboarding = Onboarding(defaults: defaults)
        await onboarding.load(from: repository, following: keyCheck)

        onboarding.keyInput = "first-test-key"
        await onboarding.saveKey(to: storage, checkingWith: keyCheck, in: repository)

        #expect(onboarding.step == .key)
        #expect(onboarding.keyProblem == "NS didn't accept this key.")
        #expect(onboarding.keyInput == "")
        #expect(keyCheck.status == .rejected)
        #expect(StubURLProtocol.requests.count == 1)

        onboarding.keyInput = "second-test-key"
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }
        let save = Task { await onboarding.saveKey(to: storage, checkingWith: keyCheck, in: repository) }
        await StubURLProtocol.waitForRequests(2)
        #expect(onboarding.step == .key)
        #expect(onboarding.keyProblem == nil)
        StubURLProtocol.release()
        await save.value

        #expect(onboarding.step == .station)
        #expect(onboarding.stationList.stations.map(\.identifiers.code) == dutchCodes)
        #expect(sentKeys == ["first-test-key", "second-test-key"])
    }

    @Test("A key saved while NS can't be reached shows the station step with Retry, after one request, and Retry loads the list")
    func savingAKeyWhileOfflineShowsTheStationStepWithRetry() async throws {
        StubURLProtocol.reset(replies: [.failure(.notConnectedToInternet), .stations])
        let storage = TestKeyStorage()
        let repository = StationsRepository(backend: api(keyProvider: provider(storage)))
        let keyCheck = APIKeyCheck()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let onboarding = Onboarding(defaults: defaults)
        await onboarding.load(from: repository, following: keyCheck)

        onboarding.keyInput = "new-test-key"
        await onboarding.saveKey(to: storage, checkingWith: keyCheck, in: repository)

        #expect(onboarding.step == .station)
        #expect(onboarding.stationList.failure == LoadFailure(message: "Can't reach NS. Check your internet connection.", action: .retry))
        #expect(!onboarding.offersSearch)
        #expect(StubURLProtocol.requests.count == 1)
        #expect(await storage.storedKey == "new-test-key")
        #expect(keyCheck.status == .cantCheck("Can't reach NS. Check your internet connection."))

        await onboarding.retry(from: repository, following: keyCheck)

        #expect(onboarding.offersSearch)
        #expect(onboarding.stationList.stations.map(\.identifiers.code) == dutchCodes)
        #expect(sentKeys == ["new-test-key", "new-test-key"])
    }

    @Test("A 401 for a saved key that couldn't be checked brings the key step back")
    func aRejectionAfterAnUncheckedSaveBringsTheKeyStepBack() async {
        StubURLProtocol.reset(replies: [.failure(.notConnectedToInternet), .status(401)])
        let storage = TestKeyStorage()
        let repository = StationsRepository(backend: api(keyProvider: provider(storage)))
        let keyCheck = APIKeyCheck()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let onboarding = Onboarding(defaults: defaults)
        await onboarding.load(from: repository, following: keyCheck)
        onboarding.keyInput = "new-test-key"
        await onboarding.saveKey(to: storage, checkingWith: keyCheck, in: repository)
        #expect(onboarding.step == .station)

        await onboarding.retry(from: repository, following: keyCheck)

        #expect(onboarding.step == .key)
        #expect(onboarding.keyProblem == "NS didn't accept this key.")
        #expect(StubURLProtocol.requests.count == 2)
    }

    @Test("A download still running with the old key, in another window, never counts as an answer about the saved key: that window loads again and shows the list, with no request")
    func savingAKeyDoesntCountAnOldKeysDownload() async throws {
        StubURLProtocol.reset(replies: [.status(401), .status(401), .stations])
        let storage = TestKeyStorage(key: "old-test-key")
        let repository = StationsRepository(backend: api(keyProvider: provider(storage)))
        let keyCheck = APIKeyCheck()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let windowA = Onboarding(defaults: defaults)
        let windowB = Onboarding(defaults: defaults)
        await windowA.load(from: repository, following: keyCheck)
        #expect(windowA.step == .key)

        // Once the refusal's pause is over, a window opened then sends the
        // old key again, and its answer is held.
        clock.advance(by: AppConfiguration.API.refusedKeyPause)
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }
        let windowBLoad = Task { await windowB.load(from: repository, following: keyCheck) }
        await StubURLProtocol.waitForRequests(2)
        StubURLProtocol.stopHolding()
        windowA.keyInput = "new-test-key"
        await windowA.saveKey(to: storage, checkingWith: keyCheck, in: repository)
        #expect(windowA.step == .station)
        #expect(windowA.stationList.stations.map(\.identifiers.code) == dutchCodes)
        // The key change reaches window B while it loads, as the screen
        // passes it on: B leaves it to that load.
        await windowB.keySavedOrRemoved(in: repository, following: keyCheck)
        #expect(windowB.stationList.isLoading)
        StubURLProtocol.release()
        await windowBLoad.value

        // The old key's rejection counts for no window and not for the key
        // check: B's load, which started before the key changed, loads again
        // and gets the list the store kept for the new key.
        #expect(windowB.step == .station)
        #expect(windowB.stationList.stations.map(\.identifiers.code) == dutchCodes)
        #expect(windowA.step == .station)
        #expect(keyCheck.status == .working)
        #expect(sentKeys == ["old-test-key", "old-test-key", "new-test-key"])
    }

    @Test("Two windows saving different keys at once both show the later key's answer, never the earlier key's", arguments: [
        ([StubURLProtocol.Reply.status(401), .stations], Onboarding.Step.station, nil as String?, APIKeyStatus.working),
        ([.stations, .status(401)], .key, "NS didn't accept this key.", .rejected),
    ])
    func twoKeysSavedAtOnceShowTheLaterKeysAnswer(replies: [StubURLProtocol.Reply], step: Onboarding.Step, problem: String?, status: APIKeyStatus) async {
        StubURLProtocol.reset(replies: replies)
        let storage = TestKeyStorage()
        let repository = StationsRepository(backend: api(keyProvider: provider(storage)))
        let keyCheck = APIKeyCheck()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let windowA = Onboarding(defaults: defaults)
        let windowB = Onboarding(defaults: defaults)
        await windowA.load(from: repository, following: keyCheck)
        await windowB.load(from: repository, following: keyCheck)
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        windowA.keyInput = "first-test-key"
        let saveA = Task { await windowA.saveKey(to: storage, checkingWith: keyCheck, in: repository) }
        await StubURLProtocol.waitForRequests(1)
        windowB.keyInput = "second-test-key"
        let saveB = Task { await windowB.saveKey(to: storage, checkingWith: keyCheck, in: repository) }
        await StubURLProtocol.waitForRequests(2)
        StubURLProtocol.release()
        await saveA.value
        await saveB.value

        // Window A's check answered for the first key, which the second
        // replaced: A loads again, and gets the second key's answer from
        // the store, with no request.
        for window in [windowA, windowB] {
            #expect(window.step == step)
            #expect(window.keyProblem == problem)
            #expect(window.stationList.stations.map(\.identifiers.code) == (step == .station ? dutchCodes : []))
        }
        #expect(keyCheck.status == status)
        #expect(await storage.storedKey == "second-test-key")
        #expect(sentKeys == ["first-test-key", "second-test-key"])
    }

    @Test("A window saving a key shows its own check's answer, and doesn't load again for its own key change")
    func aWindowSavingAKeyDoesntLoadTwice() async throws {
        StubURLProtocol.reset(replies: [.failure(.notConnectedToInternet), .stations])
        let storage = TestKeyStorage()
        let repository = StationsRepository(backend: api(keyProvider: provider(storage)))
        let keyCheck = APIKeyCheck()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let onboarding = Onboarding(defaults: defaults)
        await onboarding.load(from: repository, following: keyCheck)
        onboarding.keyInput = "new-test-key"
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        let save = Task { await onboarding.saveKey(to: storage, checkingWith: keyCheck, in: repository) }
        await StubURLProtocol.waitForRequests(1)
        // Its own key change reaches it while it saves: it stays on the key
        // step, saving.
        let follow = Task { await onboarding.keySavedOrRemoved(in: repository, following: keyCheck) }
        try await Task.sleep(for: .milliseconds(300))
        #expect(onboarding.step == .key)
        #expect(!onboarding.stationList.isLoading)
        StubURLProtocol.release()
        await save.value
        await follow.value
        // And once more after the save has shown its answer, as a screen
        // that passes the change on late would.
        await onboarding.keySavedOrRemoved(in: repository, following: keyCheck)

        #expect(onboarding.step == .station)
        #expect(onboarding.stationList.failure == LoadFailure(message: "Can't reach NS. Check your internet connection.", action: .retry))
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("A second save while one runs, such as a tap on Save Key right after the return key, writes, checks and sends nothing more")
    func aSecondSaveWhileOneRunsDoesNothing() async throws {
        let storage = TestKeyStorage()
        let repository = StationsRepository(backend: api(keyProvider: provider(storage)))
        let keyCheck = APIKeyCheck()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let onboarding = Onboarding(defaults: defaults)
        await onboarding.load(from: repository, following: keyCheck)
        onboarding.keyInput = "new-test-key"
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        let first = Task { await onboarding.saveKey(to: storage, checkingWith: keyCheck, in: repository) }
        let second = Task { await onboarding.saveKey(to: storage, checkingWith: keyCheck, in: repository) }
        await StubURLProtocol.waitForRequests(1)
        try await Task.sleep(for: .milliseconds(300))
        #expect(await storage.saves == 1)
        #expect(keyCheck.keyChanges == 1)
        #expect(StubURLProtocol.requests.count == 1)
        StubURLProtocol.release()
        await first.value
        await second.value

        #expect(onboarding.step == .station)
        #expect(onboarding.stationList.stations.map(\.identifiers.code) == dutchCodes)
        #expect(await storage.saves == 1)
        #expect(keyCheck.keyChanges == 1)
        #expect(sentKeys == ["new-test-key"])
    }

    @Test("A key that can't be written to the Keychain shows the Keychain's error, and leaves the key step as it was")
    func aKeyThatCantBeWrittenShowsItsError() async {
        let storage = TestKeyStorage(saveFailure: .saveFailed(errSecInteractionNotAllowed))
        let repository = StationsRepository(backend: api(keyProvider: provider(storage)))
        let keyCheck = APIKeyCheck()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let onboarding = Onboarding(defaults: defaults)
        await onboarding.load(from: repository, following: keyCheck)

        onboarding.keyInput = "new-test-key"
        await onboarding.saveKey(to: storage, checkingWith: keyCheck, in: repository)

        #expect(onboarding.keySaveError == "Failed to save to Keychain (status: -25308)")
        #expect(onboarding.keyInput == "new-test-key")
        #expect(onboarding.step == .key)
        #expect(onboarding.keyProblem == nil)
        #expect(!onboarding.isSavingKey)
        #expect(StubURLProtocol.requests.isEmpty)
        #expect(keyCheck.status == nil)
    }

    // MARK: - Other windows (iPad)

    @Test("A key that works, saved in another window's onboarding, moves this one on to the list with no request")
    func aKeyThatWorksInAnotherWindowMovesThisOneOn() async {
        let storage = TestKeyStorage()
        let repository = StationsRepository(backend: api(keyProvider: provider(storage)))
        let keyCheck = APIKeyCheck()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let windowA = Onboarding(defaults: defaults)
        let windowB = Onboarding(defaults: defaults)
        await windowA.load(from: repository, following: keyCheck)
        await windowB.load(from: repository, following: keyCheck)
        windowA.keyInput = "new-test-key"
        await windowA.saveKey(to: storage, checkingWith: keyCheck, in: repository)
        #expect(windowA.step == .station)
        #expect(windowB.step == .key)

        await windowB.keySavedOrRemoved(in: repository, following: keyCheck)

        #expect(windowB.step == .station)
        #expect(windowB.stationList.stations.map(\.identifiers.code) == dutchCodes)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("A key NS rejected, saved in another window's onboarding, shows the rejection here too, with no request")
    func aKeyRejectedInAnotherWindowShowsTheRejectionHere() async {
        StubURLProtocol.reset(replies: [.status(401)])
        let storage = TestKeyStorage()
        let repository = StationsRepository(backend: api(keyProvider: provider(storage)))
        let keyCheck = APIKeyCheck()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let windowA = Onboarding(defaults: defaults)
        let windowB = Onboarding(defaults: defaults)
        await windowA.load(from: repository, following: keyCheck)
        await windowB.load(from: repository, following: keyCheck)
        windowA.keyInput = "new-test-key"
        await windowA.saveKey(to: storage, checkingWith: keyCheck, in: repository)
        #expect(keyCheck.status == .rejected)

        await windowB.keySavedOrRemoved(in: repository, following: keyCheck)

        #expect(windowB.step == .key)
        #expect(windowB.keyProblem == "NS didn't accept this key.")
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("A key saved in another window while NS can't be reached moves this window to the station step with Retry, and Retry loads the list")
    func aKeyUncheckedInAnotherWindowShowsRetryHere() async throws {
        StubURLProtocol.reset(replies: [.failure(.notConnectedToInternet), .stations])
        let storage = TestKeyStorage()
        let repository = StationsRepository(backend: api(keyProvider: provider(storage)))
        let keyCheck = APIKeyCheck()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let windowA = Onboarding(defaults: defaults)
        let windowB = Onboarding(defaults: defaults)
        await windowA.load(from: repository, following: keyCheck)
        await windowB.load(from: repository, following: keyCheck)
        #expect(StubURLProtocol.requests.isEmpty)
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        windowA.keyInput = "new-test-key"
        let save = Task { await windowA.saveKey(to: storage, checkingWith: keyCheck, in: repository) }
        await StubURLProtocol.waitForRequests(1)
        // The key change reaches window B, idle on its key step: it loads
        // again, and joins window A's check.
        let follow = Task { await windowB.keySavedOrRemoved(in: repository, following: keyCheck) }
        try await Task.sleep(for: .milliseconds(300))
        StubURLProtocol.release()
        await save.value
        await follow.value

        let offline = LoadFailure(message: "Can't reach NS. Check your internet connection.", action: .retry)
        #expect(windowA.stationList.failure == offline)
        #expect(windowB.step == .station)
        #expect(windowB.stationList.failure == offline)
        #expect(StubURLProtocol.requests.count == 1)

        // A's Retry loads the list, with no key change, so B keeps its own
        // Retry, which loads the list too.
        await windowA.retry(from: repository, following: keyCheck)
        #expect(windowA.stationList.stations.map(\.identifiers.code) == dutchCodes)
        #expect(windowB.stationList.failure == offline)
        #expect(StubURLProtocol.requests.count == 2)
        await windowB.retry(from: repository, following: keyCheck)
        #expect(windowB.stationList.stations.map(\.identifiers.code) == dutchCodes)
        #expect(sentKeys == ["new-test-key", "new-test-key", "new-test-key"])
    }

    // MARK: - Choosing the home station (#22)

    /// The loaded station with that code.
    func station(_ code: String, in onboarding: Onboarding) throws -> Station {
        try #require(onboarding.stationList.stations.first { $0.identifiers.code == code })
    }

    @Test("Tapping a station selects it and writes nothing; tapping another moves the selection")
    func tappingAStationSelectsItAndWritesNothing() async throws {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let onboarding = Onboarding(defaults: defaults)
        await onboarding.load(from: repository(), following: APIKeyCheck())
        let writesNothing = {
            #expect(defaults.object(forKey: "homeStationCode") == nil)
            #expect(defaults.object(forKey: "homeStationName") == nil)
            #expect(defaults.object(forKey: "hasCompletedOnboarding") == nil)
            #expect(!Onboarding.isDone(homeStationCode: defaults.string(forKey: "homeStationCode") ?? ""))
        }
        #expect(!onboarding.canStartExploring)
        onboarding.startExploring()
        writesNothing()

        onboarding.select(try station("ASD", in: onboarding))
        #expect(onboarding.selection?.identifiers.code == "ASD")
        #expect(onboarding.canStartExploring)
        writesNothing()

        onboarding.select(try station("UT", in: onboarding))
        #expect(onboarding.selection?.identifiers.code == "UT")
        #expect(onboarding.canStartExploring)
        writesNothing()
    }

    @Test("Start Exploring stores the selected station as the home station, which ends onboarding, and no other flag")
    func startExploringStoresTheHomeStation() async throws {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let onboarding = Onboarding(defaults: defaults)
        await onboarding.load(from: repository(), following: APIKeyCheck())
        onboarding.select(try station("UT", in: onboarding))

        onboarding.startExploring()

        #expect(defaults.string(forKey: "homeStationCode") == "UT")
        #expect(defaults.string(forKey: "homeStationName") == "Utrecht Centraal")
        #expect(Onboarding.isDone(homeStationCode: defaults.string(forKey: "homeStationCode") ?? ""))
        #expect(defaults.object(forKey: "hasCompletedOnboarding") == nil)
    }

    @Test("A home station ends onboarding, so a user who already has one and no other flag sees the tabs")
    func aHomeStationEndsOnboarding() {
        #expect(!Onboarding.isDone(homeStationCode: ""))
        #expect(Onboarding.isDone(homeStationCode: "ASD"))
    }
}
