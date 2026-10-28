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
    private static let logger = Logger(subsystem: "com.rnsapp", category: "config")
    
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
        Bundle.main.bundleIdentifier ?? "com.rnsapp"
    }
    
    static var userAgent: String {
        "rnsapp/\(appVersion) (iOS; Build \(buildNumber))"
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
