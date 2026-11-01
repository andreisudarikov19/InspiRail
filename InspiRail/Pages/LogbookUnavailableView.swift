//
//  LogbookUnavailableView.swift
//  InspiRail
//
//  Shown instead of the tabs when the logbook's store can't be opened (#17).
//

import SwiftUI

struct LogbookUnavailableView: View {
    /// The old logbook is in a backup folder, and a new one couldn't be opened.
    let movedAside: Bool
    let tryAgain: () -> Void
    let startNew: () -> Void
    
    @State private var confirmingStartNew = false
    
    var body: some View {
        ContentUnavailableView {
            Label("Can't Open Your Logbook", systemImage: "book.closed")
        } description: {
            if movedAside {
                Text("Your old logbook was moved to a backup folder on this device, but a new one couldn't be opened.")
            } else {
                Text("The logbook with your visits couldn't be opened. Nothing has been deleted.")
            }
        } actions: {
            Button("Try Again", action: tryAgain)
                .buttonStyle(.borderedProminent)
            Button("Start a New Logbook", role: .destructive) {
                confirmingStartNew = true
            }
        }
        .alert("Start a New Logbook?", isPresented: $confirmingStartNew) {
            Button("Cancel", role: .cancel) { }
            Button("Start New Logbook", role: .destructive, action: startNew)
        } message: {
            Text("Your current logbook will be moved to a backup folder on this device, and you'll start with an empty logbook. The app won't show the visits in the backup.")
        }
    }
}
