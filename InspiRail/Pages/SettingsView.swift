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
    @AppStorage("homeStationCode") private var homeStationCode: String = ""
    @AppStorage("homeStationName") private var homeStationName: String = ""
    @State private var showingResetAlert = false
    @State private var apiKeyInput: String = ""
    @State private var hasAPIKey: Bool = false
    @State private var apiHealthy: Bool = true
    @State private var keyStatusLoaded: Bool = false
    @State private var keyOperationInFlight: Bool = false
    @State private var keyOperationError: String?
    @Query private var visitedStations: [VisitedStation]

    /// Show the API-key section only when we know there's something to fix:
    /// missing key, or key present but failing health checks. Hidden while we
    /// haven't checked yet, to avoid a flicker.
    private var showAPIKeySection: Bool {
        keyStatusLoaded && (!hasAPIKey || !apiHealthy)
    }

    var body: some View {
        NavigationStack {
            Form {
                if showAPIKeySection {
                    Section {
                        HStack {
                            SettingsIcon(icon: "key.fill", color: hasAPIKey ? .orange : .orange)
                            VStack(alignment: .leading) {
                                Text("NS API Key").foregroundColor(.primary)
                                Text(hasAPIKey
                                     ? "Configured key isn't working"
                                     : "Not configured")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
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
                        if hasAPIKey {
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
                        Text("Get a free key at apiportal.ns.nl, then paste it above.")
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
                    HStack { SettingsIcon(icon: "info.circle.fill", color: .gray); Text("Version"); Spacer(); Text(appVersion).foregroundStyle(.secondary) }
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
                await refreshKeyStatus()
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
                await refreshKeyStatus()
                await MainActor.run { keyOperationInFlight = false }
            } catch {
                await MainActor.run {
                    keyOperationError = error.localizedDescription
                    keyOperationInFlight = false
                }
            }
        }
    }

    /// Check whether we have a key in the Keychain and whether the backend
    /// will accept it. Used to decide whether to surface the key-entry UI.
    private func refreshKeyStatus() async {
        let keyPresent = await KeychainManager.shared.hasAPIKey()
        var healthy = true
        if keyPresent {
            let report = await BackendHealthMonitor.shared.checkHealth()
            healthy = report.isHealthy
        }
        await MainActor.run {
            hasAPIKey = keyPresent
            apiHealthy = healthy
            keyStatusLoaded = true
        }
    }
    
    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
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
        do {
            let repository = StationsRepository(backend: BackendAPI())
            let sorted = try await repository.dutchStations()
            await MainActor.run { 
                self.allStations = sorted
                self.isLoading = false
            }
        } catch { 
            print("Error loading stations: \(error)")
            await MainActor.run { self.isLoading = false }
        }
    }
}
