//
//  BackendHealthMonitor.swift
//  InspiRail
//
//  Backend health monitoring
//

import Foundation
import OSLog
import Network

/// Monitors backend health and connectivity
actor BackendHealthMonitor {
    static let shared = BackendHealthMonitor()
    private init() {
        setupNetworkMonitoring()
    }
    
    private let logger = Logger(subsystem: AppConfiguration.subsystem, category: "health")
    
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
        
        monitor.start(queue: DispatchQueue(label: "\(AppConfiguration.subsystem).network-monitor"))
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
    
    // MARK: - Backend Health
    
    enum HealthStatus {
        case healthy
        case degraded
        case unavailable
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
    
    private var consecutiveFailures = 0
    
    /// Perform a health check on the backend, through the app's one API (#18)
    func checkHealth(using backend: BackendAPI) async -> HealthReport {
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
            _ = try await backend.getStations()
            
            let responseTime = Date().timeIntervalSince(startTime)
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
}
