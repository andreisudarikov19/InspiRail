//
//  BackendHealthMonitor.swift
//  InspiRail
//
//  Backend health monitoring and diagnostics
//

import Foundation
import OSLog
import Network
import Darwin

/// Monitors backend health and connectivity
actor BackendHealthMonitor {
    static let shared = BackendHealthMonitor()
    private init() {
        setupNetworkMonitoring()
    }
    
    private let logger = Logger(subsystem: "com.rnsapp", category: "health")
    
    // MARK: - Network Monitoring
    
    private var networkMonitor: NWPathMonitor?
    private var isNetworkAvailable = true
    private var currentConnectionType: NWInterface.InterfaceType?
    
    private func setupNetworkMonitoring() {
        let monitor = NWPathMonitor()
        
        monitor.pathUpdateHandler = { [weak self] path in
            Task { [weak self] in
                await self?.handleNetworkPathUpdate(path)
            }
        }
        
        monitor.start(queue: DispatchQueue(label: "com.rnsapp.network-monitor"))
        self.networkMonitor = monitor
    }
    
    private func handleNetworkPathUpdate(_ path: NWPath) {
        let wasAvailable = isNetworkAvailable
        isNetworkAvailable = path.status == .satisfied
        
        // Detect connection type
        if path.usesInterfaceType(.wifi) {
            currentConnectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            currentConnectionType = .cellular
        } else {
            currentConnectionType = nil
        }
        
        // Log network changes
        if wasAvailable != isNetworkAvailable {
            if isNetworkAvailable {
                logger.info("✅ Network connection restored (\(self.connectionTypeDescription))")
            } else {
                logger.warning("⚠️ Network connection lost")
            }
        }
    }
    
    private var connectionTypeDescription: String {
        switch currentConnectionType {
        case .wifi:
            return "WiFi"
        case .cellular:
            return "Cellular"
        default:
            return "Unknown"
        }
    }
    
    var hasNetworkConnection: Bool {
        isNetworkAvailable
    }
    
    var connectionType: String {
        connectionTypeDescription
    }
    
    // MARK: - Backend Health
    
    enum HealthStatus {
        case healthy
        case degraded
        case unavailable
        case unknown
    }
    
    struct HealthReport {
        let status: HealthStatus
        let responseTime: TimeInterval?
        let lastChecked: Date
        let consecutiveFailures: Int
        let networkAvailable: Bool
        let connectionType: String
        
        var isHealthy: Bool {
            status == .healthy && networkAvailable
        }
    }
    
    private var lastHealthCheck: Date?
    private var lastResponseTime: TimeInterval?
    private var consecutiveFailures = 0
    
    /// Perform a health check on the backend
    func checkHealth() async -> HealthReport {
        let startTime = Date()
        
        guard isNetworkAvailable else {
            return HealthReport(
                status: .unavailable,
                responseTime: nil,
                lastChecked: startTime,
                consecutiveFailures: consecutiveFailures,
                networkAvailable: false,
                connectionType: connectionTypeDescription
            )
        }
        
        do {
            let backend = BackendAPI()
            _ = try await backend.getStations()
            
            let responseTime = Date().timeIntervalSince(startTime)
            lastResponseTime = responseTime
            lastHealthCheck = Date()
            consecutiveFailures = 0
            
            let status: HealthStatus = responseTime < 2.0 ? .healthy : .degraded
            
            logger.info("✅ Health check passed (response time: \(String(format: "%.2f", responseTime))s)")
            
            return HealthReport(
                status: status,
                responseTime: responseTime,
                lastChecked: Date(),
                consecutiveFailures: 0,
                networkAvailable: true,
                connectionType: connectionTypeDescription
            )
            
        } catch {
            consecutiveFailures += 1
            lastHealthCheck = Date()
            
            logger.error("❌ Health check failed: \(error.localizedDescription)")
            
            return HealthReport(
                status: .unavailable,
                responseTime: nil,
                lastChecked: Date(),
                consecutiveFailures: consecutiveFailures,
                networkAvailable: isNetworkAvailable,
                connectionType: connectionTypeDescription
            )
        }
    }
    
    // MARK: - Diagnostics
    
    struct DiagnosticReport {
        let timestamp: Date
        let appVersion: String
        let buildNumber: String
        let deviceModel: String
        let osVersion: String
        let networkStatus: String
        let connectionType: String
        let hasAPIKey: Bool
        let cacheInfo: CacheInfo
        let lastHealthCheck: Date?
        let consecutiveFailures: Int
        
        struct CacheInfo {
            let memoryUsed: Int
            let diskUsed: Int
            let itemCount: Int
        }
        
        var description: String {
            """
            📊 Backend Diagnostics Report
            ========================================
            Timestamp: \(timestamp)
            
            App Information:
            - Version: \(appVersion) (\(buildNumber))
            - Device: \(deviceModel)
            - OS: \(osVersion)
            
            Network Status:
            - Status: \(networkStatus)
            - Type: \(connectionType)
            
            Backend Status:
            - API Key: \(hasAPIKey ? "✅ Present" : "❌ Missing")
            - Last Health Check: \(lastHealthCheck?.formatted() ?? "Never")
            - Consecutive Failures: \(consecutiveFailures)
            
            Cache Information:
            - Memory Used: \(cacheInfo.memoryUsed / 1024 / 1024) MB
            - Disk Used: \(cacheInfo.diskUsed / 1024 / 1024) MB
            - Items Cached: \(cacheInfo.itemCount)
            ========================================
            """
        }
    }
    
    /// Generate a comprehensive diagnostic report
    func generateDiagnosticReport() async -> DiagnosticReport {
        let hasKey = await KeychainManager.shared.hasAPIKey()
        
        // Get cache information
        let cache = URLCache.shared
        let cacheInfo = DiagnosticReport.CacheInfo(
            memoryUsed: cache.currentMemoryUsage,
            diskUsed: cache.currentDiskUsage,
            itemCount: 0 // URLCache doesn't expose this
        )
        
        let report = DiagnosticReport(
            timestamp: Date(),
            appVersion: AppConfiguration.appVersion,
            buildNumber: AppConfiguration.buildNumber,
            deviceModel: deviceModel,
            osVersion: osVersion,
            networkStatus: isNetworkAvailable ? "Connected" : "Disconnected",
            connectionType: connectionTypeDescription,
            hasAPIKey: hasKey,
            cacheInfo: cacheInfo,
            lastHealthCheck: lastHealthCheck,
            consecutiveFailures: consecutiveFailures
        )
        
        logger.info("\(report.description)")
        return report
    }
    
    // MARK: - Device Information
    
    private var deviceModel: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return identifier
    }
    
    private var osVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}
