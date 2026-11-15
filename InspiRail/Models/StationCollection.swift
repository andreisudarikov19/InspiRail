//
//  StationCollection.swift
//  InspiRail
//
//  Which stations count toward the logbook, and which visits
//

import Foundation

/// The stations the logbook collects: every Dutch station but the home
/// station. A visit to the home station doesn't count (#23).
///
/// This is the one place that says so. Discover picks from the collectable
/// stations with no visit (#29), the Logbook's total is their count and its
/// visited count the visits that count, and Settings' Reset Logbook counts
/// those visits too.
struct StationCollection: Equatable {
    /// The home station's code. Empty when none is set, and then every
    /// Dutch station is collectable.
    let homeStationCode: String
    
    init(homeStationCode: String) {
        self.homeStationCode = homeStationCode
    }
    
    /// Whether a visit to the station with this code counts: any station
    /// but the home station.
    func counts(_ stationCode: String) -> Bool {
        stationCode != homeStationCode
    }
    
    /// The collectable stations among the Dutch stations, in their order.
    func stations(among dutchStations: [Station]) -> [Station] {
        dutchStations.filter { counts($0.identifiers.code) }
    }
    
    /// The collectable stations with no visit: what Discover picks from
    /// (#29).
    func unvisited(among dutchStations: [Station], visitedCodes: Set<String>) -> [Station] {
        stations(among: dutchStations).filter { !visitedCodes.contains($0.identifiers.code) }
    }
    
    /// The visits that count, in their order: every one but the home
    /// station's. A visit to a station NS no longer lists still counts.
    func countedVisits(_ visits: [VisitedStation]) -> [VisitedStation] {
        visits.filter { counts($0.stationCode) }
    }
    
    /// How many stations there are to collect, when only the number of
    /// Dutch stations is at hand: one fewer with a home station, which is
    /// chosen from those stations. Exact whenever NS still lists the home
    /// station; `stations(among:)` is exact always.
    func total(dutchStationCount: Int) -> Int {
        guard !homeStationCode.isEmpty else { return dutchStationCount }
        return max(0, dutchStationCount - 1)
    }
    
    /// The Logbook's header: the visits that count, of how many stations.
    struct Progress: Equatable {
        let visited: Int
        /// 0 while not known.
        let total: Int
        
        /// The share visited, from 0 to 1; 0 while the total isn't known.
        var fraction: Double {
            guard total > 0 else { return 0 }
            return min(1, Double(visited) / Double(total))
        }
        
        /// The share visited as a whole percentage, rounded.
        var percentage: Int {
            Int((fraction * 100).rounded())
        }
    }
    
    /// The Logbook's header for these visits. The total comes from the
    /// Dutch stations once the list is at hand, and before that from the
    /// count cached at the last load, so the header renders at once.
    func progress(of visits: [VisitedStation], dutchStations: [Station]?, cachedDutchStationCount: Int) -> Progress {
        let total = dutchStations.map { stations(among: $0).count }
            ?? total(dutchStationCount: cachedDutchStationCount)
        return Progress(visited: countedVisits(visits).count, total: total)
    }
}
