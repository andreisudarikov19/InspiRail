//
//  OnboardingView.swift
//  rnsapp
//
//  Created by Andrei Sudarikov on 03/01/2026.
//

import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    
    // We'll store the selected home station code & name in AppStorage
    @AppStorage("homeStationCode") private var homeStationCode: String = ""
    @AppStorage("homeStationName") private var homeStationName: String = ""
    
    @State private var searchText = ""
    @State private var allStations: [Station] = []
    @State private var filteredStations: [Station] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "train.side.front.car")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                        .padding(.top, 40)
                    
                    Text("Welcome to RNS")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("To get started, please select your\n**Home Station**.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 20)
                
                // Search Field
                TextField("Search (e.g. Amsterdam)", text: $searchText)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .onChange(of: searchText) { _, newValue in
                        filterStations(with: newValue)
                    }
                
                // List of Stations
                ZStack {
                    if isLoading {
                        ProgressView("Loading stations...")
                    } else if let error = errorMessage {
                        ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
                    } else {
                        List(filteredStations) { station in
                            Button {
                                selectStation(station)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(station.names.long)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        
                                        Text(station.readableType)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    
                                    // UPDATED: Using `identifiers.code` instead of `idInfo.code`
                                    Text(station.identifiers.code)
                                        .font(.caption.monospaced())
                                        .padding(6)
                                        .background(Color.yellow.opacity(0.3))
                                        .cornerRadius(4)
                                    
                                    if station.identifiers.code == homeStationCode {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.blue)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .listStyle(.plain)
                    }
                }
                
                // Continue Button
                Button(action: {
                    hasCompletedOnboarding = true
                }) {
                    Text("Start Exploring")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(homeStationCode.isEmpty ? Color.gray.opacity(0.3) : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
                .disabled(homeStationCode.isEmpty)
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
            .navigationBarHidden(true)
            .task {
                await loadStations()
            }
        }
    }
    
    // MARK: - Logic
    
    private func selectStation(_ station: Station) {
        // UPDATED: Using `identifiers.code`
        homeStationCode = station.identifiers.code
        homeStationName = station.names.long
    }
    
    private func filterStations(with query: String) {
        if query.isEmpty {
            filteredStations = allStations
        } else {
            filteredStations = allStations.filter {
                $0.names.long.localizedCaseInsensitiveContains(query) ||
                $0.identifiers.code.localizedCaseInsensitiveContains(query)
            }
        }
    }
    
    private func loadStations() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let url = "https://gateway.apiportal.ns.nl/nsapp-stations/v3"
            let response = try await NetworkManager.shared.fetch(from: url, as: StationResponse.self)
            
            // Filter only Dutch stations and sort A-Z
            let stations = response.payload
                .filter { $0.country == "NL" }
                .sorted { $0.names.long < $1.names.long }
            
            await MainActor.run {
                self.allStations = stations
                self.filteredStations = stations
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Could not load stations. Please check your internet connection."
                self.isLoading = false
            }
        }
    }
}
