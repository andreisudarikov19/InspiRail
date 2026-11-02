//
//  StationsRepository.swift
//  InspiRail
//
//  Repository layer for station data with caching
//

import Foundation
import OSLog

/// The station list, downloaded once and kept for an hour.
///
/// The app creates one, with its one `BackendAPI`, and every screen and window
/// reads the stations from it (#18). Callers that ask while a download is
/// running share it. Only a successful download is kept, so after a failure
/// the next call tries again.
actor StationsRepository {
    /// The API the stations come from. Settings' key check uses it too.
    let backend: BackendAPI
    private let logger = Logger(subsystem: AppConfiguration.subsystem, category: "repository")
    
    // MARK: - Cache Management
    private var stored: (stations: [Station], date: Date)?
    private var download: Task<[Station], Error>?
    private let cacheLifetime: TimeInterval
    private let now: @Sendable () -> Date
    
    /// - Parameters:
    ///   - backend: The API the stations come from.
    ///   - now: The clock the stored list's age is measured by. Tests pass
    ///     one they move by hand.
    init(backend: BackendAPI, now: @escaping @Sendable () -> Date = { Date() }) {
        self.backend = backend
        self.cacheLifetime = AppConfiguration.API.cacheLifetime
        self.now = now
    }
    
    // MARK: - Public Methods
    
    /// The Dutch stations, sorted by name.
    func dutchStations() async throws -> [Station] {
        if let stored,
           now().timeIntervalSince(stored.date) < cacheLifetime {
            logger.debug("Returning cached stations (\(stored.stations.count) items)")
            return stored.stations
        }
        
        if let download {
            logger.debug("Waiting for the station download in flight")
            return try await download.value
        }
        
        // Not tied to the caller's task: a screen that goes away doesn't
        // cancel a download that other screens may be waiting for.
        let task = Task { try await fetchDutchStations() }
        download = task
        return try await task.value
    }
    
    /// How many Dutch stations there are.
    func dutchStationCount() async throws -> Int {
        try await dutchStations().count
    }
    
    // MARK: - Private Methods
    
    /// Downloads the list, and keeps its Dutch stations if it succeeds. It
    /// clears `download` before it returns, so a caller that comes after it
    /// never waits for a finished download, and starts a new one after a
    /// failure.
    private func fetchDutchStations() async throws -> [Station] {
        defer { download = nil }
        
        logger.debug("Fetching fresh station data from API")
        let response = try await backend.getStations(includeNonPlannable: false)
        let stations = response.payload
            .filter { $0.country == "NL" }
            .sorted { $0.names.long < $1.names.long }
        
        stored = (stations, now())
        logger.debug("Cached \(stations.count) stations")
        return stations
    }
}
