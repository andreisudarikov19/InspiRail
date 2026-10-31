//
//  StationsRepository.swift
//  InspiRail
//
//  Repository layer for station data with caching
//

import Foundation
import OSLog

/// Repository for managing station data with caching
actor StationsRepository {
    private let backend: BackendAPI
    private let logger = Logger(subsystem: AppConfiguration.subsystem, category: "repository")
    
    // MARK: - Cache Management
    private var cachedStations: [Station]?
    private var cacheTimestamp: Date?
    private let cacheLifetime: TimeInterval
    
    init() {
        self.backend = BackendAPI()
        self.cacheLifetime = AppConfiguration.API.cacheLifetime
    }
    
    // MARK: - Public Methods
    
    /// Fetch stations with caching support
    func stations(forceRefresh: Bool = false) async throws -> StationResponse {
        // Check if cache is valid
        if !forceRefresh,
           let cached = cachedStations,
           let timestamp = cacheTimestamp,
           Date().timeIntervalSince(timestamp) < cacheLifetime {
            logger.debug("Returning cached stations (\(cached.count) items)")
            return StationResponse(payload: cached)
        }
        
        // Fetch fresh data
        logger.debug("Fetching fresh station data from API")
        let response = try await backend.getStations(includeNonPlannable: false)
        
        // Update cache
        cachedStations = response.payload
        cacheTimestamp = Date()
        
        logger.debug("Cached \(response.payload.count) stations")
        return response
    }
}
