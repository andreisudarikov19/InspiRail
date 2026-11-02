//
//  KeyRefusal.swift
//  InspiRail
//
//  An API key NS refused, remembered by its hash
//

import CryptoKit
import Foundation

/// An API key NS refused, so the app doesn't send it again for
/// `AppConfiguration.API.refusedKeyPause`, or until another key is used or a
/// key is saved (#20). Both a 401 and a 403 can pass: a new subscription can
/// take a while to become active, and a quota resets.
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
    /// When the key may be sent again.
    let until: Date
    private let keyHash: [UInt8]
    
    init(_ reason: Reason, key: String, at date: Date) {
        self.reason = reason
        self.since = date
        self.until = date.addingTimeInterval(AppConfiguration.API.refusedKeyPause)
        self.keyHash = Self.hash(of: key)
    }
    
    /// Whether `key` is the refused key.
    func refuses(_ key: String) -> Bool {
        Self.hash(of: key) == keyHash
    }
    
    /// Whether `key` is the refused key, and is still held back at `date`.
    func holds(for key: String, at date: Date) -> Bool {
        refuses(key) && date < until
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
        "KeyRefusal(\(reason), since: \(since), until: \(until))"
    }
    
    var debugDescription: String {
        description
    }
    
    var customMirror: Mirror {
        Mirror(self, children: ["reason": reason, "since": since, "until": until])
    }
    
    private static func hash(of key: String) -> [UInt8] {
        Array(SHA256.hash(data: Data(key.utf8)))
    }
}
