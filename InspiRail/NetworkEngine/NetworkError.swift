//
//  NetworkError.swift
//  InspiRail
//
//  Created by Andrei Sudarikov on 02/01/2026.
//

import Foundation

/// Why a request to the NS API failed: one case per cause, each with the
/// message a screen shows (#20). A load whose task is cancelled isn't one of
/// them: it passes through as `CancellationError`, and screens ignore it.
nonisolated enum NetworkError: Error, LocalizedError, Equatable {
    /// The request's URL couldn't be built. It is built from constants, so
    /// this doesn't happen.
    case invalidURL
    /// No key in the Keychain, and none from the launch environment.
    case noKey
    /// The Keychain couldn't be read, so a key may be stored but can't be
    /// used right now.
    case keychainUnavailable
    /// NS rejected the key (HTTP 401).
    case keyRejected
    /// NS refused the key (HTTP 403): forbidden, or over its quota.
    case forbidden
    /// NS is throttling requests (HTTP 429).
    case tooManyRequests
    /// NS failed to answer (HTTP 5xx).
    case serviceUnavailable(status: Int)
    /// NS couldn't be reached: no internet, a lost connection, a timeout, a
    /// failed name lookup or connection, a TLS failure, or a request the
    /// system cancelled.
    case offline(URLError.Code)
    /// NS answered with something this version can't use: a body that
    /// doesn't decode, no readable station, or a status it doesn't expect.
    case unreadableData
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noKey:
            return "No NS API key is set. Add one in Settings."
        case .keychainUnavailable:
            return "Your NS API key can't be read right now. Try again in a moment."
        case .keyRejected:
            return "NS didn't accept your API key. Check it in Settings."
        case .forbidden:
            return "NS refused your API key. It may be over its usage limit. Try again later."
        case .tooManyRequests:
            return "NS is getting too many requests. Try again in a minute."
        case .serviceUnavailable:
            return "NS isn't available right now. Try again later."
        case .offline:
            return "Can't reach NS. Check your internet connection."
        case .unreadableData:
            return "NS sent data this version of InspiRail can't read. Try again later."
        }
    }
    
    /// The message a screen shows for `error`, or nil for a cancellation,
    /// which a screen ignores.
    static func message(for error: Error) -> String? {
        if error is CancellationError {
            return nil
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return nil
        }
        if let networkError = error as? NetworkError {
            return networkError.errorDescription
        }
        return "Couldn't load stations. Try again later."
    }
    
    /// What a screen offers for `error` (#21), or nil for a cancellation,
    /// which a screen ignores, so every screen offers the same thing for the
    /// same error.
    ///
    /// Only a key can help with no key, a Keychain that can't be read, or a
    /// key NS rejected (401) or refused (403): the store doesn't send a
    /// refused key again for 15 minutes unless a key is saved (#20), so a
    /// Retry would only repeat the message. Everything else, including the
    /// errors that can't happen, can pass on another try.
    static func recoveryAction(for error: Error) -> RecoveryAction? {
        guard message(for: error) != nil else { return nil }
        switch error as? NetworkError {
        case .noKey, .keychainUnavailable, .keyRejected, .forbidden:
            return .keyEntry
        default:
            return .retry
        }
    }
}

/// What a screen offers when the stations couldn't be loaded (#21).
nonisolated enum RecoveryAction: Equatable, Sendable {
    /// Load again: the store drops its list, joins a download in flight and
    /// keeps a refused key held back.
    case retry
    /// Go to Settings' key section, where a key is entered.
    case keyEntry
}

/// A failed load as a screen shows it: its message and the one action it
/// offers (#21).
nonisolated struct LoadFailure: Equatable, Sendable {
    let message: String
    let action: RecoveryAction
    
    init(message: String, action: RecoveryAction) {
        self.message = message
        self.action = action
    }
    
    /// The failure `error` stands for, or nil for a cancellation.
    init?(_ error: Error) {
        guard let message = NetworkError.message(for: error),
              let action = NetworkError.recoveryAction(for: error) else { return nil }
        self.init(message: message, action: action)
    }
}
