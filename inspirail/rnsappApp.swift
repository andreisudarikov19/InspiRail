//
//  rnsappApp.swift
//  rnsapp
//
//  Created by Andrei Sudarikov on 02/01/2026.
//

import SwiftUI
import SwiftData

@main
struct OranjeRailApp: App {
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .task {
                    await runNetworkTest()
                }
        // This line initializes the database for the app
        .modelContainer(for: VisitedStation.self)
        }
    }
    
    func runNetworkTest() async {
        let testURL = "https://gateway.apiportal.ns.nl/nsapp-stations/v3?includeNonPlannableStations=false"
        
        print("[DEBUG] Starting Headless Backend Test...")
        
        do {
            // Attempt to fetch the stations list
            let response = try await NetworkManager.shared.fetch(from: testURL, as: StationResponse.self)
            
            print("[DEBUG] TEST SUCCESS!")
            print("[DEBUG] Found \(response.payload.count) stations.")
            
            // Print the first station
            if let firstStation = response.payload.first {
                print("[DEBUG] First station in list: \(firstStation.names.long)")
            }
            
        } catch {
            print("[DEBUG] TEST FAILED with error: \(error.localizedDescription)")
        }
    }
}
