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
    
    /// The key step's field.
    var keyInput = ""
    
    /// Why the key couldn't be written to the Keychain, which an alert shows,
    /// as Settings shows it. The screen clears it when the alert closes.
    var keySaveError: String?
    
    /// Whether a key is being saved: written, then checked by loading the
    /// stations with it. The key step shows its loading state meanwhile.
    private(set) var isSavingKey = false
    
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
    /// no key stored, which the step's title already says, on the station
    /// step, and while a key is saved, so that the old key's message doesn't
    /// read as the new key's.
    var keyProblem: String? {
        guard !isSavingKey,
              step == .key,
              let failure = stationList.failure,
              failure != LoadFailure(NetworkError.noKey) else { return nil }
        return failure.message
    }
    
    /// Whether the station step shows its search field: only once the
    /// stations have loaded, so it never filters a list that isn't there.
    var offersSearch: Bool {
        !stationList.isLoading && stationList.failure == nil
    }
    
    /// Whether Save Key is enabled: the field holds a key, and no key is
    /// being saved.
    var canSaveKey: Bool {
        !isSavingKey && !keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Loads the stations, as the screen opens.
    func load(from repository: StationsRepository) async {
        await stationList.load(from: repository)
    }
    
    /// The station step's Retry (#21).
    func retry(from repository: StationsRepository) async {
        await stationList.retry(from: repository)
    }
    
    /// Saves the key in the field as Settings saves one (#42), through the
    /// app's key check, so every window learns of it, and shows the check's
    /// answer: the list on the station step, the key step again with NS's
    /// answer about the key, or the station step with Retry when the key
    /// couldn't be checked. The check is the one request the save sends,
    /// with the new key; the store has let go of any download still running
    /// with the old one (#19). A key that can't be written shows its error,
    /// and nothing else changes.
    func saveKey(to storage: any APIKeyStorage, checkingWith keyCheck: APIKeyCheck, in repository: StationsRepository) async {
        guard !isSavingKey else { return }
        isSavingKey = true
        defer { isSavingKey = false }
        do {
            let answer = try await keyCheck.saveKey(keyInput, to: storage, in: repository, written: { keyInput = "" })
            if let answer {
                stationList.show(answer)
            }
        } catch {
            keySaveError = error.localizedDescription
        }
    }
    
    /// The app's key status changed, after a key was saved in another
    /// window, for example (iPad). When that key works and this window is
    /// still on the key step, it loads the stations, which the store has
    /// just kept, so it moves on to the list with no request. Any other
    /// status leaves this window as it is: saving a key here gives it the
    /// current answer. A window saving a key itself shows its own answer.
    func keyStatusChanged(to status: APIKeyStatus?, in repository: StationsRepository) async {
        guard status == .working, step == .key, !isSavingKey else { return }
        await stationList.load(from: repository)
    }
}
