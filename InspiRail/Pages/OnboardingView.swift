//
//  OnboardingView.swift
//  InspiRail
//
//  Created by Andrei Sudarikov on 03/01/2026.
//

import SwiftUI
import Foundation

/// The window's screen until a home station is stored (#22): the key step,
/// while only a key can help the station load, or the station step, where
/// the home station is chosen (#42). `Onboarding` decides which shows and
/// holds what the user entered; this view draws it.
struct OnboardingView: View {
    @Environment(\.stationsRepository) private var stationsRepository
    @Environment(\.apiKeyCheck) private var keyCheck

    /// The step, the key field and the selected station (#22, #42).
    @State private var onboarding = Onboarding()
    @State private var searchText = ""

    private var filteredStations: [Station] {
        if searchText.isEmpty {
            return onboarding.stationList.stations
        }
        return onboarding.stationList.stations.filter {
            $0.names.long.localizedCaseInsensitiveContains(searchText) ||
            $0.identifiers.code.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch onboarding.step {
                case .key:
                    keyStep
                case .station:
                    stationStep
                }
            }
            .navigationBarHidden(true)
            .task {
                await loadStations()
            }
            // A key saved in any window: this one shows the answer about
            // the key stored now too (#42)
            .onChange(of: keyCheck?.keyChanges) {
                keySavedOrRemoved()
            }
            .alert("API Key Error", isPresented: Binding(
                get: { onboarding.keySaveError != nil },
                set: { if !$0 { onboarding.keySaveError = nil } }
            )) {
                Button("OK", role: .cancel) { onboarding.keySaveError = nil }
            } message: { Text(onboarding.keySaveError ?? "") }
        }
    }

    // MARK: - Steps

    /// Asks for the key, with what it is for and where to get one. A scroll
    /// view, with the explanation right above the field, so that the
    /// explanation stays in view above the keyboard.
    private var keyStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                header {
                    VStack(spacing: 8) {
                        Text("API key needed")
                            .font(.title3)
                            .fontWeight(.bold)
                            .accessibilityAddTraits(.isHeader)

                        Text("InspiRail loads Dutch stations from the NS API, which needs a free API key. Get one from the NS API portal, then paste it here.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal)
                }

                Link(destination: URL(string: "https://apiportal.ns.nl")!) {
                    HStack(spacing: 4) {
                        Text("Get a free key at apiportal.ns.nl")
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                    }
                }

                // Why the stored key can't be used, after any key error but
                // a missing key, which the title already says
                if let keyProblem = onboarding.keyProblem {
                    Text(keyProblem)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                SecureField("Paste your NS API key", text: $onboarding.keyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit {
                        if onboarding.canSaveKey {
                            saveKey()
                        }
                    }
                    .disabled(onboarding.isSavingKey)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)

                Button(action: saveKey) {
                    primaryLabel(enabled: onboarding.canSaveKey) {
                        HStack(spacing: 8) {
                            if onboarding.isSavingKey {
                                ProgressView()
                                    .tint(.white)
                                Text("Saving…")
                            } else {
                                Text("Save Key")
                            }
                        }
                    }
                }
                .disabled(!onboarding.canSaveKey)
                .padding(.horizontal)
            }
            .padding(.bottom, 20)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// Lists the stations to choose the home station from, or says why they
    /// couldn't be loaded, with Retry.
    private var stationStep: some View {
        VStack(spacing: 20) {
            header {
                Text("To get started, please select your\n**Home Station**.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 20)

            // Search Field, once there are stations to search (#42)
            if onboarding.offersSearch {
                TextField("Search (e.g. Amsterdam)", text: $searchText)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
            }

            // List of Stations
            ZStack {
                if onboarding.stationList.isLoading {
                    ProgressView("Loading stations...")
                } else if let failure = onboarding.stationList.failure {
                    VStack(spacing: 16) {
                        ContentUnavailableView("Error", systemImage: "exclamationmark.triangle", description: Text(failure.message))
                        // Retry (#21). The errors only a key can fix show
                        // the key step instead, so this never offers key
                        // entry.
                        RecoveryButton(action: failure.action, retry: retry, enterKey: {})
                    }
                } else {
                    List(filteredStations) { station in
                        let isSelected = station.identifiers.code == onboarding.selection?.identifiers.code
                        Button {
                            // Selects it, and stores nothing until Start
                            // Exploring (#22)
                            onboarding.select(station)
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

                                if isSelected {
                                    // VoiceOver reads the row as selected
                                    // instead
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.blue)
                                        .accessibilityHidden(true)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                    .listStyle(.plain)
                }
            }

            // Continue Button: stores the home station, which ends onboarding
            Button {
                onboarding.startExploring()
            } label: {
                primaryLabel(enabled: onboarding.canStartExploring) {
                    Text("Start Exploring")
                }
            }
            .disabled(!onboarding.canStartExploring)
            .padding(.horizontal)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Parts

    /// The icon and the welcome, on both steps, above the step's own text.
    private func header<StepText: View>(@ViewBuilder text: () -> StepText) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "train.side.front.car")
                .font(.system(size: 60))
                .foregroundStyle(.blue)
                .padding(.top, 40)

            Text("Welcome to InspiRail")
                .font(.largeTitle)
                .fontWeight(.bold)

            text()
        }
    }

    /// The look of the step's main button: full width, blue once it can be
    /// pressed.
    private func primaryLabel<Content: View>(enabled: Bool, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(enabled ? Color.blue : Color.gray.opacity(0.3))
            .foregroundColor(.white)
            .cornerRadius(16)
    }

    // MARK: - Logic

    private func loadStations() async {
        guard let stationsRepository else {
            reportMissingStationStore(in: "Onboarding")
            return
        }
        guard let keyCheck else {
            reportMissingKeyCheck(in: "Onboarding")
            return
        }
        await onboarding.load(from: stationsRepository, following: keyCheck)
    }

    /// Loads the stations again, in a task of its own (#21).
    private func retry() {
        guard let stationsRepository else {
            reportMissingStationStore(in: "Onboarding")
            return
        }
        guard let keyCheck else {
            reportMissingKeyCheck(in: "Onboarding")
            return
        }
        Task { await onboarding.retry(from: stationsRepository, following: keyCheck) }
    }

    /// Saves the key in the field and loads the stations with it, in a task
    /// of its own, so that leaving doesn't cut it short (#42). When the save
    /// ends back on the key step with text above the field, VoiceOver reads
    /// that text, which otherwise appears out of its focus.
    private func saveKey() {
        guard let stationsRepository else {
            reportMissingStationStore(in: "Onboarding")
            return
        }
        guard let keyCheck else {
            reportMissingKeyCheck(in: "Onboarding")
            return
        }
        Task {
            await onboarding.saveKey(to: KeychainManager.shared, checkingWith: keyCheck, in: stationsRepository)
            // Not after a key that couldn't be written, whose alert says why
            if onboarding.keySaveError == nil, let keyProblem = onboarding.keyProblem {
                AccessibilityNotification.Announcement(keyProblem).post()
            }
        }
    }

    /// Follows the keys saved in any window, in a task of its own (#42).
    private func keySavedOrRemoved() {
        guard let stationsRepository else {
            reportMissingStationStore(in: "Onboarding")
            return
        }
        guard let keyCheck else {
            reportMissingKeyCheck(in: "Onboarding")
            return
        }
        Task { await onboarding.keySavedOrRemoved(in: stationsRepository, following: keyCheck) }
    }
}
