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
    /// The API the stations come from.
    let backend: BackendAPI
    private let logger = Logger(subsystem: AppConfiguration.subsystem, category: "repository")
    
    // MARK: - Cache Management
    private var stored: (stations: [Station], date: Date)?
    private var download: Task<[Station], Error>?
    /// Moves on each time the API key changes, so that a download that sent
    /// the old key is neither joined nor kept (#19).
    private var keyGeneration = 0
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
        let generation = keyGeneration
        let task = Task { try await fetchDutchStations(keyGeneration: generation) }
        download = task
        return try await task.value
    }
    
    /// How many Dutch stations there are.
    func dutchStationCount() async throws -> Int {
        try await dutchStations().count
    }
    
    /// Drops the stored list, so the next call downloads the stations again.
    ///
    /// - Parameter keyChanged: Whether the API key was saved or removed
    ///   (#19). The download in flight, if any, sent the old key: it still
    ///   answers the callers waiting on it, but later callers don't join it
    ///   and its list isn't kept. The API also forgets a refused key, so the
    ///   next call sends the key stored now, even the one NS refused. Without
    ///   it, a download in flight is still joined, since it is fresh, and a
    ///   refused key stays held back: a Retry or pull to refresh (#21).
    func forgetStations(keyChanged: Bool) async {
        stored = nil
        guard keyChanged else { return }
        // Before the await, so that no caller reaches the old list or
        // download once this has started.
        keyGeneration += 1
        download = nil
        await backend.forgetKeyRefusal()
    }
    
    /// The API key NS last refused, while it is held back (#20). Tests read
    /// it. Screens go by the error a load throws, which already reflects a
    /// refusal of the key stored now (#19).
    var keyRefusal: KeyRefusal? {
        get async { await backend.keyRefusal }
    }
    
    // MARK: - Private Methods
    
    /// Downloads the list, and keeps its Dutch stations if it succeeds and
    /// has any. It clears `download` before it returns, so a caller that
    /// comes after it never waits for a finished download, and starts a new
    /// one after a failure. When the key changed while it ran, it keeps
    /// nothing and leaves `download`, which is then another key's (#19).
    private func fetchDutchStations(keyGeneration generation: Int) async throws -> [Station] {
        defer {
            if generation == keyGeneration {
                download = nil
            }
        }
        
        logger.debug("Fetching fresh station data from API")
        let response = try await backend.getStations(includeNonPlannable: false)
        let stations = response.payload
            .filter { $0.country == "NL" }
            .sorted { $0.names.long < $1.names.long }
        
        // A list with no Dutch station is of no use to any screen: it fails
        // as unreadable data and isn't kept, so the next call tries again
        // (#20)
        guard !stations.isEmpty else {
            logger.error("❌ No Dutch station in the list could be read")
            await backend.report(.unreadableData)
            throw NetworkError.unreadableData
        }
        
        guard generation == keyGeneration else {
            logger.debug("Not keeping a station list downloaded with the API key used before")
            return stations
        }
        stored = (stations, now())
        logger.debug("Cached \(stations.count) stations")
        return stations
    }
}
