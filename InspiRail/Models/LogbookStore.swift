//
//  LogbookStore.swift
//  InspiRail
//
//  Opens the logbook's SwiftData store, or moves it aside. It never deletes a
//  file: the logbook is the only record of the user's visits (#17).
//

import Foundation
import SwiftData

/// The logbook's store at one URL: `default.store` and SQLite's `-wal` and
/// `-shm` files next to it.
struct LogbookStore {
    static let schema = Schema([VisitedStation.self])

    /// Where SwiftData's default configuration keeps the store, and where
    /// every release so far has kept it.
    static var defaultURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    let url: URL
    private let fileManager: FileManager

    init(url: URL, fileManager: FileManager = .default) {
        self.url = url
        self.fileManager = fileManager
    }

    var configuration: ModelConfiguration {
        ModelConfiguration(schema: Self.schema, url: url)
    }

    /// Where `moveAside(date:)` puts the old files, next to the store.
    var backupsFolder: URL {
        url.deletingLastPathComponent().appending(path: "Logbook Backups")
    }

    /// Opens the store, creating it if there is none. On failure it throws
    /// and leaves the files as they are.
    func open() throws -> ModelContainer {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try ModelContainer(for: Self.schema, configurations: [configuration])
    }

    /// Moves the store and its `-wal` and `-shm` files into a new folder in
    /// `backupsFolder`, named after `date` in UTC, and returns that folder.
    /// Returns nil, creating nothing, when there is no store file. It never
    /// reuses an existing folder, and if a move fails it puts the files it
    /// already moved back before throwing, so a store is never split from its
    /// WAL.
    @discardableResult
    func moveAside(date: Date = .now) throws -> URL? {
        let files = [url, sideFile("-wal"), sideFile("-shm")]
            .filter { fileManager.fileExists(atPath: $0.path(percentEncoded: false)) }
        guard !files.isEmpty else { return nil }

        try fileManager.createDirectory(at: backupsFolder, withIntermediateDirectories: true)
        let backup = backupsFolder.appending(path: Self.backupName(for: date), directoryHint: .isDirectory)
        try fileManager.createDirectory(at: backup, withIntermediateDirectories: false)

        var moved: [(from: URL, to: URL)] = []
        do {
            for file in files {
                let destination = backup.appending(path: file.lastPathComponent)
                try fileManager.moveItem(at: file, to: destination)
                moved.append((file, destination))
            }
        } catch {
            for move in moved.reversed() {
                try? fileManager.moveItem(at: move.to, to: move.from)
            }
            throw error
        }
        return backup
    }

    private func sideFile(_ suffix: String) -> URL {
        url.deletingLastPathComponent().appending(path: url.lastPathComponent + suffix)
    }

    /// `2026-11-01T12-35-32Z`: sorts by time, with no colons.
    private static func backupName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        return formatter.string(from: date)
    }
}
