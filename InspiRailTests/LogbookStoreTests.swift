//
//  LogbookStoreTests.swift
//  InspiRailTests
//

import Foundation
import SwiftData
import Testing
@testable import InspiRail

/// The logbook is the only record of the user's visits, so the store must
/// never be deleted: it opens, or it fails and is left as it was, or the user
/// moves it aside (#17). Each test works in its own temporary directory and
/// never touches the app's real store.
@Suite("Logbook store")
@MainActor
final class LogbookStoreTests {
    let dir: URL
    let storeURL: URL

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "LogbookStoreTests-\(UUID().uuidString)")
        storeURL = dir.appending(path: "default.store")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #require(!filePath(dir).hasPrefix(filePath(URL.applicationSupportDirectory)))
    }

    deinit {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("A store opens again with its visits")
    func opensExistingStoreAndKeepsVisits() throws {
        let date = Date(timeIntervalSince1970: 1_780_000_000)
        try autoreleasepool {
            let container = try LogbookStore(url: storeURL).open()
            try addVisit(code: "UT", name: "Utrecht Centraal", date: date, to: container)
        }

        let container = try LogbookStore(url: storeURL).open()
        let visits = try visits(in: container)

        #expect(visits.count == 1)
        #expect(visits.first?.stationCode == "UT")
        #expect(visits.first?.stationName == "Utrecht Centraal")
        #expect(visits.first?.dateVisited == date)
    }

    @Test("A store written before 1.3.0, with three fields, opens with its visits")
    func opensThreeFieldStore() throws {
        try autoreleasepool {
            let schema = Schema([ThreeFieldLogbook.VisitedStation.self])
            let configuration = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            container.mainContext.insert(ThreeFieldLogbook.VisitedStation(stationCode: "ASD", stationName: "Amsterdam Centraal"))
            try container.mainContext.save()
        }

        let container = try LogbookStore(url: storeURL).open()
        let visits = try visits(in: container)

        #expect(visits.map(\.stationCode) == ["ASD"])
        #expect(visits.first?.stationName == "Amsterdam Centraal")
        #expect(visits.first?.notes == nil)
        #expect(visits.first?.rating == nil)
    }

    @Test("A file that can't be opened throws, and is left as it was")
    func unreadableStoreIsLeftAlone() throws {
        let garbage = Data(repeating: 0x5A, count: 4096)
        let wal = Data("wal".utf8)
        try garbage.write(to: storeURL)
        try wal.write(to: storeURL.appendingStoreSuffix("-wal"))
        let listing = try contents(of: dir)

        #expect(throws: (any Error).self) {
            _ = try LogbookStore(url: self.storeURL).open()
        }

        #expect(try Data(contentsOf: storeURL) == garbage)
        #expect(try Data(contentsOf: storeURL.appendingStoreSuffix("-wal")) == wal)
        #expect(try contents(of: dir) == listing)
    }

    @Test("Moving aside keeps the old files in a dated backup and leaves an empty, working store")
    func moveAsideKeepsOldFilesAndOpensEmptyStore() throws {
        try autoreleasepool {
            let container = try LogbookStore(url: storeURL).open()
            try addVisit(code: "UT", name: "Utrecht Centraal", to: container)
        }
        var original: [String: Data] = [:]
        for name in storeFileNames where FileManager.default.fileExists(atPath: filePath(dir.appending(path: name))) {
            original[name] = try Data(contentsOf: dir.appending(path: name))
        }
        try #require(original["default.store"] != nil)

        let backup = try #require(try LogbookStore(url: storeURL).moveAside(date: Date(timeIntervalSince1970: 1_793_536_532)))

        #expect(filePath(backup) == filePath(dir.appending(path: "Logbook Backups/2026-11-01T12-35-32Z")))
        for (name, data) in original {
            #expect(try Data(contentsOf: backup.appending(path: name)) == data, "\(name) in the backup")
        }
        #expect(try contents(of: backup) == original.keys.sorted())
        for name in storeFileNames {
            #expect(!FileManager.default.fileExists(atPath: filePath(dir.appending(path: name))), "\(name) left behind")
        }

        try autoreleasepool {
            let fresh = try LogbookStore(url: storeURL).open()
            #expect(try visits(in: fresh).isEmpty)
            try addVisit(code: "ASD", name: "Amsterdam Centraal", to: fresh)
            #expect(try visits(in: fresh).map(\.stationCode) == ["ASD"])
        }

        let old = try LogbookStore(url: backup.appending(path: "default.store")).open()
        #expect(try visits(in: old).map(\.stationCode) == ["UT"])
    }

    @Test("Moving aside with no store creates nothing")
    func moveAsideWithNoStoreReturnsNil() throws {
        let store = LogbookStore(url: storeURL)

        #expect(try store.moveAside() == nil)
        #expect(!FileManager.default.fileExists(atPath: filePath(store.backupsFolder)))
    }

    @Test("Moving aside never reuses a backup folder that already exists")
    func neverReusesBackupFolder() throws {
        let garbage = Data(repeating: 0x5A, count: 4096)
        let wal = Data("wal".utf8)
        try garbage.write(to: storeURL)
        try wal.write(to: storeURL.appendingStoreSuffix("-wal"))
        // The folder holds no store file, so only refusing to reuse it can
        // stop the move.
        let earlier = dir.appending(path: "Logbook Backups/2026-11-01T12-35-32Z")
        let note = Data("earlier".utf8)
        try FileManager.default.createDirectory(at: earlier, withIntermediateDirectories: true)
        try note.write(to: earlier.appending(path: "notes.txt"))

        #expect(throws: (any Error).self) {
            try LogbookStore(url: self.storeURL).moveAside(date: Date(timeIntervalSince1970: 1_793_536_532))
        }

        #expect(try contents(of: earlier) == ["notes.txt"])
        #expect(try Data(contentsOf: earlier.appending(path: "notes.txt")) == note)
        #expect(try Data(contentsOf: storeURL) == garbage)
        #expect(try Data(contentsOf: storeURL.appendingStoreSuffix("-wal")) == wal)
    }

    @Test("A move that fails part-way puts every file back")
    func failedMovePutsFilesBack() throws {
        var original: [String: Data] = [:]
        for name in storeFileNames {
            original[name] = Data("bytes of \(name)".utf8)
            try original[name]!.write(to: dir.appending(path: name))
        }
        let store = LogbookStore(url: storeURL, fileManager: FailingSecondMove())

        #expect(throws: (any Error).self) {
            try store.moveAside(date: Date(timeIntervalSince1970: 1_793_536_532))
        }

        for (name, data) in original {
            #expect(try Data(contentsOf: dir.appending(path: name)) == data, "\(name) put back")
        }
        let backup = store.backupsFolder.appending(path: "2026-11-01T12-35-32Z")
        for name in storeFileNames {
            #expect(!FileManager.default.fileExists(atPath: filePath(backup.appending(path: name))), "\(name) in the backup")
        }
    }

    @Test("The app's store is the file SwiftData's default configuration used")
    func defaultLocationIsSwiftDataDefault() {
        let swiftDataDefault = ModelConfiguration(schema: LogbookStore.schema, isStoredInMemoryOnly: false)

        #expect(LogbookStore(url: LogbookStore.defaultURL).configuration.url == swiftDataDefault.url)
        #expect(LogbookStore.defaultURL.lastPathComponent == "default.store")
    }

    // MARK: - Helpers

    private let storeFileNames = ["default.store", "default.store-wal", "default.store-shm"]

    private func addVisit(code: String, name: String, date: Date = .now, to container: ModelContainer) throws {
        container.mainContext.insert(VisitedStation(stationCode: code, stationName: name, dateVisited: date))
        try container.mainContext.save()
    }

    private func visits(in container: ModelContainer) throws -> [VisitedStation] {
        try container.mainContext.fetch(FetchDescriptor<VisitedStation>(sortBy: [SortDescriptor(\.stationCode)]))
    }

    private func contents(of folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: filePath(folder)).sorted()
    }
}

