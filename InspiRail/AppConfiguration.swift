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
    /// Reverse-DNS prefix for the app's own identifiers: the logger subsystem,
    /// dispatch queue labels and background task ids. The bundle identifier
    /// keeps its original name, `annisu.rnsapp`.
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
        static let timeout: TimeInterval = 30
        static let resourceTimeout: TimeInterval = 60
        
        // Rate limiting
        static let maxRequestsPerMinute = 30
        static let maxRetries = 3
        
        // Cache settings
        static let cacheLifetime: TimeInterval = 3600 // 1 hour
        static let memoryCacheSize = 10 * 1024 * 1024 // 10 MB
        static let diskCacheSize = 50 * 1024 * 1024   // 50 MB
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
        
        static var enableCrashReporting: Bool {
            Environment.current == .production
        }
        
        static var enableAnalytics: Bool {
            Environment.current == .production
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
