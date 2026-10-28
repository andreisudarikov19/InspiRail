//
//  InspiRailApp.swift
//  InspiRail
//
//  Created by Andrei Sudarikov on 02/01/2026.
//

import SwiftUI
import SwiftData
import OSLog

@main
struct InspiRailApp: App {
    
    init() {
        // Log app configuration on startup
        AppConfiguration.logConfiguration()
    }
    
    var body: some Scene {
        WindowGroup {
            MainTabView()
                .task {
                    // Track app launch
                    await AnalyticsManager.shared.track(.appLaunched)
                    
                    #if DEBUG
                    // Verify backend connectivity on debug builds
                    await verifyBackendConnection()
                    #endif
                }
                // Initialize database with migration support
                .modelContainer(createModelContainer())
        }
    }
    
    /// Create model container with proper error handling and migration support
    private func createModelContainer() -> ModelContainer {
        let schema = Schema([VisitedStation.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            return container
        } catch {
            let logger = Logger(subsystem: "com.rnsapp", category: "database")
            logger.error("❌ Failed to create ModelContainer: \(error.localizedDescription)")
            logger.error("   Error type: \(type(of: error))")
            
            // SwiftData wraps CoreData migration errors
            // Check the underlying error or just try to reset on any failure
            let shouldAttemptReset = true
            
            // Check if it's specifically a migration error by looking at the error description
            let isMigrationError = error.localizedDescription.contains("migration") ||
                                 error.localizedDescription.contains("134110") ||
                                 (error as NSError).userInfo.description.contains("migration")
            
            if shouldAttemptReset {
                logger.warning("🔄 Database initialization failed")
                logger.warning("   This may be due to a schema migration issue")
                logger.warning("   Attempting to reset database...")
                
                // Get all possible database file locations
                let fileManager = FileManager.default
                if let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                    logger.info("   Database location: \(appSupport.path, privacy: .public)")
                    
                    let storeURL = appSupport.appendingPathComponent("default.store")
                    let storeWAL = appSupport.appendingPathComponent("default.store-wal")
                    let storeSHM = appSupport.appendingPathComponent("default.store-shm")
                    
                    var deletedCount = 0
                    
                    // Delete all database files
                    for url in [storeURL, storeWAL, storeSHM] {
                        if fileManager.fileExists(atPath: url.path) {
                            do {
                                try fileManager.removeItem(at: url)
                                logger.info("🗑️ Deleted: \(url.lastPathComponent)")
                                deletedCount += 1
                            } catch {
                                logger.warning("⚠️ Could not delete \(url.lastPathComponent): \(error.localizedDescription)")
                            }
                        } else {
                            logger.debug("   File doesn't exist: \(url.lastPathComponent)")
                        }
                    }
                    
                    if deletedCount > 0 {
                        logger.info("   Deleted \(deletedCount) database file(s)")
                    } else {
                        logger.warning("   No database files found to delete")
                    }
                    
                    // Try again with fresh store
                    do {
                        let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
                        logger.info("✅ Successfully created new ModelContainer after reset")
                        if isMigrationError {
                            logger.info("   Note: Previous visited stations data was lost due to schema change")
                        }
                        return container
                    } catch {
                        logger.error("❌ Failed even after reset: \(error.localizedDescription)")
                    }
                }
            }
            
            // Last resort: use in-memory storage
            logger.warning("⚠️ Falling back to in-memory database (data won't persist)")
            let memoryConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            return try! ModelContainer(for: schema, configurations: [memoryConfig])
        }
    }
    
    #if DEBUG
    /// Verify backend connection and security setup in debug builds
    func verifyBackendConnection() async {
        let logger = Logger(subsystem: "com.rnsapp", category: "startup")
        logger.info("🔍 Verifying backend connection...")
        
        // DIAGNOSTIC: Check what's in Info.plist
        if let plistValue = Bundle.main.object(forInfoDictionaryKey: "NS_API_KEY") as? String {
            logger.info("📋 Info.plist NS_API_KEY length: \(plistValue.count) chars")
            logger.info("📋 Info.plist value preview: \(plistValue.prefix(8))...")
            if plistValue == "$(NS_API_KEY)" {
                logger.error("❌ PROBLEM: Info.plist variable NOT EXPANDED!")
            }
        } else {
            logger.error("❌ PROBLEM: NS_API_KEY not found in Info.plist at all!")
        }
        
        // Step 1: Run diagnostics
        let helper = APIKeySetupHelper()
        let diagnosis = await helper.diagnoseAPIKeyIssue()
        
        // Step 2: Attempt auto-fix if needed
        if !diagnosis.keychainStatus {
            logger.info("🔧 Attempting to auto-configure API key...")
            
            // First try the emergency fix which includes reading from Secrets.xcconfig
            let fixResult = await helper.emergencyFix()
            
            switch fixResult {
            case .success(let message):
                logger.info("✅ \(message)")
            case .failed(let reason):
                logger.error("❌ Auto-fix failed: \(reason)")
                logger.error("")
                logger.error("📖 MANUAL SETUP REQUIRED:")
                logger.error("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                
                if case .unexpanded = diagnosis.infoPlistConfig {
                    logger.error("PROBLEM: Xcode is not using Secrets.xcconfig file")
                    logger.error("")
                    logger.error("SOLUTION - Configure Xcode project:")
                    logger.error("1. Open project in Xcode")
                    logger.error("2. Click on project name at the top of Navigator")
                    logger.error("3. Under 'Info' tab → 'Configurations'")
                    logger.error("4. For both Debug and Release:")
                    logger.error("   Set to 'Secrets' (the xcconfig file)")
                    logger.error("5. Clean Build Folder: Product → Clean Build Folder (⌘⇧K)")
                    logger.error("6. Rebuild: Product → Build (⌘B)")
                } else if case .missing = diagnosis.infoPlistConfig {
                    logger.error("PROBLEM: Info.plist missing NS_API_KEY entry")
                    logger.error("")
                    logger.error("SOLUTION - Add to Info.plist:")
                    logger.error("1. Open Info.plist")
                    logger.error("2. Add new row:")
                    logger.error("   Key: NS_API_KEY")
                    logger.error("   Type: String")
                    logger.error("   Value: $(NS_API_KEY)")
                    logger.error("3. Clean and rebuild")
                }
                
                logger.error("")
                logger.error("After fixing, verify Secrets.xcconfig contains:")
                logger.error("NS_API_KEY = your_actual_api_key_from_ns_portal")
                logger.error("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
                return
            case .needsManualSetup:
                logger.warning("⚠️ Manual setup required")
                return
            }
        }
        
        // Step 3: Test actual API connection
        do {
            let backend = BackendAPI()
            let response = try await backend.getStations()
            
            logger.info("✅ Backend connection successful!")
            logger.info("   Found \(response.payload.count) stations")
            
            if let first = response.payload.first {
                logger.info("   First station: \(first.names.long)")
            }
            
        } catch NetworkError.unauthorized {
            logger.error("❌ Authentication failed!")
            logger.error("   Your API key may be invalid or expired")
            logger.error("   Get a new key from: https://apiportal.ns.nl")
            logger.error("   Then update Secrets.xcconfig and rebuild")
        } catch {
            logger.error("❌ Backend connection failed: \(error.localizedDescription)")
        }
    }
    #endif
}

