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
    
    /// The logbook, opened once for the whole app so that every window shares
    /// one container (#17). Nil while hosting the unit tests.
    @State private var logbook: Logbook?
    
    /// The station list and the one network session, created once for the
    /// whole app so that every window and screen shares one download (#18).
    /// Nil while hosting the unit tests, so a test run starts no fetch.
    @State private var stationsRepository: StationsRepository?
    
    init() {
        guard !isHostingUnitTests else { return }
        // Log app configuration on startup
        AppConfiguration.logConfiguration()
        _logbook = State(initialValue: Logbook(store: LogbookStore(url: LogbookStore.defaultURL)))
        _stationsRepository = State(initialValue: StationsRepository(backend: BackendAPI()))
    }
    
    var body: some Scene {
        WindowGroup {
            if isHostingUnitTests {
                Color.clear
                    .modelContainer(for: VisitedStation.self, inMemory: true)
            } else if let logbook {
                LogbookRootView(logbook: logbook)
                    .environment(\.stationsRepository, stationsRepository)
            }
        }
    }
}

extension EnvironmentValues {
    /// The app's one station store, which `InspiRailApp` sets on every window
    /// (#18). Nil only while hosting the unit tests, where no screen loads
    /// stations. Its default builds nothing, so a view that reads it without
    /// the App's store never makes one of its own.
    @Entry var stationsRepository: StationsRepository? = nil
}

/// Reports a screen that found no station store in its environment. Only the
/// unit-test host, which shows no screens, should be without one, so anywhere
/// else this logs a fault and stops a Debug build. The screen still loads
/// nothing.
func reportMissingStationStore(in screen: String, file: StaticString = #file, line: UInt = #line) {
    guard !AppConfiguration.isHostingUnitTests() else { return }
    let message = "\(screen) found no station store in its environment"
    Logger(subsystem: AppConfiguration.subsystem, category: "repository").fault("\(message, privacy: .public)")
    assertionFailure(message, file: file, line: line)
}

/// A window's content: the tabs with the app's one container, or the error
/// screen when the logbook couldn't be opened.
private struct LogbookRootView: View {
    let logbook: Logbook
    
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        content
            // The App opens the logbook when it is created, which can be during
            // prewarming after a restart, before the first unlock, while the
            // store can't be read. So each time a window becomes active, a
            // logbook that couldn't be opened is opened again. While it is open,
            // this does nothing.
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active {
                    logbook.tryAgain()
                }
            }
    }
    
    @ViewBuilder
    private var content: some View {
        switch logbook.status {
        case .open(let container):
            MainTabView()
                .modelContainer(container)
        case .failed(let movedAside):
            LogbookUnavailableView(movedAside: movedAside, tryAgain: logbook.tryAgain, startNew: { logbook.startNew() })
        }
    }
}
