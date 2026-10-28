//
//  NetworkMonitor.swift
//  rnsapp
//
//  Advanced network monitoring using Apple's Network framework
//  RECOMMENDED FUTURE ENHANCEMENT
//

import Foundation
import Network
import OSLog

/// Monitors network connectivity and provides real-time status updates
@Observable
final class NetworkMonitor {
    private(set) var isConnected = true
    private(set) var connectionType: NWInterface.InterfaceType?
    private(set) var isExpensive = false
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.rnsapp.networkmonitor")
    private let logger = Logger(subsystem: "com.rnsapp", category: "network")
    
    init() {
        startMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    private func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            let wasConnected = self.isConnected
            let newIsConnected = path.status == .satisfied
            
            // Update state on main actor
            Task { @MainActor in
                self.isConnected = newIsConnected
                self.isExpensive = path.isExpensive
                self.connectionType = self.getCurrentInterfaceType(path)
                
                // Log significant changes
                if wasConnected != newIsConnected {
                    if newIsConnected {
                        self.logger.info("📶 Network connection restored (\(self.connectionType?.description ?? "unknown"))")
                    } else {
                        self.logger.warning("📵 Network connection lost")
                    }
                }
            }
        }
        
        monitor.start(queue: queue)
        logger.debug("Network monitoring started")
    }
    
    private func stopMonitoring() {
        monitor.cancel()
        logger.debug("Network monitoring stopped")
    }
    
    private func getCurrentInterfaceType(_ path: NWPath) -> NWInterface.InterfaceType? {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        }
        return nil
    }
}

extension NWInterface.InterfaceType {
    var description: String {
        switch self {
        case .wifi: return "Wi-Fi"
        case .cellular: return "Cellular"
        case .wiredEthernet: return "Ethernet"
        case .loopback: return "Loopback"
        case .other: return "Other"
        @unknown default: return "Unknown"
        }
    }
}

/*
 
 IMPLEMENTATION GUIDE:
 
 1. In your view, add the monitor:
 
    @State private var networkMonitor = NetworkMonitor()
 
 2. Use the monitor state:
 
    var body: some View {
        VStack {
            if !networkMonitor.isConnected {
                NetworkStatusBanner(
                    type: networkMonitor.connectionType,
                    isExpensive: networkMonitor.isExpensive
                )
            }
            // Your content...
        }
    }
 
 3. Optional: Add a banner view in your DiscoveryView or main view
 
 */
