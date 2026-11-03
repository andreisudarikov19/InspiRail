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
    /// which leaves the status as it was.
    init?(for error: Error) {
        guard let message = NetworkError.message(for: error) else { return nil }
        switch error as? NetworkError {
        case .noKey:
            self = .noKey
        case .keyRejected:
            self = .rejected
        case .forbidden:
            self = .refused
        case .keychainUnavailable:
            self = .keychainUnavailable
        default:
            self = .cantCheck(message)
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
    
    /// Whether the section offers Remove Key: only when NS answered about
    /// this very key.
    var offersRemoval: Bool {
        switch self {
        case .rejected, .refused:
            return true
        case .working, .noKey, .keychainUnavailable, .cantCheck:
            return false
        }
    }
}

/// Settings' check of the API key (#19). It asks the app's station store for
/// the Dutch stations, as every screen does, so a visit within the store's
/// hour sends nothing, a download in flight is shared, and Settings and
/// Discover agree on the same list.
@MainActor
@Observable
final class APIKeyCheck {
    /// What the last check that counted said. Nil until the first one ends,
    /// so Settings shows no key section while it checks for the first time.
    private(set) var status: APIKeyStatus?
    
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
    func refresh(using repository: StationsRepository) async {
        let keyChangesAtStart = keyChanges
        let answer: APIKeyStatus?
        do {
            _ = try await repository.dutchStations()
            answer = .working
        } catch {
            answer = APIKeyStatus(for: error)
        }
        guard let answer, !Task.isCancelled, keyChangesAtStart == keyChanges else { return }
        status = answer
    }
    
    /// A key was saved or removed: checks again with the key stored now,
    /// which the store sends whatever it knew about the old one. A check
    /// already running answers for the old key, so it no longer counts, from
    /// before anything is awaited.
    func keyChanged(in repository: StationsRepository) async {
        keyChanges += 1
        await repository.forgetStations(keyChanged: true)
        await refresh(using: repository)
    }
}
