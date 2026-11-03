//
//  ContentView.swift
//  InspiRail
//
//  Created by Andrei Sudarikov on 02/01/2026.
//
import SwiftUI
import SwiftData

/// The window's tabs.
private enum MainTab: Hashable {
    case discover, logbook, settings
}

struct MainTabView: View {
    @AppStorage("homeStationCode") private var homeStationCode: String = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    /// The tab this window shows. Each window has its own, so Discover's
    /// Open Settings switches only the window it was tapped in (#21).
    @State private var selectedTab = MainTab.discover
    
    var body: some View {
        if homeStationCode.isEmpty {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding) // Force selection if empty
        } else {
            TabView(selection: $selectedTab) {
                // Tab 1: Discovery
                NavigationStack {
                    DiscoveryView(openSettings: { selectedTab = .settings })
                }
                .tabItem {
                    Label("Discover", systemImage: "shuffle")
                }
                .tag(MainTab.discover)
                
                // Tab 2: Logbook
                NavigationStack {
                    VisitedListView()
                }
                .tabItem {
                    Label("Logbook", systemImage: "book")
                }
                .tag(MainTab.logbook)
                // Tab 3: Settings
                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(MainTab.settings)
            }
        }
    }
}

