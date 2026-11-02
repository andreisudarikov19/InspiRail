//
//  NetworkError.swift
//  InspiRail
//
//  Created by Andrei Sudarikov on 02/01/2026.
//

import Foundation

/// Why a request to the NS API failed: one case per cause, each with the
/// message a screen shows (#20). A cancelled request isn't one of them: it
/// passes through as `CancellationError`, and screens ignore it.
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
    /// failed name lookup or connection, or a TLS failure.
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
    
    /// Whether the error is about the API key. Onboarding offers Open
    /// Settings for these, as it did for the one key error before #20.
    var concernsTheKey: Bool {
        switch self {
        case .noKey, .keychainUnavailable, .keyRejected, .forbidden:
            return true
        default:
            return false
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
}
