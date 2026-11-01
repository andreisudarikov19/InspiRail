//
//  LogbookTests.swift
//  InspiRailTests
//

import Foundation
import SwiftData
import Testing
@testable import InspiRail

/// What the app's windows see: the logbook open, or the error screen with
/// Try Again and Start a New Logbook (#17). Each test works in its own
/// temporary directory and never touches the app's real store.
@Suite("Logbook")
@MainActor
final class LogbookTests {
    let dir: URL
    let store: LogbookStore
    let garbage = Data(repeating: 0x5A, count: 4096)

    init() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "LogbookTests-\(UUID().uuidString)")
        store = LogbookStore(url: dir.appending(path: "default.store"))
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try #require(!filePath(dir).hasPrefix(filePath(URL.applicationSupportDirectory)))
    }

    deinit {
        try? FileManager.default.removeItem(at: dir)
    }

    @Test("The logbook opens when it is created")
    func opensOnCreation() {
        #expect(Logbook(store: store).status.container != nil)
    }

    @Test("A store that can't be opened is reported, and left as it was")
    func failedOpenLeavesStoreAlone() throws {
        try garbage.write(to: store.url)

        let logbook = Logbook(store: store)

        #expect(logbook.status.isFailed)
        #expect(try Data(contentsOf: store.url) == garbage)
    }

    @Test("Try Again opens the logbook once the store can be opened")
    func tryAgainOpensOnceTheStoreCanBeOpened() throws {
        try garbage.write(to: store.url)
        let logbook = Logbook(store: store)

        logbook.tryAgain()

        #expect(logbook.status.isFailed)
        #expect(try Data(contentsOf: store.url) == garbage)

        // The cause goes away.
        let elsewhere = dir.appending(path: "elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: store.url, to: elsewhere.appending(path: "default.store"))

        logbook.tryAgain()

        #expect(logbook.status.container != nil)
    }

    @Test("Try Again opens the logbook with its visits once the store can be read")
    func tryAgainOpensTheStoreOnceItCanBeRead() throws {
        try autoreleasepool {
            let container = try store.open()
            container.mainContext.insert(VisitedStation(stationCode: "UT", stationName: "Utrecht Centraal"))
            try container.mainContext.save()
        }
        // Stands in for the store's file protection before the first unlock.
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: filePath(store.url))
        let logbook = Logbook(store: store)

        #expect(logbook.status.isFailed)

        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: filePath(store.url))
        logbook.tryAgain()

        let container = try #require(logbook.status.container)
        #expect(try container.mainContext.fetch(FetchDescriptor<VisitedStation>()).map(\.stationCode) == ["UT"])
    }

    @Test("Start a New Logbook moves the old store aside and opens an empty logbook")
    func startNewMovesAsideAndOpensEmptyLogbook() throws {
        try garbage.write(to: store.url)
        let logbook = Logbook(store: store)

        logbook.startNew(date: Date(timeIntervalSince1970: 1_793_536_532))

        let container = try #require(logbook.status.container)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<VisitedStation>()) == 0)
        let backup = store.backupsFolder.appending(path: "2026-11-01T12-35-32Z/default.store")
        #expect(try Data(contentsOf: backup) == garbage)
    }

    @Test("When the old store was moved aside but a new one can't be opened, the logbook says the old one is in a backup")
    func startNewThatCantOpenANewStoreSaysTheOldOneIsInABackup() throws {
        try garbage.write(to: store.url)
        let failingStore = LogbookStore(url: store.url, fileManager: CantCreateFolder(dir))
        let logbook = Logbook(store: failingStore)

        #expect(logbook.status.isFailed)
        #expect(!logbook.status.movedAside)

        logbook.startNew(date: Date(timeIntervalSince1970: 1_793_536_532))

        #expect(logbook.status.isFailed)
        #expect(logbook.status.movedAside)
        let backup = failingStore.backupsFolder.appending(path: "2026-11-01T12-35-32Z/default.store")
        #expect(try Data(contentsOf: backup) == garbage)

        logbook.tryAgain()

        #expect(logbook.status.movedAside, "the old store is still in the backup")
    }

    @Test("While the logbook is open, Start a New Logbook and Try Again change nothing")
    func startNewDoesNothingWhileOpen() throws {
        let logbook = Logbook(store: store)
        let container = try #require(logbook.status.container)
        container.mainContext.insert(VisitedStation(stationCode: "UT", stationName: "Utrecht Centraal"))
        try container.mainContext.save()

        logbook.startNew()
        logbook.tryAgain()

        #expect(logbook.status.container === container)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<VisitedStation>()) == 1)
        #expect(!FileManager.default.fileExists(atPath: filePath(store.backupsFolder)))
    }
}

extension Logbook.Status {
    var container: ModelContainer? {
        if case .open(let container) = self { container } else { nil }
    }

    var isFailed: Bool {
        if case .failed = self { true } else { false }
    }

    var movedAside: Bool {
        if case .failed(movedAside: true) = self { true } else { false }
    }
}

/// A file manager that can't create one folder, so a store in it can't be
/// opened, but can still be moved aside into a backup folder next to it.
private final class CantCreateFolder: FileManager {
    private let folder: URL

    init(_ folder: URL) {
        self.folder = folder
    }

    override func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool, attributes: [FileAttributeKey: Any]? = nil) throws {
        if filePath(url) == filePath(folder) {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: attributes)
    }
}
