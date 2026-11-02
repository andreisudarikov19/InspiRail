//
//  KeyRefusal.swift
//  InspiRail
//
//  An API key NS refused, remembered by its hash
//

import CryptoKit
import Foundation

/// An API key NS refused, so the app doesn't send it again until it changes
/// (#20). After a 401 that lasts until another key is used. After a 403,
/// which can mean a quota that resets, it also ends after
/// `AppConfiguration.API.forbiddenKeyPause`.
///
/// It keeps only a SHA-256 hash of the key, and neither its descriptions nor
/// its mirror show even that.
nonisolated struct KeyRefusal: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    enum Reason: Sendable {
        /// NS rejected the key (401).
        case rejected
        /// NS refused the key (403): forbidden, or over its quota.
        case forbidden
    }
    
    let reason: Reason
    /// When NS refused the key.
    let since: Date
    /// When the key may be sent again. Nil: not until another key is used.
    let until: Date?
    private let keyHash: [UInt8]
    
    init(_ reason: Reason, key: String, at date: Date) {
        self.reason = reason
        self.since = date
        self.until = reason == .forbidden ? date.addingTimeInterval(AppConfiguration.API.forbiddenKeyPause) : nil
        self.keyHash = Self.hash(of: key)
    }
    
    /// Whether `key` is the refused key, and is still held back at `date`.
    func holds(for key: String, at date: Date) -> Bool {
        guard Self.hash(of: key) == keyHash else {
            return false
        }
        guard let until else {
            return true
        }
        return date < until
    }
    
    /// The error a load held back by this refusal fails with.
    var error: NetworkError {
        switch reason {
        case .rejected:
            return .keyRejected
        case .forbidden:
            return .forbidden
        }
    }
    
    var description: String {
        "KeyRefusal(\(reason), since: \(since), until: \(until.map { "\($0)" } ?? "the key changes"))"
    }
    
    var debugDescription: String {
        description
    }
    
    var customMirror: Mirror {
        Mirror(self, children: ["reason": reason, "since": since, "until": until as Any])
    }
    
    private static func hash(of key: String) -> [UInt8] {
        Array(SHA256.hash(data: Data(key.utf8)))
    }
}
