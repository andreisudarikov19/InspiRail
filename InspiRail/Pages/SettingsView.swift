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
    @Environment(\.apiKeyCheck) private var keyCheck
    @AppStorage("homeStationCode") private var homeStationCode: String = ""
    @AppStorage("homeStationName") private var homeStationName: String = ""
    @State private var showingResetAlert = false
    @State private var apiKeyInput: String = ""
    @State private var keyOperationInFlight: Bool = false
    @State private var keyOperationError: String?
    /// Whether Settings' Retry is checking the key again (#21).
    @State private var retryInFlight = false
    @Query private var visitedStations: [VisitedStation]
    /// Closes Settings when it is shown as a sheet. Nil on the Settings tab.
    private let done: (() -> Void)?
    
    /// - Parameter done: Shown as a Done button that calls it, when Settings
    ///   is shown as a sheet, as onboarding shows it (#21). The Settings tab
    ///   passes none, and shows no Done button.
    init(done: (() -> Void)? = nil) {
        self.done = done
    }

    var body: some View {
        NavigationStack {
            Form {
                // The API-key section shows only when there's something to
                // say, and offers the key field and Remove Key only where a
                // key can help (#19). Hidden until the first check ends. The
                // status is the app's, so every window shows the same one.
                if let keyStatus = keyCheck?.status, let keyMessage = keyStatus.message {
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
                        // When the key couldn't be checked, for a reason
                        // another try can fix (#21)
                        if keyStatus.offersRetry {
                            Button {
                                retryKeyCheck()
                            } label: {
                                HStack {
                                    SettingsIcon(icon: "arrow.clockwise", color: .blue)
                                    Text(retryInFlight ? "Checking…" : "Retry")
                                }
                            }
                            .disabled(retryInFlight)
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
                        // Not while a key just saved, here or in another
                        // window, is being checked.
                        if keyCheck?.offersRemoval == true {
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
            .toolbar {
                if let done {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: done)
                    }
                }
            }
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

    /// Saves the key as onboarding does (#42): trimmed, written to the
    /// Keychain, then checked, so every window shows its status (#19). The
    /// field clears once the key is written.
    private func saveAPIKey() {
        guard let stationsRepository else {
            reportMissingStationStore(in: "Settings")
            return
        }
        guard let keyCheck else {
            reportMissingKeyCheck(in: "Settings")
            return
        }
        keyOperationInFlight = true
        Task {
            do {
                try await keyCheck.saveKey(apiKeyInput, to: KeychainManager.shared, in: stationsRepository, written: { apiKeyInput = "" })
            } catch {
                keyOperationError = error.localizedDescription
            }
            keyOperationInFlight = false
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
        guard let keyCheck else {
            reportMissingKeyCheck(in: "Settings")
            return
        }
        await keyCheck.refresh(using: stationsRepository)
    }
    
    /// Checks the key again after it couldn't be checked, in a task of its
    /// own, so that leaving Settings doesn't cut it short (#21).
    private func retryKeyCheck() {
        guard let stationsRepository else {
            reportMissingStationStore(in: "Settings")
            return
        }
        guard let keyCheck else {
            reportMissingKeyCheck(in: "Settings")
            return
        }
        retryInFlight = true
        Task {
            await keyCheck.retry(using: stationsRepository)
            retryInFlight = false
        }
    }
    
    /// A key was saved or removed: the store forgets what it knew about the
    /// old one, and the key stored now is checked with a request of its own,
    /// even one NS refused before (#19, #20).
    private func keyChanged() async {
        guard let stationsRepository else {
            reportMissingStationStore(in: "Settings")
            return
        }
        guard let keyCheck else {
            reportMissingKeyCheck(in: "Settings")
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
    @State private var stationList = StationList()
    @State private var searchText = ""
    
    var filteredStations: [Station] {
        if searchText.isEmpty { return stationList.stations }
        else { return stationList.stations.filter { $0.names.long.localizedCaseInsensitiveContains(searchText) || $0.identifiers.code.localizedCaseInsensitiveContains(searchText) } }
    }
    
    var body: some View {
        List {
            if stationList.isLoading { ProgressView("Loading stations...").frame(maxWidth: .infinity).listRowBackground(Color.clear) }
            else if let failure = stationList.failure {
                // The error and its one action, not an empty list (#21). The
                // key section is in Settings, the screen this one came from.
                VStack(alignment: .leading, spacing: 12) {
                    Text(failure.message)
                    RecoveryButton(action: failure.action, keyEntryTitle: "Back to Settings", retry: retry, enterKey: { dismiss() })
                }
                .padding(.vertical, 4)
            }
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
        .task {
            guard stationList.stations.isEmpty else { return }
            guard let stationsRepository else {
                reportMissingStationStore(in: "The Home Station picker")
                return
            }
            await stationList.load(from: stationsRepository)
        }
    }
    
    /// Loads the stations again, in a task of its own, so that leaving the
    /// picker doesn't cut it short (#21).
    private func retry() {
        guard let stationsRepository else {
            reportMissingStationStore(in: "The Home Station picker")
            return
        }
        Task { await stationList.retry(from: stationsRepository) }
    }
}
