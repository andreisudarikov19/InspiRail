//
//  OnboardingView.swift
//  InspiRail
//
//  Created by Andrei Sudarikov on 03/01/2026.
//

import SwiftUI
import Foundation

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    
    // We'll store the selected home station code & name in AppStorage
    @AppStorage("homeStationCode") private var homeStationCode: String = ""
    @AppStorage("homeStationName") private var homeStationName: String = ""
    
    @Environment(\.stationsRepository) private var stationsRepository
    
    @State private var searchText = ""
    /// The stations to pick from, or why they couldn't be loaded (#21).
    @State private var stationList = StationList()
    @State private var showingSettings = false
    
    private var filteredStations: [Station] {
        if searchText.isEmpty {
            return stationList.stations
        }
        return stationList.stations.filter {
            $0.names.long.localizedCaseInsensitiveContains(searchText) ||
            $0.identifiers.code.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 12) {
                    Image(systemName: "train.side.front.car")
                        .font(.system(size: 60))
                        .foregroundStyle(.blue)
                        .padding(.top, 40)
                    
                    Text("Welcome to InspiRail")
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
                
                // List of Stations
                ZStack {
                    if stationList.isLoading {
                        ProgressView("Loading stations...")
                    } else if let failure = stationList.failure {
                        VStack(spacing: 16) {
                            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(failure.message))
                            // Open Settings for the errors about the key, as
                            // before, and Retry for the others (#21)
                            RecoveryButton(action: failure.action, retry: retry, enterKey: { showingSettings = true })
                        }
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
            .sheet(isPresented: $showingSettings, onDismiss: {
                Task { await loadStations() }
            }) {
                SettingsView(done: { showingSettings = false })
            }
        }
    }
    
    // MARK: - Logic
    
    private func selectStation(_ station: Station) {
        // UPDATED: Using `identifiers.code`
        homeStationCode = station.identifiers.code
        homeStationName = station.names.long
    }
    
    private func loadStations() async {
        guard let stationsRepository else {
            reportMissingStationStore(in: "Onboarding")
            return
        }
        await stationList.load(from: stationsRepository)
    }
    
    /// Loads the stations again, in a task of its own (#21).
    private func retry() {
        guard let stationsRepository else {
            reportMissingStationStore(in: "Onboarding")
            return
        }
        Task { await stationList.retry(from: stationsRepository) }
    }
}
