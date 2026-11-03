//
//  AppConfiguration.swift
//  InspiRail
//
//  Centralized app configuration management
//

import Foundation
import OSLog

/// Centralized configuration for the app
enum AppConfiguration {
    /// Reverse-DNS prefix for the app's own identifiers: the logger subsystem
    /// and dispatch queue labels. The bundle identifier keeps its original
    /// name, `annisu.rnsapp`.
    nonisolated static let subsystem = "annisu.inspirail"
    
    private static let logger = Logger(subsystem: subsystem, category: "config")
    
    // MARK: - Environment
    
    enum Environment {
        case development
        case production
        
        static var current: Environment {
            #if DEBUG
            return .development
            #else
            return .production
            #endif
        }
    }
    
    // MARK: - API Configuration
    
    enum API {
        static let baseURL = "https://gateway.apiportal.ns.nl"
        /// The longest a request waits for the first or the next bytes of
        /// the reply. A connection that sends nothing for this long, several
        /// times the round trips of a slow mobile network, has stalled, and
        /// waiting longer only keeps the loading screen up (#21).
        nonisolated static let timeout: TimeInterval = 15
        /// The longest one request may take in all, even while the reply is
        /// still arriving. A timeout isn't retried, and a Retry starts again
        /// from zero, so this leaves a slow link room to finish the station
        /// list, the app's only request. The size of NS's reply hasn't been
        /// measured; the review stub's list, 600 stations in NS's shape, is
        /// about 380 KB, about 15 s on EDGE uncompressed. A stalled
        /// connection is caught sooner, by `timeout` (#21).
        nonisolated static let resourceTimeout: TimeInterval = 60
        
        // Retries (#20)
        /// The most times one load sends its request.
        nonisolated static let maxAttempts = 3
        /// The longest wait between attempts. When NS asks for longer, the
        /// load fails at once instead of keeping the screen loading.
        nonisolated static let longestRetryWait: TimeInterval = 10
        /// How long a key NS refused (401 or 403) is held back before it is
        /// sent again: a 401 can pass, for example while a new subscription
        /// becomes active, and a 403 can mean a quota that resets. Another
        /// key, or any key saved in Settings, is sent at once.
        nonisolated static let refusedKeyPause: TimeInterval = 15 * 60
        
        // Cache settings
        static let cacheLifetime: TimeInterval = 3600 // 1 hour
    }
    
    // MARK: - App Info
    
    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }
    
    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "annisu.rnsapp"
    }
    
    static var userAgent: String {
        "InspiRail/\(appVersion) (iOS; Build \(buildNumber))"
    }
    
    // MARK: - Test host
    
    /// Set to "1" by `InspiRail.xctestplan` in the environment of the process
    /// that hosts the unit tests. The app a UI test launches doesn't get it.
    nonisolated static let unitTestHostVariable = "INSPIRAIL_UNIT_TEST_HOST"
    
    /// Whether this process only hosts the unit tests, so the app should skip
    /// its startup work, its network requests and the stored visits.
    nonisolated static func isHostingUnitTests(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment[unitTestHostVariable] == "1"
    }
    
    // MARK: - Feature Flags
    
    enum Features {
        static var enableDetailedLogging: Bool {
            Environment.current == .development
        }
        
        static var enableNetworkLogging: Bool {
            Environment.current == .development
        }
    }
    
    // MARK: - Logging
    
    static func logConfiguration() {
        logger.info("🚀 App Configuration:")
        logger.info("  - Environment: \(Environment.current == .development ? "Development" : "Production")")
        logger.info("  - Version: \(appVersion) (\(buildNumber))")
        logger.info("  - Bundle ID: \(bundleIdentifier)")
        logger.info("  - API Base: \(API.baseURL)")
    }
}
