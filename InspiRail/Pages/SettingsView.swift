//
//  SettingsView.swift
//  InspiRail
//
//  Created by Andrei Sudarikov on 03/01/2026.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.stationsRepository) private var stationsRepository
    @AppStorage("homeStationCode") private var homeStationCode: String = ""
    @AppStorage("homeStationName") private var homeStationName: String = ""
    @State private var showingResetAlert = false
    @State private var apiKeyInput: String = ""
    @State private var keyCheck = APIKeyCheck()
    @State private var keyOperationInFlight: Bool = false
    @State private var keyOperationError: String?
    @Query private var visitedStations: [VisitedStation]

    var body: some View {
        NavigationStack {
            Form {
                // The API-key section shows only when there's something to
                // say, and offers the key field and Remove Key only where a
                // key can help (#19). Hidden until the first check ends.
                if let keyStatus = keyCheck.status, let keyMessage = keyStatus.message {
                    Section {
                        HStack {
                            SettingsIcon(icon: "key.fill", color: .orange)
                            VStack(alignment: .leading) {
                                Text("NS API Key").foregroundColor(.primary)
                                Text(keyMessage)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        if keyStatus.offersKeyEntry {
                            SecureField("Paste your NS API key", text: $apiKeyInput)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Button {
                                saveAPIKey()
                            } label: {
                                HStack {
                                    SettingsIcon(icon: "checkmark.circle.fill", color: .blue)
                                    Text(keyOperationInFlight ? "Saving…" : "Save Key")
                                }
                            }
                            .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty || keyOperationInFlight)
                        }
                        if keyStatus.offersRemoval {
                            Button(role: .destructive) {
                                removeAPIKey()
                            } label: {
                                HStack { SettingsIcon(icon: "trash.fill", color: .red); Text("Remove Key") }
                            }
                            .disabled(keyOperationInFlight)
                        }
                    } header: {
                        Text("API Configuration")
                    } footer: {
                        if keyStatus.offersKeyEntry {
                            Text("Get a free key at apiportal.ns.nl, then paste it above.")
                        }
                    }
                }
                Section {
                    NavigationLink {
                        StationSelectorView(selectedCode: $homeStationCode, selectedName: $homeStationName)
                    } label: {
                        HStack {
                            SettingsIcon(icon: "house.fill", color: .blue)
                            VStack(alignment: .leading) {
                                Text("Home Station").foregroundColor(.primary)
                                Text(homeStationName.isEmpty ? "Select a station" : homeStationName)
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Travel Preferences")
                }
                Section {
                    Button(role: .destructive) { showingResetAlert = true } label: {
                        HStack { SettingsIcon(icon: "trash.fill", color: .red); Text("Reset Logbook") }
                    }
                    .disabled(visitedStations.isEmpty)
                } header: {
                    Text("Data Management")
                } footer: {
                    Text("This will remove all \(visitedStations.count) stations from your history.")
                }
                Section {
                    HStack { SettingsIcon(icon: "info.circle.fill", color: .gray); Text("Version"); Spacer(); Text("\(AppConfiguration.appVersion) (\(AppConfiguration.buildNumber))").foregroundStyle(.secondary) }
                    Link(destination: URL(string: "https://apiportal.ns.nl")!) {
                        HStack { SettingsIcon(icon: "server.rack", color: .indigo); Text("Powered by NS API"); Spacer(); Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(.secondary) }
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .task { await refreshKeyStatus() }
            .alert("Reset History?", isPresented: $showingResetAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete All", role: .destructive) { resetHistory() }
            } message: { Text("This action cannot be undone.") }
            .alert("API Key Error", isPresented: Binding(
                get: { keyOperationError != nil },
                set: { if !$0 { keyOperationError = nil } }
            )) {
                Button("OK", role: .cancel) { keyOperationError = nil }
            } message: { Text(keyOperationError ?? "") }
        }
    }

    private func saveAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        keyOperationInFlight = true
        Task {
            do {
                try await KeychainManager.shared.saveAPIKey(key)
                await MainActor.run { apiKeyInput = "" }
                await keyChanged()
                await MainActor.run { keyOperationInFlight = false }
            } catch {
                await MainActor.run {
                    keyOperationError = error.localizedDescription
                    keyOperationInFlight = false
                }
            }
        }
    }

    private func removeAPIKey() {
        keyOperationInFlight = true
        Task {
            do {
                try await KeychainManager.shared.deleteAPIKey()
                await keyChanged()
                await MainActor.run { keyOperationInFlight = false }
            } catch {
                await MainActor.run {
                    keyOperationError = error.localizedDescription
                    keyOperationInFlight = false
                }
            }
        }
    }

    /// Checks the key by asking the app's station store with it, so a visit
    /// within the store's hour sends nothing (#19).
    private func refreshKeyStatus() async {
        guard let stationsRepository else {
            reportMissingStationStore(in: "Settings")
            return
        }
        await keyCheck.refresh(using: stationsRepository)
    }
    
    /// A key was saved or removed: the store forgets what it knew about the
    /// old one, and the key stored now is checked with a request of its own,
    /// even one NS refused before (#19, #20).
    private func keyChanged() async {
        guard let stationsRepository else {
            reportMissingStationStore(in: "Settings")
            return
        }
        await keyCheck.keyChanged(in: stationsRepository)
    }
    
    private func resetHistory() {
        withAnimation {
            for station in visitedStations { modelContext.delete(station) }
            try? modelContext.save()
        }
    }
}

struct SettingsIcon: View {
    let icon: String; let color: Color
    var body: some View {
        Image(systemName: icon).font(.system(size: 14, weight: .semibold)).foregroundColor(.white)
            .frame(width: 28, height: 28).background(color.gradient).cornerRadius(6)
    }
}

struct StationSelectorView: View {
    @Binding var selectedCode: String
    @Binding var selectedName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.stationsRepository) private var stationsRepository
    @State private var allStations: [Station] = []
    @State private var searchText = ""
    @State private var isLoading = true
    
    var filteredStations: [Station] {
        if searchText.isEmpty { return allStations }
        else { return allStations.filter { $0.names.long.localizedCaseInsensitiveContains(searchText) || $0.identifiers.code.localizedCaseInsensitiveContains(searchText) } }
    }
    
    var body: some View {
        List {
            if isLoading { ProgressView("Loading stations...").frame(maxWidth: .infinity).listRowBackground(Color.clear) }
            else {
                ForEach(filteredStations) { station in
                    Button {
                        // FIXED: .identifiers.code
                        selectedCode = station.identifiers.code
                        selectedName = station.names.long
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(station.names.long).foregroundStyle(.primary)
                                Text(station.readableType).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            // FIXED: .identifiers.code
                            if station.identifiers.code == selectedCode { Image(systemName: "checkmark").foregroundStyle(.blue) }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("Select Home")
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search station")
        .task { await fetchStations() }
    }
    
    private func fetchStations() async {
        guard allStations.isEmpty else { return }
        guard let stationsRepository else {
            reportMissingStationStore(in: "The Home Station picker")
            return
        }
        do {
            let sorted = try await stationsRepository.dutchStations()
            await MainActor.run { 
                self.allStations = sorted
                self.isLoading = false
            }
        } catch is CancellationError {
            // A cancelled load leaves the picker as it was (#20).
        } catch { 
            print("Error loading stations: \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }
}
