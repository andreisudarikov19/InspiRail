//
//  APIKeyCheck.swift
//  InspiRail
//
//  What Settings says about the NS API key
//

import Foundation
import Observation

/// What Settings says about the API key (#19): whether the key section
/// shows, its caption, and which controls it offers.
///
/// It comes from asking the shared station store with the current key, so it
/// says the key is at fault only when NS answered about that key: a 401 or a
/// 403. Any other failure shows the message Discover shows for it, and a
/// new key can't fix it, so it offers neither the key field nor Remove Key.
nonisolated enum APIKeyStatus: Equatable, Sendable {
    /// The store has the stations: no key section.
    case working
    /// No key is stored.
    case noKey
    /// NS rejected the key (401).
    case rejected
    /// NS refused the key (403): forbidden, or over its quota.
    case refused
    /// The Keychain couldn't be read. Saving a key replaces an item that
    /// can't be read, so the key field stays.
    case keychainUnavailable
    /// The key couldn't be checked, for a reason a new key can't fix: no
    /// connection, NS busy or failing, or data the app can't read. Holds the
    /// message Discover shows for it.
    case cantCheck(String)
    
    /// The status a failed check stands for, or nil for a cancellation,
    /// which leaves the status as it was. It follows what every screen
    /// offers for the error (`NetworkError.recoveryAction(for:)`, #21): Retry
    /// becomes "can't check", and key entry the key's own state.
    init?(for error: Error) {
        guard let failure = LoadFailure(error) else { return nil }
        switch failure.action {
        case .retry:
            self = .cantCheck(failure.message)
        case .keyEntry:
            switch error as? NetworkError {
            case .keyRejected:
                self = .rejected
            case .forbidden:
                self = .refused
            case .keychainUnavailable:
                self = .keychainUnavailable
            default:
                // No key: the one other error only a key can help with
                self = .noKey
            }
        }
    }
    
    /// The key section's caption, or nil when there's nothing to say and the
    /// section stays hidden. Every text but two is the one Discover shows
    /// (`NetworkError.message(for:)`); "Check it in Settings" and "Add one in
    /// Settings" don't fit inside Settings.
    var message: String? {
        switch self {
        case .working:
            return nil
        case .noKey:
            return "Not configured"
        case .rejected:
            return "NS didn't accept this key."
        case .refused:
            return NetworkError.forbidden.errorDescription
        case .keychainUnavailable:
            return NetworkError.keychainUnavailable.errorDescription
        case .cantCheck(let message):
            return message
        }
    }
    
    /// Whether the section offers the key field and Save Key: when another
    /// key can help.
    var offersKeyEntry: Bool {
        switch self {
        case .noKey, .rejected, .refused, .keychainUnavailable:
            return true
        case .working, .cantCheck:
            return false
        }
    }
    
    /// Whether the section offers Retry: when the key couldn't be checked,
    /// for a reason another try can fix, which are the errors every screen
    /// offers Retry for (#21).
    var offersRetry: Bool {
        switch self {
        case .cantCheck:
            return true
        case .working, .noKey, .rejected, .refused, .keychainUnavailable:
            return false
        }
    }
    
    /// Whether the section offers Remove Key: only when NS rejected this very
    /// key (401). A key NS refused (403) may only be over its usage limit, so
    /// it is still a valid key, and the key field already replaces it.
    var offersRemoval: Bool {
        switch self {
        case .rejected:
            return true
        case .working, .noKey, .refused, .keychainUnavailable, .cantCheck:
            return false
        }
    }
}

/// Settings' check of the API key (#19). It asks the app's station store for
/// the Dutch stations, as every screen does, so a visit within the store's
/// hour sends nothing, a download in flight is shared, and Settings and
/// Discover agree on the same list. Settings and onboarding both save a key
/// through it (#42), so every window learns of the new key.
@MainActor
@Observable
final class APIKeyCheck {
    /// What the last check that counted said. Nil until the first one ends,
    /// so Settings shows no key section while it checks for the first time.
    private(set) var status: APIKeyStatus?
    
