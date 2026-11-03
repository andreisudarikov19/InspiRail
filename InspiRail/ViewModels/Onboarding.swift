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
///
/// Every answer it shows is about the key stored now: it follows the keys
/// saved in any window (`APIKeyCheck.keyChanges`), and loads again when a
/// key change overtook its load, Retry or save check, or reached it idle.
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
    
    /// The station the user tapped, which shows the checkmark. Only "Start
    /// Exploring" stores it, so a tap, even an accidental one while
    /// scrolling, doesn't end onboarding (#22).
    private(set) var selection: Station?
    
    /// The keys saved or removed so far, in any window
    /// (`APIKeyCheck.keyChanges`), when the load, Retry or save check whose
    /// answer is shown started. Nil until the first answer shows.
    private var answeredKeyChanges: Int?
    
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
    /// used, as Settings' key section says it (`APIKeyStatus.message`), since
    /// both ask for a key right there. So a rejected key reads "NS didn't
    /// accept this key.", not Discover's "Check it in Settings". Nil with no
    /// key stored, which the step's title already says, on the station
    /// step, and while a key is saved, so that the old key's message doesn't
    /// read as the new key's.
    var keyProblem: String? {
        guard !isSavingKey,
              step == .key,
              let failure = stationList.failure else { return nil }
        // The key error the failure stands for, among those with text of
        // their own: no key has none
        let keyErrors: [NetworkError] = [.keychainUnavailable, .keyRejected, .forbidden]
        return keyErrors.first { LoadFailure($0) == failure }
            .flatMap { APIKeyStatus(for: $0) }?.message
    }
    
    /// Whether the station step shows its search field: only once the
    /// stations have loaded, so it never filters a list that isn't there.
    var offersSearch: Bool {
        !stationList.isLoading && stationList.failure == nil
    }
    
    /// Whether "Start Exploring" is enabled: once a station is selected.
    var canStartExploring: Bool {
        selection != nil
    }
    
    /// Whether Save Key is enabled: the field holds a key, and no key is
    /// being saved.
    var canSaveKey: Bool {
        !isSavingKey && !keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    /// Loads the stations, as the screen opens, and shows the answer once it
    /// is about the key stored now, as `show(_:startedAt:following:in:)`
    /// does.
    func load(from repository: StationsRepository, following keyCheck: APIKeyCheck) async {
        let changes = keyCheck.keyChanges
        let answer = await stationList.fetch(from: repository)
        await show(answer, startedAt: changes, following: keyCheck, in: repository)
    }
    
    /// The station step's Retry (#21), whose answer shows as a load's does.
    func retry(from repository: StationsRepository, following keyCheck: APIKeyCheck) async {
        let changes = keyCheck.keyChanges
        let answer = await stationList.fetchAgain(from: repository)
        await show(answer, startedAt: changes, following: keyCheck, in: repository)
    }
    
    /// Saves the key in the field as Settings saves one (#42), through the
    /// app's key check, so every window learns of it, and shows the check's
    /// answer: the list on the station step, the key step again with NS's
    /// answer about the key, or the station step with Retry when the key
    /// couldn't be checked. The check is the one request the save sends,
    /// with the new key; the store has let go of any download still running
    /// with the old one (#19). When another window saved a key meanwhile,
    /// the answer may be about this window's key, since replaced, so it
    /// shows the answer about the key stored now instead. A key that can't
    /// be written shows its error, and nothing else changes.
    func saveKey(to storage: any APIKeyStorage, checkingWith keyCheck: APIKeyCheck, in repository: StationsRepository) async {
        guard !isSavingKey else { return }
        isSavingKey = true
        defer { isSavingKey = false }
        // The save is a key change of its own, which its check follows
        let changes = keyCheck.keyChanges + 1
        do {
            let answer = try await keyCheck.saveKey(keyInput, to: storage, in: repository, written: { keyInput = "" })
            if let answer {
                await show(answer, startedAt: changes, following: keyCheck, in: repository)
            }
        } catch {
            keySaveError = error.localizedDescription
        }
    }
    
    /// A key was saved or removed, in this window or another (iPad), as the
    /// screen learns from `APIKeyCheck.keyChanges`. When this window is idle,
    /// not loading, retrying or saving a key, and what it shows is about an
    /// earlier key, it loads the stations again, so it shows the answer
    /// about the key stored now: the list after a key that works, which the
    /// store has kept, so with no request; the key step with NS's answer
    /// after a key NS rejected or refused, which isn't sent again; the
    /// station step with Retry after a key NS couldn't check. A window that
    /// is loading, retrying or saving a key gets that answer as its own
    /// ends, so it doesn't load twice.
    func keySavedOrRemoved(in repository: StationsRepository, following keyCheck: APIKeyCheck) async {
        guard !stationList.isLoading,
              !isSavingKey,
              keyCheck.keyChanges != answeredKeyChanges else { return }
        await load(from: repository, following: keyCheck)
    }
    
    /// Shows `answer`, from a load, Retry or save check that started when
    /// `keyCheck` had counted `changes` keys saved or removed, if none was
    /// saved or removed since. Otherwise the answer may be about a key since
    /// replaced (#19), so it loads again, which joins the download for the
    /// key stored now or reads the list the store kept for it, and so sends
    /// no request unless that key's answer wasn't kept. Each load counts
    /// afresh, and only another key change, which the user makes, loads
    /// again.
    private func show(_ answer: Result<[Station], Error>, startedAt changes: Int, following keyCheck: APIKeyCheck, in repository: StationsRepository) async {
        var answer = answer
        var changes = changes
        while changes != keyCheck.keyChanges {
            changes = keyCheck.keyChanges
            answer = await stationList.fetch(from: repository)
        }
        answeredKeyChanges = changes
        stationList.show(answer)
    }
    
    /// Selects the station the user tapped. Nothing is stored yet.
    func select(_ station: Station) {
        selection = station
    }
    
    /// "Start Exploring": stores the selected station as the home station,
    /// which ends onboarding in every window. The name comes first, so it
    /// is there when the tabs appear. Does nothing until a station is
    /// selected.
    func startExploring() {
        guard let selection else { return }
        defaults.set(selection.names.long, forKey: "homeStationName")
        defaults.set(selection.identifiers.code, forKey: "homeStationCode")
    }
    
    /// Whether onboarding is done: once a home station is stored (#22). Only
    /// "Start Exploring" stores one during onboarding, so the home station
    /// already means onboarding is done, with no flag of its own: users of
    /// earlier versions, who have a home station, need no migration, and a
    /// launch with `-homeStationCode`, which sets it only for that launch,
    /// leaves nothing behind.
    static func isDone(homeStationCode: String) -> Bool {
        !homeStationCode.isEmpty
    }
}