/// `VisitedStation` as builds before 1.3.0 stored it: the Sprint 1 project,
/// d565b4c and the internal builds that followed. 1.3.0 (eeefb47) added the
/// optional `notes`, `rating` and `_isFavorite`.
enum ThreeFieldLogbook {
    @Model
    final class VisitedStation {
        @Attribute(.unique) var stationCode: String
        var stationName: String
        var dateVisited: Date

        init(stationCode: String, stationName: String, dateVisited: Date = .now) {
            self.stationCode = stationCode
            self.stationName = stationName
            self.dateVisited = dateVisited
        }
    }
}

/// A file manager whose second move fails, as a full or failing disk might.
private final class FailingSecondMove: FileManager {
    private var moves = 0

    override func moveItem(at srcURL: URL, to dstURL: URL) throws {
        moves += 1
        if moves == 2 {
            throw CocoaError(.fileWriteUnknown)
        }
        try super.moveItem(at: srcURL, to: dstURL)
    }
}

/// A file URL's path without percent encoding or a trailing slash.
func filePath(_ url: URL) -> String {
    let path = url.standardizedFileURL.path(percentEncoded: false)
    return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
}

extension URL {
    /// `default.store` → `default.store-wal`: SQLite's names for a store's
    /// side files.
    func appendingStoreSuffix(_ suffix: String) -> URL {
        deletingLastPathComponent().appending(path: lastPathComponent + suffix)
    }
}
