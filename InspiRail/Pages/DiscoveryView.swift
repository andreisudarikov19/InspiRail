//
//  DiscoveryView.swift
//  InspiRail
//
//  Created by Andrei Sudarikov on 04/01/2026.
//
import SwiftData
import SwiftUI
import MapKit
import CoreLocation

struct DiscoveryView: View {
    @StateObject private var viewModel = DiscoveryViewModel()
    @Environment(\.stationsRepository) private var stationsRepository
    
    @Environment(\.modelContext) private var modelContext
    @Query private var visitedStations: [VisitedStation]
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    @AppStorage("homeStationCode") private var homeStationCode: String = ""
    
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

                // MAIN LAYOUT
                // We use spacing: 20 here to match the spacing inside stationDetailView
                VStack(spacing: 20) {
                    
                    if viewModel.isLoading && !viewModel.isReady {
                        loadingView
                    } else if let station = viewModel.station {
                        // This view contains the Header and the Map
                        // It will expand to fill available space because the Map inside is flexible
                        stationDetailView(for: station)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    } else if let error = viewModel.errorMessage {
                        errorView(message: error)
                    } else {
                        emptyStateView
                    }
                    
                    randomizeButton
                }
                .padding(.horizontal)
                .padding(.bottom) // Respects safe area
                .task {
                    guard let stationsRepository else { return }
                    await viewModel.loadStations(from: stationsRepository)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - STATION DETAIL
    private func stationDetailView(for station: Station) -> some View {
        // Internal Spacing: 20 (Matches Main Layout)
        VStack(spacing: 20) {
            
            // 1. HEADER CARD
            HStack(alignment: .center, spacing: 16) {
                // Monogram
                Text(station.identifiers.code)
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.8))
                    .frame(width: 64, height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.yellow)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                    )
                
                // Info
                VStack(alignment: .leading, spacing: 6) {
                    Text(station.names.long)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.9)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
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
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 4)
            
            // 2. IMMERSIVE MAP
            let isVisited = visitedStations.contains(where: { $0.stationCode == station.identifiers.code })
            
            ZStack(alignment: .top) {
                // A. MAP
                Map(position: $cameraPosition) {
                    Marker(station.names.short, coordinate: station.coordinate)
                        .tint(.blue)
                }
                .frame(maxHeight: .infinity) // This pushes the layout!
                
                // B. GLASS HUD
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    GlassPill(
                        icon: "arrow.triangle.swap",
                        label: "Distance",
                        value: calculateDistance(to: station),
                        color: .purple
                    )
                    GlassPill(
                        icon: "clock.fill",
                        label: "Travel Time",
                        value: calculateTravelTime(to: station),
                        color: .indigo
                    )
                    GlassPill(
                        icon: "cup.and.saucer.fill",
                        label: "Amenities",
                        value: (station.hasKnownFacilities == true) ? "Yes" : "No",
                        color: .orange
                    )
                    GlassPill(
                        icon: "figure.roll",
                        label: "Assist",
                        value: (station.hasTravelAssistance == true) ? "Yes" : "No",
                        color: .blue
                    )
                }
                .padding()
                
                // C. ACTION BAR
                VStack {
                    Spacer()
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
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: Color.black.opacity(0.12), radius: 12, x: 0, y: 6)
            .onChange(of: station.id) { _, _ in updateMapCamera(for: station) }
        }
        .onAppear { updateMapCamera(for: station, animate: false) }
    }
    
    // MARK: - GLASS PILL
    struct GlassPill: View {
        let icon: String
        let label: String
        let value: String
        let color: Color
        
        var body: some View {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(color.opacity(0.15))
                    Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(color)
                }
                .frame(width: 44, height: 44)
                .overlay(Circle().strokeBorder(color.opacity(0.3), lineWidth: 1))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                Spacer()
            }
            .padding(6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 3)
        }
    }
    
    // MARK: - CALCULATIONS
    private func getHomeLocation() -> CLLocation? {
        guard let home = viewModel.getStation(byCode: homeStationCode) else { return nil }
        return CLLocation(latitude: home.location.lat, longitude: home.location.lng)
    }
    
    private func calculateDistance(to targetStation: Station) -> String {
        guard let homeLoc = getHomeLocation() else { return "--" }
        let targetLoc = CLLocation(latitude: targetStation.location.lat, longitude: targetStation.location.lng)
        let distanceInKm = homeLoc.distance(from: targetLoc) / 1000
        return String(format: "%.0f km", distanceInKm)
    }
    
    private func calculateTravelTime(to targetStation: Station) -> String {
        guard let homeLoc = getHomeLocation() else { return "--" }
        let targetLoc = CLLocation(latitude: targetStation.location.lat, longitude: targetStation.location.lng)
        let distanceInKm = homeLoc.distance(from: targetLoc) / 1000
        let speedKmH = 90.0
        let hours = distanceInKm / speedKmH
        let totalMinutes = Int(hours * 60) + 15
        if totalMinutes > 60 {
            let h = totalMinutes / 60
            let m = totalMinutes % 60
            return "\(h)h \(m)m"
        } else {
            return "\(totalMinutes) min"
        }
    }

    // MARK: - STANDARD COMPONENTS
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
        Button(action: { 
            viewModel.randomize(excludeHomeStation: homeStationCode) 
        }) {
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
        let newCamera = MapCamera(centerCoordinate: station.coordinate, distance: 4000, heading: 0, pitch: 0)
        if animate { withAnimation(.easeInOut(duration: 1.0)) { cameraPosition = .camera(newCamera) } }
        else { cameraPosition = .camera(newCamera) }
    }
    
    private func errorView(message: String) -> some View {
        ContentUnavailableView("Connection Issue", systemImage: "wifi.slash", description: Text(message))
    }
}

