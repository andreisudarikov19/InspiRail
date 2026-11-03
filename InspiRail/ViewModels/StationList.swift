//
//  StationList.swift
//  InspiRail
//
//  The stations a screen lists for choosing the home station
//

import Foundation
import Observation

/// The Dutch stations that onboarding and the Home Station picker list for
/// choosing the home station, loaded from the app's station store (#18):
/// loading, loaded, or failed with the message and the one action the
/// screen offers for it (#21).
@MainActor
@Observable
final class StationList {
    /// The stations, sorted by name. Empty until a load succeeds.
    private(set) var stations: [Station] = []
    /// Whether a load is running. True until the first one ends.
    private(set) var isLoading = true
    /// Why the last load failed, and what the screen offers for it: Retry
    /// or the way to the key. Nil while loading and after a success.
    private(set) var failure: LoadFailure?
    
    /// Loads the stations. A load whose task was cancelled leaves the list
    /// loading: only the screen going away cancels it (#20).
    func load(from repository: StationsRepository) async {
        isLoading = true
        failure = nil
        do {
            show(.success(try await repository.dutchStations()))
        } catch {
            show(.failure(error))
        }
    }
    
    /// Shows an answer the store gave, as the end of a load shows its own:
    /// the stations, or why they couldn't be loaded and what the screen
    /// offers for it. Onboarding shows the check of a key it just saved this
    /// way, so a save sends one request (#42). A cancellation changes
    /// nothing.
    func show(_ answer: Result<[Station], Error>) {
        switch answer {
        case .success(let stations):
            self.stations = stations
            failure = nil
            isLoading = false
        case .failure(let error):
            guard let failure = LoadFailure(error) else { return }
            self.failure = failure
            isLoading = false
        }
    }
    
    /// Loads the stations again after a failure. The store drops its list,
    /// joins a download already in flight and keeps a refused key held
    /// back, so this never starts a second download or sends a key NS
    /// refused. The list shows its loading state from the start.
    func retry(from repository: StationsRepository) async {
        isLoading = true
        failure = nil
        await repository.forgetStations(keyChanged: false)
        await load(from: repository)
    }
}
