//
//  AnalyticsManager.swift
//  rnsapp
//
//  Privacy-focused analytics and error tracking
//

import Foundation
import OSLog
import Darwin

/// Privacy-focused analytics manager
/// Note: This is a foundation for future analytics integration
/// Currently logs to OSLog for debugging, can be extended with third-party SDKs
actor AnalyticsManager {
    static let shared = AnalyticsManager()
    private init() {}
    
    private let logger = Logger(subsystem: "com.rnsapp", category: "analytics")
    
    // MARK: - Events
    
    enum Event {
        case appLaunched
        case appBackgrounded
        case appForegrounded
        
        // Station Events
        case stationViewed(code: String)
        case stationSearched(query: String)
        case stationMarkedVisited(code: String)
        case stationFavorited(code: String)
        
        // Discovery
        case discoveryRandomized
        case discoveryShared
        
        // Network
        case apiRequestSucceeded(endpoint: String, duration: TimeInterval)
        case apiRequestFailed(endpoint: String, error: String)
        case cacheHit(endpoint: String)
        case cacheMiss(endpoint: String)
        
        // Errors
        case errorOccurred(domain: String, code: Int, description: String)
        
        var name: String {
            switch self {
            case .appLaunched: return "app_launched"
            case .appBackgrounded: return "app_backgrounded"
            case .appForegrounded: return "app_foregrounded"
            case .stationViewed: return "station_viewed"
            case .stationSearched: return "station_searched"
            case .stationMarkedVisited: return "station_marked_visited"
            case .stationFavorited: return "station_favorited"
            case .discoveryRandomized: return "discovery_randomized"
            case .discoveryShared: return "discovery_shared"
            case .apiRequestSucceeded: return "api_request_succeeded"
            case .apiRequestFailed: return "api_request_failed"
            case .cacheHit: return "cache_hit"
            case .cacheMiss: return "cache_miss"
            case .errorOccurred: return "error_occurred"
            }
        }
        
        var parameters: [String: Any] {
            switch self {
            case .stationViewed(let code):
                return ["station_code": code]
            case .stationSearched(let query):
                // Privacy: Don't log the actual query, just that a search happened
                return ["query_length": query.count]
            case .stationMarkedVisited(let code):
                return ["station_code": code]
            case .stationFavorited(let code):
                return ["station_code": code]
            case .apiRequestSucceeded(let endpoint, let duration):
                return ["endpoint": endpoint, "duration_ms": Int(duration * 1000)]
            case .apiRequestFailed(let endpoint, let error):
                return ["endpoint": endpoint, "error": error]
            case .cacheHit(let endpoint):
                return ["endpoint": endpoint]
            case .cacheMiss(let endpoint):
                return ["endpoint": endpoint]
            case .errorOccurred(let domain, let code, let description):
                return ["domain": domain, "code": code, "description": description]
            default:
                return [:]
            }
        }
    }
    
    // MARK: - Tracking Methods
    
    /// Track an analytics event
    func track(_ event: Event) async {
        guard AppConfiguration.Features.enableAnalytics else {
            return
        }
        
        // Privacy: Only log non-sensitive information
        logger.info("📊 Event: \(event.name, privacy: .public)")
        
        if !event.parameters.isEmpty {
            logger.debug("   Parameters: \(event.parameters, privacy: .private)")
        }
        
        // TODO: Integrate with your analytics provider
        // Examples:
        // - Apple Analytics (StoreKit)
        // - Firebase Analytics
        // - Custom backend
        // - TelemetryDeck (privacy-focused)
    }
    
    /// Track a screen view
    func trackScreen(_ name: String) async {
        guard AppConfiguration.Features.enableAnalytics else {
            return
        }
        
        logger.info("📱 Screen: \(name, privacy: .public)")
        
        // TODO: Integrate with analytics provider
    }
    
    /// Track a timed event
    func time<T>(_ operation: String, block: () async throws -> T) async rethrows -> T {
        let start = Date()
        defer {
            let duration = Date().timeIntervalSince(start)
            let durationMs = Int(duration * 1000)
            logger.debug("⏱️ \(operation) took \(durationMs)ms")
        }
        return try await block()
    }
    
    // MARK: - User Properties
    
    /// Set user properties for analytics
    func setUserProperty(_ value: String, forName name: String) async {
        guard AppConfiguration.Features.enableAnalytics else {
            return
        }
        
        logger.debug("👤 User property: \(name, privacy: .public) = \(value, privacy: .private)")
        
        // TODO: Integrate with analytics provider
    }
}

// MARK: - Performance Metrics

extension AnalyticsManager {
    /// Track app performance metrics
    struct PerformanceMetrics {
        let memoryUsage: UInt64
        let cpuUsage: Double
        let networkBytesReceived: UInt64
        let networkBytesSent: UInt64
    }
    
    func trackPerformanceMetrics() async {
        guard AppConfiguration.Features.enableDetailedLogging else {
            return
        }
        
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let usedMemory = taskInfo.resident_size / 1024 / 1024 // MB
            logger.debug("💾 Memory usage: \(usedMemory) MB")
        }
    }
}
