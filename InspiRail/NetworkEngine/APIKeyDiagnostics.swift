//
//  APIKeyDiagnostics.swift
//  InspiRail
//
//  Diagnostic tool for troubleshooting API key configuration
//

import Foundation
import OSLog

/// Diagnostic utility for API key configuration issues
actor APIKeyDiagnostics {
    private let logger = Logger(subsystem: AppConfiguration.subsystem, category: "diagnostics")
    
    /// Run a comprehensive diagnostic check
    func runDiagnostics() async -> DiagnosticReport {
        logger.info("🔍 Running API key diagnostics...")
        
        var report = await DiagnosticReport()
        
        // Check 1: Keychain
        report.keychainStatus = await checkKeychain()
        
        // Check 2: Info.plist
        report.infoPlistStatus = checkInfoPlist()
        
        // Check 3: Environment variables (DEBUG only)
        #if DEBUG
        report.environmentStatus = checkEnvironment()
        #endif
        
        // Check 4: Network connectivity
        report.networkStatus = await checkNetworkConnectivity()
        
        // Check 5: API endpoint accessibility
        report.apiEndpointStatus = await checkAPIEndpoint()
        
        // Generate recommendations
        report.recommendations = generateRecommendations(from: report)
        
        // Log summary
        logReport(report)
        
        return report
    }
    
    // MARK: - Individual Checks
    
    private func checkKeychain() async -> CheckStatus {
        do {
            let key = try await KeychainManager.shared.getAPIKey()
            
            // Validate key format (basic check)
            if key.isEmpty {
                return .failed(reason: "API key in Keychain is empty")
            }
            
            if key.count < 10 {
                return .failed(reason: "API key appears too short (possibly invalid)")
            }
            
            // Check for common placeholders
            let placeholders = ["YOUR_API_KEY_HERE", "$(NS_API_KEY)", "$(API_KEY)", "PLACEHOLDER"]
            if placeholders.contains(where: { key.contains($0) }) {
                return .failed(reason: "API key contains placeholder text")
            }
            
            return .passed(message: "Valid API key found in Keychain (\(key.count) characters)")
            
        } catch KeychainError.notFound {
            return .warning(message: "No API key in Keychain (expected on first launch)")
        } catch {
            return .failed(reason: "Keychain access error: \(error.localizedDescription)")
        }
    }
    
    private func checkInfoPlist() -> CheckStatus {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "NS_API_KEY") as? String else {
            return .failed(reason: "NS_API_KEY not found in Info.plist")
        }
        
        if key.isEmpty {
            return .failed(reason: "NS_API_KEY in Info.plist is empty")
        }
        
        // Check for unexpanded variables
        if key.hasPrefix("$(") && key.hasSuffix(")") {
            return .failed(reason: "Info.plist contains unexpanded variable: \(key)")
        }
        
        // Check for placeholders
        if key == "YOUR_API_KEY_HERE" {
            return .failed(reason: "Info.plist contains placeholder value")
        }
        
        if key.count < 10 {
            return .warning(message: "API key in Info.plist appears too short")
        }
        
        return .passed(message: "Valid API key found in Info.plist (\(key.count) characters)")
    }
    
    private func checkEnvironment() -> CheckStatus {
        guard let key = ProcessInfo.processInfo.environment["NS_API_KEY"] else {
            return .warning(message: "NS_API_KEY not found in environment variables (optional)")
        }
        
        if key.isEmpty {
            return .warning(message: "NS_API_KEY environment variable is empty")
        }
        
        return .passed(message: "API key found in environment (\(key.count) characters)")
    }
    
    private func checkNetworkConnectivity() async -> CheckStatus {
        // Simple connectivity check using Apple's known-good URL
        guard let url = URL(string: "https://www.apple.com") else {
            return .failed(reason: "Could not create test URL")
        }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode) {
                return .passed(message: "Internet connectivity verified")
            } else {
                return .warning(message: "Unexpected response from connectivity test")
            }
        } catch {
            return .failed(reason: "No internet connectivity: \(error.localizedDescription)")
        }
    }
    
    private func checkAPIEndpoint() async -> CheckStatus {
        // Try to reach the NS API endpoint
        let baseURL = AppConfiguration.API.baseURL
        guard let url = URL(string: baseURL) else {
            return .failed(reason: "Invalid API base URL: \(baseURL)")
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 10
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                switch httpResponse.statusCode {
                case 200...299:
                    return .passed(message: "API endpoint is reachable")
                case 401, 403:
                    return .warning(message: "API endpoint reachable but authentication may be required")
                case 404:
                    return .failed(reason: "API endpoint not found (404)")
                case 500...599:
                    return .warning(message: "API server error (\(httpResponse.statusCode))")
                default:
                    return .warning(message: "Unexpected status code: \(httpResponse.statusCode)")
                }
            }
            
            return .warning(message: "Could not verify API endpoint status")
            
        } catch {
            return .failed(reason: "Cannot reach API endpoint: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Recommendations
    
    private func generateRecommendations(from report: DiagnosticReport) -> [String] {
        var recommendations: [String] = []
        
        // Keychain recommendations
        if case .failed = report.keychainStatus {
            if case .passed = report.infoPlistStatus {
                recommendations.append("Try deleting and reinstalling the app to trigger key migration from Info.plist to Keychain")
            } else {
                recommendations.append("Configure your API key in Secrets.xcconfig and rebuild the app")
            }
        }
        
        // Info.plist recommendations
        if case .failed(let reason) = report.infoPlistStatus {
            if reason.contains("unexpanded") {
                recommendations.append("Ensure Secrets.xcconfig is properly configured with NS_API_KEY variable")
                recommendations.append("Clean build folder (⌘⇧K) and rebuild")
            }
            if reason.contains("not found") {
                recommendations.append("Add NS_API_KEY to your Info.plist with value $(NS_API_KEY)")
                recommendations.append("Ensure Secrets.xcconfig is included in your project configuration")
            }
        }
        
        // Network recommendations
        if case .failed = report.networkStatus {
            recommendations.append("Check your internet connection")
            recommendations.append("Try connecting to WiFi or cellular data")
        }
        
        // API endpoint recommendations
        if case .failed = report.apiEndpointStatus {
            recommendations.append("Verify the NS API base URL is correct: \(AppConfiguration.API.baseURL)")
            recommendations.append("Check if NS API is experiencing downtime: https://status.ns.nl")
        }
        
        // If everything looks good
        if case .passed = report.keychainStatus,
           case .passed = report.networkStatus {
            recommendations.append("Configuration appears correct. If issues persist, try clearing the Keychain:")
            recommendations.append("  1. Delete and reinstall the app")
            recommendations.append("  2. Rebuild with a clean build folder")
        }
        
        return recommendations
    }
    
    // MARK: - Logging
    
    private func logReport(_ report: DiagnosticReport) {
        logger.info("📊 Diagnostic Report:")
        logger.info("  Keychain: \(report.keychainStatus.description)")
        logger.info("  Info.plist: \(report.infoPlistStatus.description)")
        
        #if DEBUG
        logger.info("  Environment: \(report.environmentStatus?.description ?? "N/A")")
        #endif
        
        logger.info("  Network: \(report.networkStatus.description)")
        logger.info("  API Endpoint: \(report.apiEndpointStatus.description)")
        
        if !report.recommendations.isEmpty {
            logger.info("💡 Recommendations:")
            for (index, rec) in report.recommendations.enumerated() {
                logger.info("  \(index + 1). \(rec)")
            }
        }
    }
}

// MARK: - Models

struct DiagnosticReport {
    var keychainStatus: CheckStatus = .unknown
    var infoPlistStatus: CheckStatus = .unknown
    var environmentStatus: CheckStatus? = nil
    var networkStatus: CheckStatus = .unknown
    var apiEndpointStatus: CheckStatus = .unknown
    var recommendations: [String] = []
}

enum CheckStatus {
    case passed(message: String)
    case warning(message: String)
    case failed(reason: String)
    case unknown
    
    var description: String {
        switch self {
        case .passed(let msg):
            return "✅ \(msg)"
        case .warning(let msg):
            return "⚠️ \(msg)"
        case .failed(let reason):
            return "❌ \(reason)"
        case .unknown:
            return "❓ Not checked"
        }
    }
    
    var isHealthy: Bool {
        if case .passed = self { return true }
        return false
    }
}
