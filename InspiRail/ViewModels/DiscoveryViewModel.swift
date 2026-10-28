//
//  DiscoveryViewModel.swift
//  InspiRail
//
//  Created by Andrei Sudarikov on 03/01/2026.
//

import SwiftUI
import Combine
import OSLog

@MainActor
class DiscoveryViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var station: Station?
    @Published var isLoading = true
    @Published var isReady = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private var allStations: [Station] = []
    private var repository: StationsRepository?
    private let logger = Logger(subsystem: AppConfiguration.subsystem, category: "viewmodel")
    
    // Keep track of recently shown stations to avoid repetition
    private var recentlyShown: [String] = []
    private let maxRecentHistory = 10
    
    // MARK: - Public Methods
    
    func loadStations(forceRefresh: Bool = false) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Initialize repository if needed
            if repository == nil {
                repository = StationsRepository()
            }
            
            guard let repository = repository else {
                throw NetworkError.unknown(NSError(domain: "DiscoveryViewModel", code: -1))
            }
            
            let response = try await repository.stations(forceRefresh: forceRefresh)
            
            // Filter only Dutch stations
            self.allStations = response.payload.filter { $0.country == "NL" }
            
            logger.debug("Loaded \(self.allStations.count) Dutch stations")
            
            // Pick a random initial station if we haven't already
            if station == nil {
                randomize()
            }
            
            self.isLoading = false
            self.isReady = true
            
        } catch let error as NetworkError {
            self.errorMessage = error.localizedDescription
            self.isLoading = false
            logger.error("Failed to load stations: \(error.localizedDescription)")
        } catch {
            self.errorMessage = "Could not load stations. Please check your connection."
            self.isLoading = false
            logger.error("Unexpected error: \(error.localizedDescription)")
        }
    }
    
    func randomize(excludeHomeStation homeCode: String? = nil) {
        guard !allStations.isEmpty else { return }
        
        // Filter out recently shown stations and home station for better variety
        var availableStations = allStations.filter { station in
            let isRecent = recentlyShown.contains(station.identifiers.code)
            let isHome = station.identifiers.code == homeCode
            return !isRecent && !isHome
        }
        
        // If we've filtered too much, reset recent history
        if availableStations.isEmpty {
            recentlyShown.removeAll()
            availableStations = allStations.filter { $0.identifiers.code != homeCode }
        }
        
        // Pick a random station
        if let newStation = availableStations.randomElement() {
            station = newStation
            
            // Track this station
            recentlyShown.append(newStation.identifiers.code)
            if recentlyShown.count > maxRecentHistory {
                recentlyShown.removeFirst()
            }
            
            logger.debug("Selected station: \(newStation.names.long)")
        }
    }
    
    func getStation(byCode code: String) -> Station? {
        return allStations.first(where: { $0.identifiers.code == code })
    }
    
    func refresh() async {
        await loadStations(forceRefresh: true)
    }
}

