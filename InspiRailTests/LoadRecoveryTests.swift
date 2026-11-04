//
//  LoadRecoveryTests.swift
//  InspiRailTests
//

import Foundation
import SwiftData
import Testing
@testable import InspiRail

/// What a screen offers when the stations couldn't be loaded, and its Retry
/// (#21). These tests extend the serialized "Station store" suite, since they
/// share its stub, and never reach the network.
extension StationStoreTests {
    // MARK: - Discover

    @Test("Discover offers Retry when NS is unavailable, and key entry when it rejected the key", arguments: [
        (503, RecoveryAction.retry),
        (401, .keyEntry),
    ])
    func discoverOffersRetryOrKeyEntry(status: Int, action: RecoveryAction) async throws {
        StubURLProtocol.reset(replies: [.status(status)])
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, _) = try discover(home: "", visits: [], in: defaults)

        await viewModel.loadStations(from: repository(), logbook: logbook.mainContext)

        let failure = try #require(viewModel.failure)
        #expect(failure.action == action)
        let error: NetworkError = status == 401 ? .keyRejected : .serviceUnavailable(status: 503)
        #expect(failure.message == NetworkError.message(for: error))
        #expect(!viewModel.isLoading)
        #expect(!viewModel.isReady)
        #expect(viewModel.station == nil)
    }

    @Test("Discover's Retry shows the loading state, sends one new request, and shows a station")
    func discoverRetryShowsTheLoadingStateThenTheStation() async throws {
        StubURLProtocol.reset(replies: [.status(503), .status(503), .status(503), .stations])
        let repository = repository()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, _) = try discover(home: "", visits: [], in: defaults)
        await viewModel.loadStations(from: repository, logbook: logbook.mainContext)
        #expect(viewModel.failure?.action == .retry)
        #expect(StubURLProtocol.requests.count == 3)
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        let retry = Task { await viewModel.retry(from: repository, logbook: logbook.mainContext) }
        await StubURLProtocol.waitForRequests(4)
        #expect(viewModel.isLoading)
        #expect(viewModel.failure == nil)
        StubURLProtocol.release()
        await retry.value

        #expect(viewModel.failure == nil)
        #expect(viewModel.isReady)
        #expect(!viewModel.isLoading)
        #expect(dutchCodes.contains(try #require(viewModel.station).identifiers.code))
        #expect(StubURLProtocol.requests.count == 4)
        #expect(failures.values == [.serviceUnavailable(status: 503)])
    }

    @Test("Discover's Retry shows the loading state from its start, before it asks the store, and while its download is held")
    func discoverRetryShowsTheLoadingStateFromItsStart() async throws {
        StubURLProtocol.reset(replies: [.failure(.notConnectedToInternet), .stations])
        let repository = repository()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, _) = try discover(home: "", visits: [], in: defaults)
        await viewModel.loadStations(from: repository, logbook: logbook.mainContext)
        #expect(viewModel.failure?.action == .retry)
        #expect(!viewModel.isLoading)
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        let retry = Task { await viewModel.retry(from: repository, logbook: logbook.mainContext) }
        // The yield lets the retry run up to its first await, on the store.
        // It resumes on the main actor only after these checks.
        await Task.yield()
        #expect(viewModel.isLoading)
        #expect(viewModel.failure == nil)
        await StubURLProtocol.waitForRequests(2)
        #expect(viewModel.isLoading)
        #expect(viewModel.failure == nil)
        StubURLProtocol.release()
        await retry.value

        #expect(!viewModel.isLoading)
        #expect(viewModel.failure == nil)
        #expect(viewModel.station != nil)
        #expect(StubURLProtocol.requests.count == 2)
    }

    @Test("Discover's Retry joins a download already in flight, such as another window's")
    func discoverRetryJoinsTheDownloadInFlight() async throws {
        StubURLProtocol.reset(replies: [.failure(.notConnectedToInternet), .stations])
        let repository = repository()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, _) = try discover(home: "", visits: [], in: defaults)
        await viewModel.loadStations(from: repository, logbook: logbook.mainContext)
        #expect(viewModel.failure?.action == .retry)
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        let otherWindow = Task { try await repository.dutchStations() }
        await StubURLProtocol.waitForRequests(2)
        let retry = Task { await viewModel.retry(from: repository, logbook: logbook.mainContext) }
        try await Task.sleep(for: .milliseconds(300))
        #expect(StubURLProtocol.requests.count == 2)
        StubURLProtocol.release()
        await retry.value

        #expect(try await otherWindow.value.map(\.identifiers.code) == dutchCodes)
        #expect(viewModel.station != nil)
        #expect(viewModel.failure == nil)
        #expect(StubURLProtocol.requests.count == 2)
    }

    @Test("Discover's Retry after a rejected key doesn't send the key again, and still leads to key entry")
    func discoverRetryAfterARejectedKeySendsNothing() async throws {
        StubURLProtocol.reset(replies: [.status(401), .stations])
        let repository = repository()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, _) = try discover(home: "", visits: [], in: defaults)
        await viewModel.loadStations(from: repository, logbook: logbook.mainContext)

        await viewModel.retry(from: repository, logbook: logbook.mainContext)

        #expect(viewModel.failure == LoadFailure(message: "NS didn't accept your API key. Check it in Settings.", action: .keyEntry))
        #expect(StubURLProtocol.requests.count == 1)
        // Each load is reported once, the held-back one too.
        #expect(failures.values == [.keyRejected, .keyRejected])
    }

    @Test("A failed Retry on Discover shows its own error, reported once")
    func discoverFailedRetryShowsTheNewError() async throws {
        StubURLProtocol.reset(replies: [.failure(.notConnectedToInternet), .status(503)])
        let repository = repository()
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, _) = try discover(home: "", visits: [], in: defaults)
        await viewModel.loadStations(from: repository, logbook: logbook.mainContext)
        #expect(viewModel.failure == LoadFailure(message: "Can't reach NS. Check your internet connection.", action: .retry))

        await viewModel.retry(from: repository, logbook: logbook.mainContext)

        #expect(viewModel.failure == LoadFailure(message: "NS isn't available right now. Try again later.", action: .retry))
        #expect(!viewModel.isLoading)
        #expect(StubURLProtocol.requests.count == 4)
        #expect(failures.values == [.offline(.notConnectedToInternet), .serviceUnavailable(status: 503)])
    }

    // MARK: - The Home Station picker

    @Test("The Home Station picker shows the error and Retry when the stations can't be loaded, not an empty list")
    func pickerShowsTheErrorAndRetryOnAFailure() async {
        StubURLProtocol.reset(replies: [.status(503)])
        let stationList = StationList()
        #expect(stationList.isLoading)

        await stationList.load(from: repository())

        #expect(!stationList.isLoading)
        #expect(stationList.stations.isEmpty)
        #expect(stationList.failure == LoadFailure(message: "NS isn't available right now. Try again later.", action: .retry))
    }

    @Test("Right after Remove Key, the Home Station picker shows the key message and the way to the key")
    func pickerShowsTheKeyMessageRightAfterTheKeyIsRemoved() async {
        let (repository, storage) = keyCheckRepository()
        let keyCheck = APIKeyCheck()
        await keyCheck.refresh(using: repository)
        #expect(keyCheck.status == .working)
        // What Remove Key does: the store drops its list.
        await storage.removeKey()
        await keyCheck.keyChanged(in: repository)

        let stationList = StationList()
        await stationList.load(from: repository)

        #expect(stationList.failure == LoadFailure(message: "No NS API key is set. Add one in Settings.", action: .keyEntry))
        #expect(stationList.stations.isEmpty)
        #expect(StubURLProtocol.requests.count == 1)
    }

    @Test("After a saved key is rejected, the Home Station picker shows the key message and the way to the key")
    func pickerShowsTheKeyMessageAfterASavedKeyIsRejected() async {
        StubURLProtocol.reset(replies: [.stations, .status(401)])
        let (repository, storage) = keyCheckRepository()
        let keyCheck = APIKeyCheck()
        await keyCheck.refresh(using: repository)
        await storage.setKey("new-test-key")
        await keyCheck.keyChanged(in: repository)
        #expect(keyCheck.status == .rejected)

        let stationList = StationList()
        await stationList.load(from: repository)

        #expect(stationList.failure == LoadFailure(message: "NS didn't accept your API key. Check it in Settings.", action: .keyEntry))
        #expect(stationList.stations.isEmpty)
        #expect(StubURLProtocol.requests.count == 2)
    }

    @Test("The Home Station picker's Retry shows the loading state, then the stations")
    func pickerShowsTheStationsAfterASuccessfulRetry() async {
        StubURLProtocol.reset(replies: [.failure(.notConnectedToInternet), .stations])
        let repository = repository()
        let stationList = StationList()
        await stationList.load(from: repository)
        #expect(stationList.failure?.action == .retry)
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        let retry = Task { await stationList.retry(from: repository) }
        await StubURLProtocol.waitForRequests(2)
        #expect(stationList.isLoading)
        #expect(stationList.failure == nil)
        StubURLProtocol.release()
        await retry.value

        #expect(stationList.stations.map(\.identifiers.code) == dutchCodes)
        #expect(stationList.failure == nil)
        #expect(!stationList.isLoading)
        #expect(StubURLProtocol.requests.count == 2)
    }

    @Test("The Home Station picker's Retry joins a download already in flight, such as another window's")
    func pickerRetryJoinsTheDownloadInFlight() async throws {
        StubURLProtocol.reset(replies: [.failure(.notConnectedToInternet), .stations])
        let repository = repository()
        let stationList = StationList()
        await stationList.load(from: repository)
        #expect(stationList.failure?.action == .retry)
        StubURLProtocol.hold()
        defer { StubURLProtocol.release() }

        let otherWindow = Task { try await repository.dutchStations() }
        await StubURLProtocol.waitForRequests(2)
        let retry = Task { await stationList.retry(from: repository) }
        try await Task.sleep(for: .milliseconds(300))
        #expect(StubURLProtocol.requests.count == 2)
        StubURLProtocol.release()
        await retry.value

        #expect(try await otherWindow.value.map(\.identifiers.code) == dutchCodes)
        #expect(stationList.stations.map(\.identifiers.code) == dutchCodes)
        #expect(stationList.failure == nil)
        #expect(StubURLProtocol.requests.count == 2)
    }
}
