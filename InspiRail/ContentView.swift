//
//  ContentView.swift
//  InspiRail
//
//  Created by Andrei Sudarikov on 02/01/2026.
//
import SwiftUI
import SwiftData

struct MainTabView: View {
    @AppStorage("homeStationCode") private var homeStationCode: String = ""
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    
    var body: some View {
        if homeStationCode.isEmpty {
                OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding) // Force selection if empty
        } else {
            TabView {
                // Tab 1: Discovery
                NavigationStack {
                    DiscoveryView()
                }
                .tabItem {
                    Label("Discover", systemImage: "shuffle")
                }
                
                // Tab 2: Logbook
                NavigationStack {
                    VisitedListView()
                }
                .tabItem {
                    Label("Logbook", systemImage: "book")
                }
                // Tab 3: Settings
                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
    }
}

