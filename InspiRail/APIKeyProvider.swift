//
//  APIKeyProvider.swift
//  InspiRail
//
//  Finds the NS API key to send with a request
//

import Foundation
import OSLog

/// Finds the NS API key to send with a request.
///
/// The key lives in the Keychain. In Debug builds a non-empty `NS_API_KEY`
/// environment variable wins over it and is saved to the Keychain, so a
/// single launch with the variable also primes later launches.
nonisolated struct APIKeyProvider: Sendable {
    private let keychain: KeychainManager
    private let environmentKey: String?
    private let logger = Logger(subsystem: AppConfiguration.subsystem, category: "apikey")

    init(keychain: KeychainManager, environment: [String: String], allowsEnvironmentOverride: Bool) {
        self.keychain = keychain
        let value = environment["NS_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.environmentKey = allowsEnvironmentOverride && !value.isEmpty ? value : nil
    }

    /// Whether the `NS_API_KEY` environment variable supplies the key, so that a key
    /// saved or removed in Settings is overridden by it.
    var usesEnvironmentKey: Bool { environmentKey != nil }

    /// The key to send with a request. Throws `NetworkError.unauthorized` when there is none.
    func currentKey() async throws -> String {
        let storedKey: String?
        do {
            storedKey = try await keychain.getAPIKey()
        } catch KeychainError.notFound {
            storedKey = nil
        } catch {
            logger.warning("Couldn't read the API key from the Keychain: \(error.localizedDescription)")
            storedKey = nil
        }

        if let environmentKey {
            logger.debug("Using the API key from the NS_API_KEY environment variable")
            if storedKey != environmentKey {
                do {
                    try await keychain.saveAPIKey(environmentKey)
                } catch {
                    logger.error("Couldn't save the API key to the Keychain: \(error.localizedDescription)")
                }
            }
            return environmentKey
        }

        if let storedKey {
            logger.debug("Using the API key from the Keychain")
            return storedKey
        }

        logger.error("No API key: enter one in Settings")
        throw NetworkError.unauthorized
    }
}
