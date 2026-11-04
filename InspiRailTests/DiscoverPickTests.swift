//
//  DiscoverPickTests.swift
//  InspiRailTests
//

import Foundation
import SwiftData
import Testing
@testable import InspiRail

/// Discover's pick (#23, #29): never the home station, never a station in the
/// logbook, on every pick. These tests extend the serialized "Station store"
/// suite, since they share its stub, and never reach the network. Each view
/// model reads a scratch defaults suite, never the app's, and an in-memory
/// logbook, and records the pool each pick chose from.
extension StationStoreTests {
    /// Records each pool a pick chose from, as codes, and chooses its first
    /// station, so a test knows every pick.
    func pickRecorder() -> (choose: ([Station]) -> Station?, pools: Recorder<[String]>) {
        let pools = Recorder<[String]>()
        return ({ pool in
            pools.append(pool.map(\.identifiers.code))
            return pool.first
        }, pools)
    }

    /// A Discover view model that reads `defaults`, with `home` stored as
    /// the home station, and chooses through `pickRecorder()`; and an
    /// in-memory logbook with one visit per code. The caller removes the
    /// suite.
    func discover(home: String, visits: [String], in defaults: UserDefaults) throws -> (viewModel: DiscoveryViewModel, logbook: ModelContainer, pools: Recorder<[String]>) {
        defaults.set(home, forKey: "homeStationCode")
        let (choose, pools) = pickRecorder()
        return (DiscoveryViewModel(defaults: defaults, choose: choose), try inMemoryLogbook(visits: visits), pools)
    }

    // MARK: - The pick

    @Test("The first pick after loading is neither the home station nor a visited station")
    func theFirstPickSkipsTheHomeStationAndVisitedStations() async throws {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, pools) = try discover(home: "UT", visits: ["ASD"], in: defaults)

        await viewModel.loadStations(from: repository(), logbook: logbook.mainContext)

