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
    @State private var allStations: [Station] = []
    @State private var filteredStations: [Station] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isUnauthorized = false
    @State private var showingSettings = false
    
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
                    .onChange(of: searchText) { _, newValue in
                        filterStations(with: newValue)
                    }
                
                // List of Stations
                ZStack {
                    if isLoading {
                        ProgressView("Loading stations...")
                    } else if let error = errorMessage {
                        VStack(spacing: 16) {
                            ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(error))
                            if isUnauthorized {
                                Button {
                                    showingSettings = true
                                } label: {
                                    Label("Open Settings", systemImage: "gear")
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 8)
                                }
                                .buttonStyle(.borderedProminent)
                            }
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
                SettingsView()
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
        guard let stationsRepository else { return }
        isLoading = true
        errorMessage = nil
        isUnauthorized = false

        do {
            // The Dutch stations, sorted A-Z
            let sorted = try await stationsRepository.dutchStations()
            
            await MainActor.run {
                self.allStations = sorted
                self.filteredStations = sorted
                self.isLoading = false
            }
        } catch {
            // Log the actual error for debugging
            print("❌ OnboardingView - Failed to load stations: \(error)")
            print("   Error type: \(type(of: error))")
            
            if let networkError = error as? NetworkError {
                print("   Network error: \(networkError)")
            }
            
            await MainActor.run {
                // Provide more specific error messages
                if let networkError = error as? NetworkError {
                    switch networkError {
                    case .unauthorized:
                        self.errorMessage = "No valid NS API key. Tap below to enter one (get a free key at apiportal.ns.nl)."
                        self.isUnauthorized = true
                    case .noConnection:
                        self.errorMessage = "No internet connection. Please check your network."
                    case .timeout:
                        self.errorMessage = "Connection timeout. Please try again."
                    default:
                        self.errorMessage = "Could not load stations: \(networkError.localizedDescription)"
                    }
                } else {
                    self.errorMessage = "Could not load stations. Please check your internet connection."
                }
                self.isLoading = false
            }
        }
    }
}
