//
//  BackgroundRefreshManager.swift
//  InspiRail
//
//  Background refresh implementation for station data
//  RECOMMENDED FUTURE ENHANCEMENT
//

import Foundation
import BackgroundTasks
import OSLog

/// Manages background refresh of station data
final class BackgroundRefreshManager {
    static let shared = BackgroundRefreshManager()
    
    private let logger = Logger(subsystem: AppConfiguration.subsystem, category: "background")
    private let repository = StationsRepository()
    
    // Background task identifier - must match Info.plist entry
    static let refreshTaskIdentifier = "\(AppConfiguration.subsystem).refresh-stations"
    
    private init() {}
    
    // MARK: - Registration
    
    /// Register background tasks - call from App.init()
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.refreshTaskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleRefresh(task: task as! BGAppRefreshTask)
        }
        
        logger.info("Background refresh tasks registered")
    }
    
    // MARK: - Scheduling
    
    /// Schedule next background refresh
    func scheduleNextRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
        
        // Refresh every 4 hours (minimum is 15 minutes, but system decides actual timing)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Background refresh scheduled for \(request.earliestBeginDate?.description ?? "soon")")
        } catch {
            logger.error("Failed to schedule background refresh: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Task Handler
    
    private func handleRefresh(task: BGAppRefreshTask) {
        logger.info("Background refresh task started")
        
        // Schedule next refresh
        scheduleNextRefresh()
        
        // Create task to refresh data
        let refreshTask = Task {
            do {
                let startTime = Date()
                
                // Fetch fresh station data
                let response = try await repository.stations(forceRefresh: true)
                
                let duration = Date().timeIntervalSince(startTime)
                logger.info("✅ Background refresh completed successfully")
                logger.info("   Fetched \(response.payload.count) stations in \(String(format: "%.1f", duration))s")
                
                // Track analytics
                await AnalyticsManager.shared.track(.apiRequestSucceeded(endpoint: "background-refresh", duration: duration))
                
                task.setTaskCompleted(success: true)
                
            } catch {
                logger.error("❌ Background refresh failed: \(error.localizedDescription)")
                
                // Track failure
                await AnalyticsManager.shared.track(.apiRequestFailed(endpoint: "background-refresh", error: error.localizedDescription))
                
                task.setTaskCompleted(success: false)
            }
        }
        
        // Handle task expiration
        task.expirationHandler = {
            self.logger.warning("⚠️ Background refresh expired - cancelling")
            refreshTask.cancel()
        }
    }
}

/*
 
 IMPLEMENTATION GUIDE:
 
 1. Add to Info.plist:
 
    <key>BGTaskSchedulerPermittedIdentifiers</key>
    <array>
        <string>annisu.inspirail.refresh-stations</string>
    </array>
 
 2. In InspiRailApp.swift, add to init():
 
    BackgroundRefreshManager.shared.registerBackgroundTasks()
 
 3. In InspiRailApp.swift, add to .task modifier:
 
    BackgroundRefreshManager.shared.scheduleNextRefresh()
 
 4. Testing in Xcode console:
 
    e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"annisu.inspirail.refresh-stations"]
 
 Note: The analytics events used are:
    - .apiRequestSucceeded(endpoint: "background-refresh", duration: duration)
    - .apiRequestFailed(endpoint: "background-refresh", error: error.localizedDescription)
 
 */
