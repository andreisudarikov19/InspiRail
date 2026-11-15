//
//  DiscoveryViewModel.swift
//  InspiRail
//
//  Created by Andrei Sudarikov on 03/01/2026.
//

import SwiftUI
import SwiftData
import Combine
import OSLog

@MainActor
class DiscoveryViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var station: Station?
    @Published var isLoading = true
    @Published var isReady = false
    /// Why the stations couldn't be loaded, and what Discover offers for
    /// it: Retry or Open Settings (#21).
    @Published var failure: LoadFailure?
    /// How many stations there are to collect, once every one is visited
    /// (#29): Discover then shows "all visited" instead of a station, and
    /// Randomize is disabled. Nil otherwise. A failed reload keeps it, and
    /// Discover shows it above the error.
    @Published private(set) var allVisitedCount: Int?
    
    // MARK: - Private Properties
    private var allStations: [Station] = []
    private let logger = Logger(subsystem: AppConfiguration.subsystem, category: "viewmodel")
    
    // Keep track of recently shown stations to avoid repetition
    private var recentlyShown: [String] = []
    private let maxRecentHistory = 10
    
    /// Where the home station is read from at each pick: the app's
    /// defaults, which Settings and onboarding write. Tests pass a suite
    /// of their own.
    private let defaults: UserDefaults
    /// Chooses the station shown from those a pick may show.
    private let choose: ([Station]) -> Station?
    
    /// - Parameters:
    ///   - defaults: Where the home station is read from at each pick.
    ///   - choose: Chooses from the stations a pick may show; at random
    ///     by default. Tests pass one they can follow.
    init(defaults: UserDefaults = .standard, choose: @escaping ([Station]) -> Station? = { $0.randomElement() }) {
        self.defaults = defaults
        self.choose = choose
    }
    
    /// Whether Randomize is enabled: once the stations have loaded, and
    /// while a station is left to visit.
    var canRandomize: Bool {
        isReady && allVisitedCount == nil
    }
    
    // MARK: - Public Methods
    
    /// Loads the Dutch stations from the app's station store (#18), and
    /// picks a station if none is shown yet, from `logbook`'s visits.
    func loadStations(from repository: StationsRepository, logbook: ModelContext) async {
        isLoading = true
        failure = nil
        
        do {
            // The Dutch stations
            self.allStations = try await repository.dutchStations()
            
            logger.debug("Loaded \(self.allStations.count) Dutch stations")
            
            // Pick a random initial station if we haven't already
            if station == nil {
                pick(logbook: logbook)
            }
            
            self.isLoading = false
            self.isReady = true
            
        } catch {
            // A cancelled load shows no message. Only Discover going away
            // cancels it, so nobody sees it still loading (#20).
            guard let failure = LoadFailure(error) else { return }
            self.failure = failure
            self.isLoading = false
            logger.error("Failed to load stations: \(error.localizedDescription)")
        }
    }
    
    /// Loads the stations again after a failure (#21). The store drops its
    /// list, joins a download already in flight and keeps a refused key
    /// held back, so this never starts a second download or sends a key NS
    /// refused. Discover shows its loading state from the start.
    func retry(from repository: StationsRepository, logbook: ModelContext) async {
        isLoading = true
        failure = nil
        await repository.forgetStations(keyChanged: false)
        await loadStations(from: repository, logbook: logbook)
    }
    
    /// Shows another station, from `logbook`'s visits.
    func randomize(logbook: ModelContext) {
        pick(logbook: logbook)
    }
    
    /// The visits or the home station changed, in any window. While every
    /// station is visited, picks again, so that "all visited" leaves by
    /// itself once a station is free: after Reset Logbook, or a home-station
    /// change that frees one (#29). Picks again, too, when the station on
    /// the card is now the home station, which Discover never suggests
    /// (#23). Any other station on the card stays, even once it is marked
    /// visited, until the next Randomize.
    func visitsOrHomeChanged(logbook: ModelContext) {
        let cardIsHome = station.map { !collection.counts($0.identifiers.code) } ?? false
        guard allVisitedCount != nil || cardIsHome else { return }
        pick(logbook: logbook)
    }
    
    func getStation(byCode code: String) -> Station? {
        return allStations.first(where: { $0.identifiers.code == code })
    }
    
    // MARK: - Private Methods
    
    /// The stations that count, with the home station the defaults hold
    /// now.
    private var collection: StationCollection {
        StationCollection(homeStationCode: defaults.string(forKey: "homeStationCode") ?? "")
    }
    
    /// Every pick: after loading, after Retry and Randomize. It reads the
    /// home station and the visits itself, as they are now, so no caller
    /// can leave them out (#23): a home station changed in Settings and a
    /// visit marked in any window, saved or not, count at once. It picks a
    /// collectable station with no visit (#29), skipping the last few
    /// shown while others are left. With none left, it shows "all visited".
    private func pick(logbook: ModelContext) {
        guard !allStations.isEmpty else { return }
        
        let collection = self.collection
        let pool = collection.unvisited(among: allStations, visitedCodes: visitedCodes(in: logbook))
        
        // Every collectable station is visited: nothing to show (#29)
        guard !pool.isEmpty else {
            station = nil
            allVisitedCount = collection.stations(among: allStations).count
            logger.debug("Every collectable station is visited")
            return
        }
        allVisitedCount = nil
        
        // Filter out recently shown stations for better variety
        var availableStations = pool.filter { !recentlyShown.contains($0.identifiers.code) }
        
        // If we've filtered too much, reset recent history
        if availableStations.isEmpty {
            recentlyShown.removeAll()
            availableStations = pool
        }
        
        // Pick a random station
        if let newStation = choose(availableStations) {
            station = newStation
            
            // Track this station
            recentlyShown.append(newStation.identifiers.code)
            if recentlyShown.count > maxRecentHistory {
                recentlyShown.removeFirst()
            }
            
            logger.debug("Selected station: \(newStation.names.long)")
        }
    }
    
    /// The codes of the stations in `logbook`, its changes not yet saved
    /// included. When they can't be read, none, so Discover still picks.
    private func visitedCodes(in logbook: ModelContext) -> Set<String> {
        do {
            return Set(try logbook.fetch(FetchDescriptor<VisitedStation>()).map(\.stationCode))
        } catch {
            logger.error("Couldn't read the visits: \(String(describing: error))")
            return []
        }
    }
}

