//
//  RecoveryButton.swift
//  InspiRail
//
//  The button a failed station load offers
//

import SwiftUI

/// The one thing a screen offers when the stations couldn't be loaded (#21):
/// Retry, or the way to Settings' key section when only a key can help
/// (`NetworkError.recoveryAction(for:)`). Discover, onboarding and the Home
/// Station picker show it, so the same error offers the same button
/// everywhere, with the look onboarding's Open Settings button had.
/// Onboarding shows it for Retry only: its key errors show its key step
/// (#42).
struct RecoveryButton: View {
    let action: RecoveryAction
    /// The key-entry button's title: where it leads from this screen.
    var keyEntryTitle: LocalizedStringKey = "Open Settings"
    let retry: () -> Void
    let enterKey: () -> Void
    
    var body: some View {
        Button {
            switch action {
            case .retry:
                retry()
            case .keyEntry:
                enterKey()
            }
        } label: {
            // White, as the prominent style draws its title. In a List row
            // the icon otherwise takes the button's own blue, and vanishes
            // into its background.
            label
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
    }
    
    @ViewBuilder
    private var label: some View {
        switch action {
        case .retry:
            Label("Retry", systemImage: "arrow.clockwise")
        case .keyEntry:
            Label(keyEntryTitle, systemImage: "gear")
        }
    }
}
