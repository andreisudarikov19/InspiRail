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
        case failed(any Error)
    }

    private(set) var status: Status

    private let store: LogbookStore

    private static let logger = Logger(subsystem: AppConfiguration.subsystem, category: "database")

    init(store: LogbookStore) {
        self.store = store
        status = Self.open(store)
    }

    /// Opens the store again after a failure. Does nothing while it is open.
    func tryAgain() {
        guard case .failed = status else { return }
        status = Self.open(store)
    }

    /// Moves the store that couldn't be opened into a dated backup folder,
    /// and opens an empty one. Does nothing while the logbook is open, so a
    /// confirmation in a second window can't move the store in use.
    func startNew(date: Date = .now) {
        guard case .failed = status else { return }
        do {
            if let backup = try store.moveAside(date: date) {
                Self.logger.notice("Moved the logbook aside to Logbook Backups/\(backup.lastPathComponent, privacy: .public)")
            }
        } catch {
            Self.logger.error("Couldn't move the logbook aside: \(String(describing: error))")
            status = .failed(error)
            return
        }
        status = Self.open(store)
    }

    private static func open(_ store: LogbookStore) -> Status {
        do {
            return .open(try store.open())
        } catch {
            logger.error("Couldn't open the logbook: \(String(describing: error))")
            return .failed(error)
        }
    }
}
