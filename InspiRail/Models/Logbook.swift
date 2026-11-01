//
//  Logbook.swift
//  InspiRail
//
//  The logbook as every window sees it: open, or failed to open, with the two
//  ways out that the error screen offers (#17).
//

import Foundation
import Observation
import OSLog
import SwiftData

/// The app creates one, so every window shares one container.
@Observable
final class Logbook {
    enum Status {
        case open(ModelContainer)
        /// The store couldn't be opened. The reason is in the log.
        /// `movedAside` is true once Start a New Logbook has moved the old
        /// store into a backup folder and the new one couldn't be opened.
        case failed(movedAside: Bool)
    }
    
    private(set) var status: Status
    
    private let store: LogbookStore
    
    private static let logger = Logger(subsystem: AppConfiguration.subsystem, category: "database")
    
    init(store: LogbookStore) {
        self.store = store
        status = Self.open(store, movedAside: false)
    }
    
    /// Opens the store again after a failure. Does nothing while it is open.
    /// Try Again calls it, and so does each window when it becomes active.
    func tryAgain() {
        guard case .failed(let movedAside) = status else { return }
        status = Self.open(store, movedAside: movedAside)
    }
    
    /// Moves the store that couldn't be opened into a dated backup folder,
    /// and opens an empty one. Does nothing while the logbook is open, so a
    /// confirmation in a second window can't move the store in use.
    func startNew(date: Date = .now) {
        guard case .failed(var movedAside) = status else { return }
        do {
            if let backup = try store.moveAside(date: date) {
                Self.logger.notice("Moved the logbook aside to Logbook Backups/\(backup.lastPathComponent, privacy: .public)")
                movedAside = true
            }
        } catch {
            Self.logger.error("Couldn't move the logbook aside: \(String(describing: error))")
            status = .failed(movedAside: movedAside)
            return
        }
        status = Self.open(store, movedAside: movedAside)
    }
    
    private static func open(_ store: LogbookStore, movedAside: Bool) -> Status {
        do {
            return .open(try store.open())
        } catch {
            logger.error("Couldn't open the logbook: \(String(describing: error))")
            return .failed(movedAside: movedAside)
        }
    }
}