    /// Whether a key just saved or removed is being checked. Until that
    /// check ends, the status still says what the last check said about the
    /// key before it.
    private(set) var isCheckingNewKey = false
    
    /// Whether Settings offers Remove Key, in every window: when the status
    /// does, and no new key is being checked. Otherwise a window would offer
    /// to remove the key just saved, for what NS said about the one before
    /// it (#19).
    var offersRemoval: Bool {
        !isCheckingNewKey && status?.offersRemoval == true
    }
    
    /// Counts the keys saved or removed, so that a check started before the
    /// last change, which may be about the key since replaced, doesn't count.
    /// Checks started since then all ask about the key stored now and share
    /// the store's download, so they agree, and a newer one doesn't void an
    /// older one.
    @ObservationIgnored private var keyChanges = 0
    
    /// Asks the store with the current key, and shows its answer. The store's
    /// download runs on when the check's task is cancelled, for example by
    /// leaving Settings, so the answer still arrives: it is dropped, and the
    /// status stays as it was. So is the answer of a check that started
    /// before a key was saved or removed. A check cut short doesn't stop
    /// another check of the same key from counting, such as the one that
    /// follows a save.
    ///
    /// - Returns: The store's answer, whether or not it counted for the
    ///   status: the stations, or why they couldn't be loaded.
    @discardableResult
    func refresh(using repository: StationsRepository) async -> Result<[Station], Error> {
        let keyChangesAtStart = keyChanges
        let result: Result<[Station], Error>
        do {
            result = .success(try await repository.dutchStations())
        } catch {
            result = .failure(error)
        }
        let answer: APIKeyStatus?
        switch result {
        case .success:
            answer = .working
        case .failure(let error):
            answer = APIKeyStatus(for: error)
        }
        if let answer, !Task.isCancelled, keyChangesAtStart == keyChanges {
            status = answer
        }
        return result
    }
    
    /// Settings' Retry, when the key couldn't be checked (#21): the store
    /// drops its list, joins a download already in flight and keeps a
    /// refused key held back, and the key is checked again as `refresh`
    /// checks it.
    func retry(using repository: StationsRepository) async {
        await repository.forgetStations(keyChanged: false)
        await refresh(using: repository)
    }
    
    /// A key was saved or removed: checks again with the key stored now,
    /// which the store sends whatever it knew about the old one. A check
    /// already running answers for the old key, so it no longer counts, from
    /// before anything is awaited. The new key counts as being checked until
    /// this check ends, or, when another key was saved or removed meanwhile,
    /// until that key's check ends.
    ///
    /// - Returns: The store's answer for the key stored now, as `refresh`
    ///   returns it.
    @discardableResult
    func keyChanged(in repository: StationsRepository) async -> Result<[Station], Error> {
        keyChanges += 1
        let change = keyChanges
        isCheckingNewKey = true
        await repository.forgetStations(keyChanged: true)
        let result = await refresh(using: repository)
        if change == keyChanges {
            isCheckingNewKey = false
        }
        return result
    }
    
    /// Saves a key the user entered, the one way Settings and onboarding
    /// both save one (#42): `input`, without the spaces and line breaks
    /// around it, is written to `storage`, then checked as `keyChanged(in:)`
    /// checks it, so every window shows the new key's status.
    ///
    /// - Parameters:
    ///   - storage: Where the key is written: the Keychain in the app.
    ///   - written: Runs once the key is written, before it is checked: the
    ///     screen clears its field then.
    /// - Returns: The store's answer for the saved key: the stations, or why
    ///   they couldn't be loaded. Nil when `input` holds only spaces and
    ///   line breaks, and nothing is saved.
    /// - Throws: The storage's error when the key can't be written. Nothing
    ///   is checked then.
    @discardableResult
    func saveKey(
        _ input: String,
        to storage: any APIKeyStorage,
        in repository: StationsRepository,
        written: () -> Void = {}
    ) async throws -> Result<[Station], Error>? {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        try await storage.saveAPIKey(key)
        written()
        return await keyChanged(in: repository)
    }
}
