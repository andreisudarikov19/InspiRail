//
//  DiscoveryViewModel.swift
//  rnsapp
//
//  Created by Andrei Sudarikov on 16/01/2026.
//

import Foundation
import SwiftUI
import Combine

@MainActor
class DiscoveryViewModel: ObservableObject {
    
    @Published var station: Station?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // Private cache to hold the heavy data
    private var allStations: [Station] = []
    
    /// Loads stations silently in the background
    func loadStations() async {
        // If we already have data, don't fetch again
        guard allStations.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let url = "https://gateway.apiportal.ns.nl/nsapp-stations/v3"
            let response = try await NetworkManager.shared.fetch(from: url, as: StationResponse.self)
            
            // Filter for NL only
            self.allStations = response.payload.filter { $0.country == "NL" }
            
        } catch {
            self.errorMessage = error.localizedDescription
            print("Station fetch error: \(error)")
        }
        
        isLoading = false
    }
    
    /// Instantaneously picks a random station from memory
    func randomize() {
        guard !allStations.isEmpty else { return }
        
        withAnimation {
            station = allStations.randomElement()
        }
    }
    
    var isReady: Bool {
        !allStations.isEmpty
    }
}
