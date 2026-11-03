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

        await onboarding.load(from: repository())

        #expect(onboarding.step == .station)
        #expect(onboarding.offersSearch)
        #expect(onboarding.stationList.stations.map(\.identifiers.code) == dutchCodes)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("Each error only a key can fix shows the key step, with its message above the field; with no key, the title says it", arguments: [
        (KeyEntryCause.noKey, nil as String?, 0),
        (.unreadable, "Your NS API key can't be read right now. Try again in a moment.", 0),
        (.rejected, "NS didn't accept your API key. Check it in Settings.", 1),
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

        await onboarding.load(from: StationsRepository(backend: api(keyProvider: provider(storage))))

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

        await onboarding.load(from: repository())

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
        await keyStep.load(from: StationsRepository(backend: api(keyProvider: provider(TestKeyStorage()))))
        StubURLProtocol.reset(replies: [.failure(.notConnectedToInternet)])
        let stationStep = Onboarding(defaults: defaults)
        await stationStep.load(from: repository())
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
}
