//
//  VisitedListView.swift
//  rnsapp
//
//  Created by Andrei Sudarikov on 03/01/2026.
//

import SwiftUI
import SwiftData

struct VisitedListView: View {
    @Query(sort: \VisitedStation.dateVisited, order: .reverse)
    private var visitedStations: [VisitedStation]
    
    @AppStorage("homeStationCode") private var homeStationCode: String = ""
    @State private var homeStation: Station?
    @State private var totalStations = 397
    @State private var progressValue: Double = 0.0
    
    // MARK: - Computed Grouping Logic
    // Groups stations by "Month Year" (e.g., "January 2026") keeping the sort order.
    private var historyByMonth: [(month: String, stations: [VisitedStation])] {
        let filtered = visitedStations.filter { $0.stationCode != homeStationCode }
        
        // Since visitedStations is already sorted by date (reverse),
        // we can just iterate linearly to group them.
        var groups: [(String, [VisitedStation])] = []
        
        for station in filtered {
            let monthTitle = station.dateVisited.formatted(.dateTime.month(.wide).year())
            
            if let lastIndex = groups.indices.last, groups[lastIndex].0 == monthTitle {
                groups[lastIndex].1.append(station)
            } else {
                groups.append((monthTitle, [station]))
            }
        }
        return groups
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground)
                    .ignoresSafeArea()
                
                List {
                    // MARK: - 1. Stats Header
                    Section {
                        StatsHeaderView(
                            visitedCount: visitedStations.count,
                            totalCount: totalStations,
                            progress: progressValue
                        )
                        .listRowBackground(Color.clear)
                        .padding(.vertical, 4)
                    }
                    
                    // MARK: - 2. Home Station (Pinned)
                    if let home = homeStation {
                        Section {
                            StationRowView(
                                name: home.names.long,
                                code: home.identifiers.code,
                                date: nil,
                                isHome: true
                            )
                        }
                    }
                    
                    // MARK: - 3. Timeline (Grouped by Month)
                    ForEach(historyByMonth, id: \.month) { group in
                        Section(header: Text(group.month)) {
                            ForEach(group.stations) { visit in
                                StationRowView(
                                    name: visit.stationName,
                                    code: visit.stationCode,
                                    date: visit.dateVisited,
                                    isHome: false
                                )
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Logbook")
            .navigationBarTitleDisplayMode(.large)
            .task {
                await loadStationData()
                withAnimation(.easeOut(duration: 1.5)) {
                    progressValue = Double(visitedStations.count) / Double(totalStations)
                }
            }
        }
    }
    
    private func loadStationData() async {
        do {
            let repository = StationsRepository()
            let response = try await repository.stations()
            let stations = response.payload.filter { $0.country == "NL" }
            
            self.totalStations = stations.count
            
            if let foundHome = stations.first(where: { $0.identifiers.code == homeStationCode }) {
                self.homeStation = foundHome
            }
        } catch {
            print("Failed to fetch station data: \(error)")
        }
    }
}

// MARK: - Subviews

struct StatsHeaderView: View {
    let visitedCount: Int
    let totalCount: Int
    let progress: Double
    
    var percentage: Int {
        Int(progress * 100)
    }
    
    var body: some View {
        HStack(spacing: 20) {
            // Ring
            ZStack {
                Circle()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 8)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            gradient: Gradient(colors: [.blue, .purple]),
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                
                Text("\(percentage)%")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            .frame(width: 80, height: 80)
            
            // Stats Text
            VStack(alignment: .leading, spacing: 4) {
                Text("Discovery progress")
                    .font(.headline)
                
                HStack {
                    Text("\(visitedCount)")
                        .bold()
                        .foregroundColor(.blue)
                    Text("of \(totalCount) stations visited")
                        .foregroundColor(.secondary)
                }
                .font(.subheadline)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct StationRowView: View {
    let name: String
    let code: String
    let date: Date?
    let isHome: Bool
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            
            // Left Side: Name & Date
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.medium))
                    .foregroundColor(isHome ? .primary : .primary)
                
                if let date = date {
                    // Date Format: "Friday, 16 January" (Year is in the header now!)
                    Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if isHome {
                    Text("Home Station")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
            
            Spacer()
            
            // Right Side: Icon (if Home) + Code
            if isHome {
                Image(systemName: "house.fill")
                    .font(.body)
                    .foregroundStyle(.blue)
            }
            
            Text(code)
                .font(.system(.body, design: .monospaced).weight(.bold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isHome ? Color.blue.opacity(0.1) : Color.yellow.opacity(0.3))
                .foregroundStyle(isHome ? .blue : .black.opacity(0.7))
                .cornerRadius(6)
        }
        .padding(.vertical, 4)
    }
}

