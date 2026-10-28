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
            await AnalyticsManager.shared.track(.cacheHit(endpoint: "/nsapp-stations/v3"))
            return StationResponse(payload: cached)
        }
        
        // Fetch fresh data
        logger.debug("Fetching fresh station data from API")
        await AnalyticsManager.shared.track(.cacheMiss(endpoint: "/nsapp-stations/v3"))
        let response = try await backend.getStations(includeNonPlannable: false)
        
        // Update cache
        cachedStations = response.payload
        cacheTimestamp = Date()
        
        logger.debug("Cached \(response.payload.count) stations")
        return response
    }
    
    /// Find a specific station by code
    func station(byCode code: String) async throws -> Station? {
        let response = try await stations()
        return response.payload.first { $0.identifiers.code == code }
    }
    
    /// Search stations by name
    func search(query: String, country: String = "NL") async throws -> [Station] {
        let response = try await stations()
        
        guard !query.isEmpty else {
            return response.payload.filter { $0.country == country }
        }
        
        return response.payload.filter {
            $0.country == country && (
                $0.names.long.localizedCaseInsensitiveContains(query) ||
                $0.names.medium.localizedCaseInsensitiveContains(query) ||
                $0.identifiers.code.localizedCaseInsensitiveContains(query)
            )
        }
    }
    
    /// Clear the cache manually
    func clearCache() {
        logger.debug("Clearing station cache")
        cachedStations = nil
        cacheTimestamp = nil
    }
}
