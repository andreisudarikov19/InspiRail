//
//  InspiRailApp.swift
//  InspiRail
//
//  Created by Andrei Sudarikov on 02/01/2026.
//

import SwiftUI
import SwiftData

@main
struct InspiRailApp: App {
    
    /// When the app only hosts the unit tests, it shows an empty scene with an
    /// in-memory store and skips its startup work, so a test run makes no
    /// requests and never opens the stored visits (#15).
    private let isHostingUnitTests = AppConfiguration.isHostingUnitTests()
    
    /// The logbook, opened once for the whole app so that every window shares
    /// one container (#17). Nil while hosting the unit tests.
    @State private var logbook: Logbook?
    
    init() {
        guard !isHostingUnitTests else { return }
        // Log app configuration on startup
        AppConfiguration.logConfiguration()
        _logbook = State(initialValue: Logbook(store: LogbookStore(url: LogbookStore.defaultURL)))
    }
    
    var body: some Scene {
        WindowGroup {
            if isHostingUnitTests {
                Color.clear
                    .modelContainer(for: VisitedStation.self, inMemory: true)
            } else if let logbook {
                LogbookRootView(logbook: logbook)
            }
        }
    }
}

/// A window's content: the tabs with the app's one container, or the error
/// screen when the logbook couldn't be opened.
private struct LogbookRootView: View {
    let logbook: Logbook
    
    var body: some View {
        switch logbook.status {
        case .open(let container):
            MainTabView()
                .modelContainer(container)
        case .failed(let error):
            LogbookUnavailableView(error: error, tryAgain: logbook.tryAgain, startNew: { logbook.startNew() })
        }
    }
}
