//
//  StationCollectionTests.swift
//  InspiRailTests
//

import Foundation
import SwiftData
import Testing
@testable import InspiRail

/// The fixture's Dutch stations, decoded as the API decodes them and sorted
/// by name, as the store keeps them: HT, ASD, UT, ZL.
func dutchFixtureStations() throws -> [Station] {
    try JSONDecoder().decode(StationResponse.self, from: Data(stationFixture.utf8)).payload
        .filter { $0.country == "NL" }
        .sorted { $0.names.long < $1.names.long }
}

/// A logbook kept in memory only, never the app's store, with one saved
/// visit per code. Each has a configuration of its own, so no two tests
/// share visits.
@MainActor
func inMemoryLogbook(visits codes: [String] = []) throws -> ModelContainer {
    let configuration = ModelConfiguration(UUID().uuidString, schema: LogbookStore.schema, isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: LogbookStore.schema, configurations: [configuration])
    for code in codes {
        container.mainContext.insert(VisitedStation(stationCode: code, stationName: code))
    }
    try container.mainContext.save()
    return container
}

/// Which stations count toward the logbook, and the numbers the Logbook and
/// Settings show (#23): every Dutch station but the home station, and every
/// visit but the home station's. Pure: no stub, no store of the app's.
@Suite("The stations that count")
@MainActor
final class StationCollectionTests {
    let dutch: [Station]
    /// Every logbook a test opened, kept until the test ends: a visit can't
    /// be read once its container is gone.
    private var logbooks: [ModelContainer] = []

    init() throws {
        dutch = try dutchFixtureStations()
        try #require(dutch.map(\.identifiers.code) == ["HT", "ASD", "UT", "ZL"])
    }

    /// The visits of a new in-memory logbook with one visit per code.
    func logbookVisits(_ codes: [String]) throws -> [VisitedStation] {
        let logbook = try inMemoryLogbook(visits: codes)
        logbooks.append(logbook)
        return try logbook.mainContext.fetch(FetchDescriptor<VisitedStation>())
    }

    // MARK: - The rule

    @Test("The home station isn't collectable, and a visit to it doesn't count")
    func theHomeStationIsNotCollectable() {
        let collection = StationCollection(homeStationCode: "UT")

        #expect(collection.stations(among: dutch).map(\.identifiers.code) == ["HT", "ASD", "ZL"])
        #expect(collection.total(dutchStationCount: 4) == 3)
        #expect(!collection.counts("UT"))
        #expect(collection.counts("ASD"))
    }

    @Test("With no home station, every Dutch station is collectable")
    func withNoHomeStationEveryDutchStationIsCollectable() {
        let collection = StationCollection(homeStationCode: "")

        #expect(collection.stations(among: dutch).map(\.identifiers.code) == ["HT", "ASD", "UT", "ZL"])
        #expect(collection.total(dutchStationCount: 4) == 4)
        #expect(collection.counts("UT"))
    }

    @Test("Every visit counts but the home station's")
    func aVisitToTheHomeStationDoesntCount() throws {
        let visits = try logbookVisits(["UT", "ASD", "ZL"])

        #expect(Set(StationCollection(homeStationCode: "UT").countedVisits(visits).map(\.stationCode)) == ["ASD", "ZL"])
        #expect(Set(StationCollection(homeStationCode: "").countedVisits(visits).map(\.stationCode)) == ["UT", "ASD", "ZL"])
    }

    @Test("The stations left to visit are the collectable ones with no visit")
    func unvisitedLeavesOutTheHomeStationAndEveryVisitedStation() {
        let collection = StationCollection(homeStationCode: "UT")

        #expect(collection.unvisited(among: dutch, visitedCodes: ["ASD", "UT"]).map(\.identifiers.code) == ["HT", "ZL"])
        #expect(collection.unvisited(among: dutch, visitedCodes: ["HT", "ASD", "ZL"]).isEmpty)
    }

    // MARK: - The Logbook

    @Test("With every station but the home one visited, the Logbook shows N of N and 100 %, with or without the home station's visit")
    func everyStationButTheHomeOneIsOneHundredPercent() throws {
        let collection = StationCollection(homeStationCode: "UT")
        let others = try logbookVisits(["HT", "ASD", "ZL"])
        let all = try logbookVisits(["HT", "ASD", "UT", "ZL"])

        for visits in [others, all] {
            let progress = collection.progress(of: visits, dutchStations: dutch, cachedDutchStationCount: 4)
            #expect(progress == StationCollection.Progress(visited: 3, total: 3))
            #expect(progress.fraction == 1)
            #expect(progress.percentage == 100)
        }
    }

    @Test("The Logbook's total and count follow a home-station change, from the list and, before it loads, from the cached count")
    func theTotalFollowsAHomeStationChangeBeforeAndAfterTheListLoads() throws {
        let visits = try logbookVisits(["HT", "ASD", "ZL"])

        let atUtrecht = StationCollection(homeStationCode: "UT")
        #expect(atUtrecht.progress(of: visits, dutchStations: nil, cachedDutchStationCount: 4) == StationCollection.Progress(visited: 3, total: 3))

        let atAmsterdam = StationCollection(homeStationCode: "ASD")
        for list in [dutch, nil] {
            let progress = atAmsterdam.progress(of: visits, dutchStations: list, cachedDutchStationCount: 4)
            #expect(progress == StationCollection.Progress(visited: 2, total: 3))
            #expect(progress.percentage == 67)
        }
    }

    @Test("Before any list or cached count, the total is unknown")
    func beforeAnyListTheTotalIsUnknown() throws {
        let visits = try logbookVisits(["ASD"])

        let progress = StationCollection(homeStationCode: "UT").progress(of: visits, dutchStations: nil, cachedDutchStationCount: 0)

        #expect(progress == StationCollection.Progress(visited: 1, total: 0))
        #expect(progress.fraction == 0)
    }

    @Test("Once the list has loaded, a home station NS no longer lists leaves every Dutch station to collect")
    func aHomeStationNotInTheListLeavesEveryDutchStation() throws {
        let progress = StationCollection(homeStationCode: "XX").progress(of: [], dutchStations: dutch, cachedDutchStationCount: 4)

        #expect(progress.total == 4)
    }

    @Test("A visit to a station NS no longer lists still counts, and the bar stops at 100 % (#37 decides)")
    func aVisitNoLongerInTheListStillCounts() throws {
        let visits = try logbookVisits(["HT", "ASD", "ZL", "OLD"])

        let progress = StationCollection(homeStationCode: "UT").progress(of: visits, dutchStations: dutch, cachedDutchStationCount: 4)

        #expect(progress == StationCollection.Progress(visited: 4, total: 3))
        #expect(progress.fraction == 1)
        #expect(progress.percentage == 100)
    }

    // MARK: - Settings

    @Test("With only the home station's visit recorded, Settings counts none, as the Logbook does, so Reset Logbook is disabled")
    func onlyTheHomeStationsVisitLeavesNothingToReset() throws {
        let visits = try logbookVisits(["UT"])

        #expect(StationCollection(homeStationCode: "UT").countedVisits(visits).isEmpty)
        #expect(StationCollection(homeStationCode: "UT").progress(of: visits, dutchStations: dutch, cachedDutchStationCount: 4).visited == 0)
        #expect(StationCollection(homeStationCode: "ASD").countedVisits(visits).count == 1)
    }
}