        #expect(pools.values == [["HT", "ZL"]])
        #expect(viewModel.station?.identifiers.code == "HT")
    }

    @Test("The pick after Retry is neither the home station nor a visited station")
    func thePickAfterRetrySkipsThemToo() async throws {
        StubURLProtocol.reset(replies: [.status(503), .status(503), .status(503), .stations])
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, pools) = try discover(home: "UT", visits: ["ASD"], in: defaults)
        let repository = repository()
        await viewModel.loadStations(from: repository, logbook: logbook.mainContext)
        #expect(viewModel.failure?.action == .retry)
        #expect(pools.values.isEmpty)

        await viewModel.retry(from: repository, logbook: logbook.mainContext)

        #expect(pools.values == [["HT", "ZL"]])
        #expect(viewModel.station?.identifiers.code == "HT")
    }

    @Test("Randomize picks neither the home station nor a visited station")
    func randomizeSkipsThem() async throws {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, pools) = try discover(home: "UT", visits: ["ASD"], in: defaults)
        await viewModel.loadStations(from: repository(), logbook: logbook.mainContext)

        viewModel.randomize(logbook: logbook.mainContext)

        // HT was just shown
        #expect(pools.values == [["HT", "ZL"], ["ZL"]])
        #expect(viewModel.station?.identifiers.code == "ZL")
    }

    @Test("A home station changed between picks, as in Settings, counts at the next pick")
    func aHomeStationChangedBetweenPicksCountsAtTheNextPick() async throws {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, pools) = try discover(home: "UT", visits: [], in: defaults)
        await viewModel.loadStations(from: repository(), logbook: logbook.mainContext)

        defaults.set("ZL", forKey: "homeStationCode")
        viewModel.randomize(logbook: logbook.mainContext)

        #expect(pools.values == [["HT", "ASD", "ZL"], ["ASD", "UT"]])
    }

    @Test("A visit marked between picks, not yet saved, counts at the next pick, and so does one deleted, as Reset Logbook does")
    func aVisitBetweenPicksCountsAtTheNextPick() async throws {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, pools) = try discover(home: "UT", visits: [], in: defaults)
        let context = logbook.mainContext
        await viewModel.loadStations(from: repository(), logbook: context)

        // What the card's toggle does: insert, with no save
        context.insert(VisitedStation(stationCode: "ASD", stationName: "Amsterdam Centraal"))
        viewModel.randomize(logbook: context)
        #expect(pools.values == [["HT", "ASD", "ZL"], ["ZL"]])

        // What Reset Logbook does: delete every visit, then save
        for visit in try context.fetch(FetchDescriptor<VisitedStation>()) {
            context.delete(visit)
        }
        try context.save()
        viewModel.randomize(logbook: context)

        // HT and ZL were just shown
        #expect(pools.values == [["HT", "ASD", "ZL"], ["ZL"], ["ASD"]])
    }

    @Test("Recently shown stations are skipped among the rest, and come back only once they are all that is left")
    func recentlyShownStationsComeBackOnlyWhenTheyAreAllThatIsLeft() async throws {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, pools) = try discover(home: "UT", visits: ["ASD"], in: defaults)
        var shown: [String?] = []
        await viewModel.loadStations(from: repository(), logbook: logbook.mainContext)
        shown.append(viewModel.station?.identifiers.code)

        for _ in 0..<2 {
            viewModel.randomize(logbook: logbook.mainContext)
            shown.append(viewModel.station?.identifiers.code)
        }

        #expect(pools.values == [["HT", "ZL"], ["ZL"], ["HT", "ZL"]])
        #expect(shown == ["HT", "ZL", "HT"])
    }

    // MARK: - All visited

    @Test("With every collectable station visited, loading shows \"all visited\" with the count, no station, and Randomize disabled")
    func withEveryStationVisitedLoadingShowsAllVisited() async throws {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, pools) = try discover(home: "UT", visits: ["HT", "ASD", "UT", "ZL"], in: defaults)

        await viewModel.loadStations(from: repository(), logbook: logbook.mainContext)

        #expect(viewModel.station == nil)
        #expect(viewModel.allVisitedCount == 3)
        #expect(!viewModel.canRandomize)
        #expect(viewModel.isReady)
        #expect(!viewModel.isLoading)
        #expect(viewModel.failure == nil)
        #expect(pools.values.isEmpty)
    }

    @Test("A reload that fails once the stored list has expired keeps \"all visited\", which Discover shows above the error")
    func aFailedReloadKeepsAllVisited() async throws {
        StubURLProtocol.reset(replies: [.stations, .failure(.notConnectedToInternet)])
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, pools) = try discover(home: "UT", visits: ["HT", "ASD", "ZL"], in: defaults)
        let clock = TestClock()
        let repository = StationsRepository(backend: api(), now: { clock.now })
        await viewModel.loadStations(from: repository, logbook: logbook.mainContext)
        #expect(viewModel.allVisitedCount == 3)

        // An hour later Discover appears again, offline
        clock.advance(by: AppConfiguration.API.cacheLifetime)
        await viewModel.loadStations(from: repository, logbook: logbook.mainContext)

        #expect(StubURLProtocol.requests.count == 2)
        #expect(viewModel.failure == LoadFailure(message: "Can't reach NS. Check your internet connection.", action: .retry))
        #expect(viewModel.allVisitedCount == 3)
        #expect(viewModel.station == nil)
        #expect(viewModel.isReady)
        #expect(!viewModel.canRandomize)
        #expect(pools.values.isEmpty)
    }

    @Test("Marking the last station keeps its card until the next Randomize, which shows \"all visited\"")
    func markingTheLastStationKeepsTheCardUntilTheNextRandomize() async throws {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, pools) = try discover(home: "UT", visits: ["ASD", "ZL"], in: defaults)
        let context = logbook.mainContext
        await viewModel.loadStations(from: repository(), logbook: context)
        #expect(viewModel.station?.identifiers.code == "HT")
        #expect(viewModel.canRandomize)

        // The card's toggle, then what Discover does when the visits change
        context.insert(VisitedStation(stationCode: "HT", stationName: "'s-Hertogenbosch"))
        viewModel.visitsOrHomeChanged(logbook: context)

        #expect(viewModel.station?.identifiers.code == "HT")
        #expect(viewModel.allVisitedCount == nil)
        #expect(viewModel.canRandomize)

        viewModel.randomize(logbook: context)

        #expect(viewModel.station == nil)
        #expect(viewModel.allVisitedCount == 3)
        #expect(!viewModel.canRandomize)
        #expect(pools.values == [["HT"]])
    }

    @Test("Reset Logbook leaves \"all visited\" with a pick")
    func resetLogbookLeavesAllVisited() async throws {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, pools) = try discover(home: "UT", visits: ["HT", "ASD", "ZL"], in: defaults)
        let context = logbook.mainContext
        await viewModel.loadStations(from: repository(), logbook: context)
        #expect(viewModel.allVisitedCount == 3)

        for visit in try context.fetch(FetchDescriptor<VisitedStation>()) {
            context.delete(visit)
        }
        try context.save()
        viewModel.visitsOrHomeChanged(logbook: context)

        #expect(pools.values == [["HT", "ASD", "ZL"]])
        #expect(viewModel.station?.identifiers.code == "HT")
        #expect(viewModel.allVisitedCount == nil)
        #expect(viewModel.canRandomize)
    }

    @Test("A home-station change that frees a station leaves \"all visited\" with that station")
    func aHomeStationThatFreesAStationLeavesAllVisited() async throws {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, pools) = try discover(home: "UT", visits: ["HT", "ASD", "ZL"], in: defaults)
        await viewModel.loadStations(from: repository(), logbook: logbook.mainContext)
        #expect(viewModel.allVisitedCount == 3)

        defaults.set("ZL", forKey: "homeStationCode")
        viewModel.visitsOrHomeChanged(logbook: logbook.mainContext)

        #expect(pools.values == [["UT"]])
        #expect(viewModel.station?.identifiers.code == "UT")
        #expect(viewModel.allVisitedCount == nil)
        #expect(viewModel.canRandomize)
    }

    // MARK: - The card and the home station

    @Test("A card whose station becomes the home station, as in Settings, is replaced by another pick")
    func aCardThatBecomesTheHomeStationIsPickedAgain() async throws {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, pools) = try discover(home: "UT", visits: [], in: defaults)
        await viewModel.loadStations(from: repository(), logbook: logbook.mainContext)
        #expect(viewModel.station?.identifiers.code == "HT")

        defaults.set("HT", forKey: "homeStationCode")
        viewModel.visitsOrHomeChanged(logbook: logbook.mainContext)

        #expect(pools.values == [["HT", "ASD", "ZL"], ["ASD", "UT", "ZL"]])
        #expect(viewModel.station?.identifiers.code == "ASD")
        #expect(viewModel.allVisitedCount == nil)
        #expect(viewModel.canRandomize)
    }

    @Test("A card whose station becomes the home station shows \"all visited\" when no other station is left")
    func aCardThatBecomesTheHomeStationWithNoneLeftShowsAllVisited() async throws {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, pools) = try discover(home: "UT", visits: ["ASD", "UT", "ZL"], in: defaults)
        await viewModel.loadStations(from: repository(), logbook: logbook.mainContext)
        #expect(viewModel.station?.identifiers.code == "HT")

        defaults.set("HT", forKey: "homeStationCode")
        viewModel.visitsOrHomeChanged(logbook: logbook.mainContext)

        #expect(pools.values == [["HT"]])
        #expect(viewModel.station == nil)
        #expect(viewModel.allVisitedCount == 3)
        #expect(!viewModel.canRandomize)
    }

    @Test("A home station changed to a station not on the card leaves the card")
    func aHomeStationChangedToAnotherStationLeavesTheCard() async throws {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let (viewModel, logbook, pools) = try discover(home: "UT", visits: [], in: defaults)
        await viewModel.loadStations(from: repository(), logbook: logbook.mainContext)
        #expect(viewModel.station?.identifiers.code == "HT")

        defaults.set("ZL", forKey: "homeStationCode")
        viewModel.visitsOrHomeChanged(logbook: logbook.mainContext)

        #expect(pools.values == [["HT", "ASD", "ZL"]])
        #expect(viewModel.station?.identifiers.code == "HT")
        #expect(viewModel.allVisitedCount == nil)
        #expect(viewModel.canRandomize)
    }
}
