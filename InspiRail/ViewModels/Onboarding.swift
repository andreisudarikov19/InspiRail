//
//  Onboarding.swift
//  InspiRail
//
//  What onboarding shows, and what it does with the key and the home station
//

import Foundation
import Observation

/// Onboarding's two steps, in one screen (#42): the key step, while only a
/// key can help the station load, and the station step, where the home
/// station is chosen.
///
/// The step follows the station load's result through the mapping every
/// screen uses (`NetworkError.recoveryAction(for:)`, #21). A failure whose
/// action is key entry shows the key step: no key, a Keychain that can't be
/// read, or a key NS rejected (401) or refused (403), which isn't sent
/// again for 15 minutes, so only another key can help. Anything else shows
/// the station step: loading, the list, or the error with Retry.
@MainActor
@Observable
final class Onboarding {
    enum Step: Equatable, Sendable {
        /// Asks for the key, since only a key can help the station load.
        case key
        /// Lists the stations, or says why they couldn't be loaded, with
        /// Retry.
        case station
    }
    
    /// The stations to pick from, loaded as the Home Station picker loads
    /// them (#21).
    let stationList = StationList()
    
    /// Where "Start Exploring" stores the home station: the app's defaults.
    /// Tests pass a suite of their own.
    private let defaults: UserDefaults
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    /// The step the station load's result calls for.
    var step: Step {
        stationList.failure?.action == .keyEntry ? .key : .station
    }
    
    /// The key step's text above the field: why the stored key can't be
    /// used, as every screen says it (`NetworkError.message(for:)`). Nil with
    /// no key stored, which the step's title already says, and on the
    /// station step.
    var keyProblem: String? {
        guard step == .key,
              let failure = stationList.failure,
              failure != LoadFailure(NetworkError.noKey) else { return nil }
        return failure.message
    }
    
    /// Whether the station step shows its search field: only once the
    /// stations have loaded, so it never filters a list that isn't there.
    var offersSearch: Bool {
        !stationList.isLoading && stationList.failure == nil
    }
    
    /// Loads the stations, as the screen opens.
    func load(from repository: StationsRepository) async {
        await stationList.load(from: repository)
    }
    
    /// The station step's Retry (#21).
    func retry(from repository: StationsRepository) async {
        await stationList.retry(from: repository)
    }
}
