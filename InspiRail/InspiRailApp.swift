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

    /// When the app only hosts the unit tests, it shows an empty scene with an
    /// in-memory store and skips its startup work, so a test run makes no
    /// requests and never opens the stored visits (#15).
    private let isHostingUnitTests = AppConfiguration.isHostingUnitTests()

    init() {
        guard !isHostingUnitTests else { return }
        // Log app configuration on startup
        AppConfiguration.logConfiguration()
    }

    var body: some Scene {
        WindowGroup {
            if isHostingUnitTests {
                Color.clear
                    .modelContainer(for: VisitedStation.self, inMemory: true)
            } else {
                MainTabView()
                    .task {
                        // Track app launch
                        await AnalyticsManager.shared.track(.appLaunched)
                    }
                    // Initialize database with migration support
                    .modelContainer(createModelContainer())
            }
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
            let logger = Logger(subsystem: AppConfiguration.subsystem, category: "database")
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
}

