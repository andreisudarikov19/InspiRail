//
//  APIKeySetupHelper.swift
//  rnsapp
//
//  Helper to diagnose and fix API key configuration issues
//

import Foundation
import OSLog

/// Diagnostic and setup helper for API key configuration
actor APIKeySetupHelper {
    private let logger = Logger(subsystem: "com.rnsapp", category: "setup")
    
    // MARK: - Diagnostic Methods
    
    /// Comprehensive diagnostic check for API key configuration
    func diagnoseAPIKeyIssue() async -> DiagnosticResult {
        logger.info("🔍 Starting API key diagnostics...")
        
        var result = DiagnosticResult()
        
        // Check 1: Secrets.xcconfig file exists
        result.secretsFileExists = checkSecretsFile()
        
        // Check 2: Info.plist configuration
        result.infoPlistConfig = checkInfoPlist()
        
        // Check 3: Keychain status
        result.keychainStatus = await checkKeychain()
        
        // Check 4: Environment (DEBUG only)
        #if DEBUG
        result.environmentVar = checkEnvironment()
        #endif
        
        // Generate fix suggestions
        result.suggestions = generateSuggestions(from: result)
        
        // Log complete report
        logDiagnosticReport(result)
        
        return result
    }
    
    // MARK: - Individual Checks
    
    private func checkSecretsFile() -> Bool {
        // Try to read from the bundle's resource path
        if let bundlePath = Bundle.main.resourcePath {
            let secretsPath = (bundlePath as NSString).appendingPathComponent("Secrets.xcconfig")
            let fileExists = FileManager.default.fileExists(atPath: secretsPath)
            
            if fileExists {
                logger.info("✅ Secrets.xcconfig file found at: \(secretsPath, privacy: .public)")
                return true
            }
        }
        
        logger.warning("⚠️ Secrets.xcconfig file not found in bundle")
        return false
    }
    
    private func checkInfoPlist() -> InfoPlistStatus {
        guard let rawValue = Bundle.main.object(forInfoDictionaryKey: "NS_API_KEY") as? String else {
            logger.error("❌ NS_API_KEY key not found in Info.plist")
            logger.error("   The Info.plist needs this entry:")
            logger.error("   <key>NS_API_KEY</key>")
            logger.error("   <string>$(NS_API_KEY)</string>")
            return .missing
        }
        
        logger.debug("Found NS_API_KEY in Info.plist: '\(rawValue, privacy: .private)'")
        
        // Check for unexpanded variable
        if rawValue == "$(NS_API_KEY)" {
            logger.error("❌ Info.plist variable not expanded!")
            logger.error("   This means Secrets.xcconfig is not being used by Xcode")
            logger.error("   SOLUTION:")
            logger.error("   1. Open your Xcode project")
            logger.error("   2. Select your project in the navigator")
            logger.error("   3. Select your app target")
            logger.error("   4. Go to 'Build Settings' tab")
            logger.error("   5. Search for 'Configuration'")
            logger.error("   6. Under 'Configurations', set Secrets.xcconfig for Debug and Release")
            return .unexpanded
        }
        
        // Check for placeholder
        if rawValue == "YOUR_API_KEY_HERE" || rawValue.isEmpty {
            logger.error("❌ Info.plist contains placeholder value")
            logger.error("   Update Secrets.xcconfig with your actual API key")
            return .placeholder
        }
        
        // Check if it looks like a valid API key
        if rawValue.count < 10 {
            logger.warning("⚠️ API key appears too short: \(rawValue.count) characters")
            return .invalid
        }
        
        logger.info("✅ Info.plist has valid-looking API key (\(rawValue.count) chars)")
        return .valid(key: rawValue)
    }
    
    private func checkKeychain() async -> Bool {
        let hasKey = await KeychainManager.shared.hasAPIKey()
        if hasKey {
            logger.info("✅ API key exists in Keychain")
        } else {
            logger.warning("⚠️ No API key in Keychain (expected on first launch)")
        }
        return hasKey
    }
    
    private func checkEnvironment() -> String? {
        let envKey = ProcessInfo.processInfo.environment["NS_API_KEY"]
        if let key = envKey, !key.isEmpty {
            logger.info("✅ Found NS_API_KEY in environment (\(key.count) chars)")
            return key
        } else {
            logger.debug("ℹ️ No NS_API_KEY in environment (optional)")
            return nil
        }
    }
    
    // MARK: - Automatic Fixes
    
    /// Attempt to automatically fix API key issues
    func attemptAutoFix() async -> FixResult {
        logger.info("🔧 Attempting automatic fix...")
        
        let diagnosis = await diagnoseAPIKeyIssue()
        
        // Try to get key from any available source
        var apiKey: String?
        
        // 1. Try Info.plist
        if case .valid(let key) = diagnosis.infoPlistConfig {
            apiKey = key
            logger.info("Found valid key in Info.plist")
        }
        
        // 2. Try environment (DEBUG only)
        #if DEBUG
        if apiKey == nil, let envKey = diagnosis.environmentVar {
            apiKey = envKey
            logger.info("Found key in environment variable")
        }
        #endif
        
        // 3. If we found a key, save it to Keychain
        if let key = apiKey {
            do {
                try await KeychainManager.shared.saveAPIKey(key)
                logger.info("✅ Successfully saved API key to Keychain!")
                return .success(message: "API key configured successfully")
            } catch {
                logger.error("❌ Failed to save to Keychain: \(error.localizedDescription)")
                return .failed(reason: "Could not save to Keychain: \(error.localizedDescription)")
            }
        }
        
        // No key found anywhere
        logger.error("❌ Could not find API key in any location")
        return .failed(reason: "No API key found. Please configure Secrets.xcconfig and rebuild.")
    }
    
    // MARK: - Manual Key Entry
    
    /// Save an API key manually entered by the user
    func saveManualKey(_ key: String) async throws {
        guard !key.isEmpty else {
            throw NSError(domain: "APIKeySetupHelper", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "API key cannot be empty"])
        }
        
        guard key.count >= 10 else {
            throw NSError(domain: "APIKeySetupHelper", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "API key appears too short"])
        }
        
        // Save to Keychain
        try await KeychainManager.shared.saveAPIKey(key)
        logger.info("✅ Manual API key saved to Keychain")
    }
    
    /// Emergency fallback: Read API key directly from Secrets.xcconfig file
    /// This is a workaround when the build system isn't properly configured
    func readKeyFromSecretsFile() async -> String? {
        // Try to locate Secrets.xcconfig in common locations
        let possiblePaths = [
            // In source directory (development)
            FileManager.default.currentDirectoryPath + "/Secrets.xcconfig",
            // In bundle resource path
            (Bundle.main.resourcePath ?? "") + "/Secrets.xcconfig",
            // Parent directory
            FileManager.default.currentDirectoryPath + "/../Secrets.xcconfig",
        ]
        
        for path in possiblePaths {
            logger.debug("Checking for Secrets.xcconfig at: \(path, privacy: .public)")
            
            guard FileManager.default.fileExists(atPath: path) else {
                continue
            }
            
            do {
                let content = try String(contentsOfFile: path, encoding: .utf8)
                logger.debug("✅ Found Secrets.xcconfig file")
                
                // Parse the file for NS_API_KEY = value
                let lines = content.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    
                    // Skip comments and empty lines
                    if trimmed.isEmpty || trimmed.hasPrefix("//") {
                        continue
                    }
                    
                    // Look for NS_API_KEY = value
                    if trimmed.hasPrefix("NS_API_KEY") {
                        let parts = trimmed.components(separatedBy: "=")
                        if parts.count >= 2 {
                            let key = parts[1...].joined(separator: "=")
                                .trimmingCharacters(in: .whitespaces)
                            
                            // Verify it's not a placeholder
                            if !key.isEmpty && 
                               key != "YOUR_API_KEY_HERE" &&
                               key.count >= 10 {
                                logger.info("✅ Extracted API key from Secrets.xcconfig (\(key.count) chars)")
                                return key
                            }
                        }
                    }
                }
            } catch {
                logger.warning("Failed to read Secrets.xcconfig: \(error.localizedDescription)")
            }
        }
        
        logger.warning("⚠️ Could not read API key from Secrets.xcconfig")
        return nil
    }
    
    /// Ultimate emergency fix: Try everything to get the API key working
    func emergencyFix() async -> FixResult {
        logger.info("🚨 Running emergency fix procedure...")
        
        // Try 1: Normal diagnosis and auto-fix
        let normalFix = await attemptAutoFix()
        if case .success = normalFix {
            return normalFix
        }
        
        // Try 2: Read directly from Secrets.xcconfig file
        logger.info("🔧 Attempting to read directly from Secrets.xcconfig file...")
        if let key = await readKeyFromSecretsFile() {
            do {
                try await KeychainManager.shared.saveAPIKey(key)
                logger.info("✅ Emergency fix successful! API key loaded from Secrets.xcconfig")
                return .success(message: "Emergency fix successful - API key configured")
            } catch {
                return .failed(reason: "Found key but couldn't save to Keychain: \(error.localizedDescription)")
            }
        }
        
        // Try 3: Check environment one more time
        #if DEBUG
        if let envKey = ProcessInfo.processInfo.environment["NS_API_KEY"], !envKey.isEmpty {
            do {
                try await KeychainManager.shared.saveAPIKey(envKey)
                return .success(message: "Configured from environment variable")
            } catch {
                return .failed(reason: "Found key in environment but couldn't save: \(error.localizedDescription)")
            }
        }
        #endif
        
        return .failed(reason: "All emergency procedures failed. Manual setup required.")
    }
    
    // MARK: - Helper Methods
    
    private func generateSuggestions(from result: DiagnosticResult) -> [String] {
        var suggestions: [String] = []
        
        if case .missing = result.infoPlistConfig {
            suggestions.append("Add NS_API_KEY to your Info.plist with value $(NS_API_KEY)")
        }
        
        if case .unexpanded = result.infoPlistConfig {
            suggestions.append("Configure your Xcode project to use Secrets.xcconfig:")
            suggestions.append("  • Project Settings → Info tab → Configurations")
            suggestions.append("  • Set Debug and Release to use Secrets.xcconfig")
            suggestions.append("  • Clean Build Folder (⌘⇧K) and rebuild")
        }
        
        if case .placeholder = result.infoPlistConfig {
            suggestions.append("Edit Secrets.xcconfig and replace YOUR_API_KEY_HERE with your actual NS API key")
            suggestions.append("Get your key from: https://apiportal.ns.nl")
        }
        
        if case .invalid = result.infoPlistConfig {
            suggestions.append("Verify your NS API key is correct at https://apiportal.ns.nl")
        }
        
        if !result.keychainStatus {
            suggestions.append("The app will automatically migrate the key to Keychain on successful configuration")
        }
        
        return suggestions
    }
    
    private func logDiagnosticReport(_ result: DiagnosticResult) {
        logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        logger.info("📊 API Key Diagnostic Report")
        logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        logger.info("")
        logger.info("Secrets.xcconfig file: \(result.secretsFileExists ? "✅ Found" : "❌ Not Found")")
        logger.info("Info.plist config: \(result.infoPlistConfig.description)")
        logger.info("Keychain status: \(result.keychainStatus ? "✅ Has Key" : "⚠️ Empty")")
        
        #if DEBUG
        if let env = result.environmentVar {
            logger.info("Environment var: ✅ Set (\(env.count) chars)")
        } else {
            logger.info("Environment var: ℹ️ Not Set (optional)")
        }
        #endif
        
        logger.info("")
        
        if !result.suggestions.isEmpty {
            logger.info("💡 Suggested Actions:")
            for (index, suggestion) in result.suggestions.enumerated() {
                logger.info("   \(index + 1). \(suggestion)")
            }
        }
        
        logger.info("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    }
}

// MARK: - Models

struct DiagnosticResult {
    var secretsFileExists: Bool = false
    var infoPlistConfig: InfoPlistStatus = .missing
    var keychainStatus: Bool = false
    var environmentVar: String? = nil
    var suggestions: [String] = []
}

enum InfoPlistStatus {
    case missing
    case unexpanded
    case placeholder
    case invalid
    case valid(key: String)
    
    var description: String {
        switch self {
        case .missing:
            return "❌ Key not in Info.plist"
        case .unexpanded:
            return "❌ Variable not expanded (Secrets.xcconfig not configured)"
        case .placeholder:
            return "❌ Contains placeholder value"
        case .invalid:
            return "⚠️ Invalid or too short"
        case .valid(let key):
            return "✅ Valid (\(key.count) chars)"
        }
    }
}

enum FixResult {
    case success(message: String)
    case failed(reason: String)
    case needsManualSetup
}
