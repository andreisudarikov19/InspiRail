//
//  DiscoveryView.swift
//  rnsapp
//
//  Created by Andrei Sudarikov on 04/01/2026.
//
import SwiftData
import SwiftUI
import MapKit

struct DiscoveryView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    
    @Environment(\.modelContext) private var modelContext
    @Query private var visitedStations: [VisitedStation]
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                LinearGradient(
                    colors: [
                        Color(uiColor: .systemGroupedBackground),
                        Color(uiColor: .secondarySystemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 24) {
                    
                    if viewModel.isLoading && !viewModel.isReady {
                        loadingView
                    } else if let station = viewModel.station {
                        stationDetailView(for: station)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else if let error = viewModel.errorMessage {
                        errorView(message: error)
                    } else {
                        emptyStateView
                    }
                    
                    Spacer()
                    
                    randomizeButton
                }
                .padding(.horizontal)
                .padding(.bottom)
                .task {
                    await viewModel.loadStations()
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - STATION DETAIL
        private func stationDetailView(for station: Station) -> some View {
            VStack(alignment: .leading, spacing: 20) {
                
                // A. HEADER: SINGLE UNIFIED CARD
                HStack(alignment: .center, spacing: 16) {
                    
                    // 1. The Monogram (Restored to 64x64, Horizontal)
                    Text(station.identifiers.code)
                        .font(.system(size: 22, weight: .heavy, design: .monospaced))
                        .foregroundStyle(.black.opacity(0.8))
                        .frame(width: 64, height: 64)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous) // Slightly tighter radius inside the card
                                .fill(Color.yellow)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                        )
                        // No separate shadow needed here as it's inside the card
                    
                    // 2. The Info Column
                    VStack(alignment: .leading, spacing: 6) {
                        Text(station.names.long)
                            .font(.system(size: 22, weight: .bold, design: .rounded)) // Adjusted size for balance
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.9)
                        
                        // The Pills
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                // Type Pill (Blue)
                                HStack(spacing: 4) {
                                    Image(systemName: "train.side.front.car")
                                        .font(.caption2)
                                    Text(station.readableType)
                                        .font(.caption2.weight(.bold))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.1))
                                .foregroundStyle(.blue)
                                .clipShape(Capsule())
                                
                                // Synonym Pill (Gray)
                                if let synonyms = station.names.synonyms, let firstSynonym = synonyms.first {
                                    HStack(spacing: 4) {
                                        Image(systemName: "quote.bubble.fill")
                                            .font(.caption2)
                                        Text(firstSynonym)
                                            .font(.caption2.weight(.medium))
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.gray.opacity(0.1))
                                    .foregroundStyle(.secondary)
                                    .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .padding(12) // Padding inside the unified card
                .frame(maxWidth: .infinity, alignment: .leading)
                // THE UNIFIED FRAME
                .background(Color(uiColor: .tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
                
                // B. FEATURE GRID
                HStack(spacing: 0) {
                    if let tracks = station.tracks {
                        featureBox(icon: "tram", label: "Tracks", value: "\(tracks.count)", color: .indigo)
                    } else {
                        featureBox(icon: "tram", label: "Tracks", value: "-", color: .gray)
                    }
                    Spacer()
                    if station.hasKnownFacilities == true {
                        featureBox(icon: "cup.and.saucer.fill", label: "Amenities", value: "Yes", color: .orange)
                    } else {
                        featureBox(icon: "cup.and.saucer", label: "Amenities", value: "No", color: .gray)
                    }
                    Spacer()
                    if station.hasTravelAssistance == true {
                        featureBox(icon: "figure.roll", label: "Assist", value: "Yes", color: .blue)
                    } else {
                         featureBox(icon: "figure.roll", label: "Assist", value: "No", color: .gray)
                    }
                    Spacer()
                    featureBox(icon: "location.north.fill", label: "GPS", value: String(format: "%.1f, %.1f", station.location.lat, station.location.lng), color: .green)
                }
                
                // C. MAP
                let isVisited = visitedStations.contains(where: { $0.stationCode == station.identifiers.code })
                
                ZStack(alignment: .bottom) {
                    Map(position: $cameraPosition) {
                        Marker(station.names.short, coordinate: station.coordinate)
                            .tint(.blue)
                    }
                    .frame(maxHeight: 380)
                    
                    // The Bottom Panel
                    HStack {
                        Button(action: {
                            toggleVisited(station: station, alreadyVisited: isVisited)
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: isVisited ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                
                                Text(isVisited ? "Visited" : "Mark as Visited")
                                    .font(.headline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.ultraThinMaterial)
                            .foregroundStyle(isVisited ? .green : .blue)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(
                                        (isVisited ? Color.green : Color.blue).opacity(0.3),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
                .onChange(of: station.id) { _, _ in updateMapCamera(for: station) }
            }
            .onAppear { updateMapCamera(for: station, animate: false) }
        }
    
    // MARK: - HELPERS
    private func featureBox(icon: String, label: String, value: String?, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(height: 24)
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).textCase(.uppercase)
            if let val = value {
                Text(val).font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(.primary).minimumScaleFactor(0.8).lineLimit(1)
            }
        }
        .frame(width: 72, height: 72)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tram.fill").font(.system(size: 80))
                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .padding(.bottom, 8).symbolEffect(.pulse, isActive: true)
            Text("Where to next?").font(.title.weight(.bold))
            Text("Tap the button below to discover\nyour next destination.").multilineTextAlignment(.center).foregroundStyle(.secondary)
            Spacer()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 20) {
            Spacer(); ProgressView().controlSize(.extraLarge); Text("Consulting the timetable...").font(.headline).foregroundStyle(.secondary); Spacer()
        }
    }
    
    private var randomizeButton: some View {
        Button(action: { viewModel.randomize() }) {
            HStack(spacing: 12) {
                Image(systemName: "shuffle").font(.headline)
                Text("Randomize Station").font(.headline.weight(.semibold))
            }
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(.blue).foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.isReady)
        .opacity(viewModel.isReady ? 1.0 : 0.6)
    }

    private func toggleVisited(station: Station, alreadyVisited: Bool) {
        if alreadyVisited {
            if let existing = visitedStations.first(where: { $0.stationCode == station.identifiers.code }) { modelContext.delete(existing) }
        } else {
            let newVisit = VisitedStation(stationCode: station.identifiers.code, stationName: station.names.long)
            modelContext.insert(newVisit)
        }
    }
    
    private func updateMapCamera(for station: Station, animate: Bool = true) {
        let newCamera = MapCamera(centerCoordinate: station.coordinate, distance: 2500, heading: 0, pitch: 0)
        if animate { withAnimation(.easeInOut(duration: 1.0)) { cameraPosition = .camera(newCamera) } }
        else { cameraPosition = .camera(newCamera) }
    }
    
    private func errorView(message: String) -> some View {
        ContentUnavailableView("Connection Issue", systemImage: "wifi.slash", description: Text(message))
    }
}
