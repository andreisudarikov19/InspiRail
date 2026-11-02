//
//  VisitedListView.swift
//  InspiRail
//
//  Created by Andrei Sudarikov on 03/01/2026.
//

import SwiftUI
import SwiftData

struct VisitedListView: View {
    @Query(sort: \VisitedStation.dateVisited, order: .reverse)
    private var visitedStations: [VisitedStation]

    @AppStorage("homeStationCode") private var homeStationCode: String = ""
    @AppStorage("homeStationName") private var homeStationName: String = ""

    /// Last-known total Dutch station count, persisted across launches so the
    /// hero stats don't flicker on first frame. Zero means "not yet known".
    @AppStorage("cachedTotalStations") private var cachedTotalStations: Int = 0

    @Environment(\.stationsRepository) private var stationsRepository

    private var visitedExcludingHome: [VisitedStation] {
        visitedStations.filter { $0.stationCode != homeStationCode }
    }

    private var visitedCount: Int { visitedExcludingHome.count }

    private var progress: Double {
        guard cachedTotalStations > 0 else { return 0 }
        return min(1.0, Double(visitedCount) / Double(cachedTotalStations))
    }

    /// Groups visited stations by "Month Year" while preserving the query's
    /// reverse-chronological sort.
    private var historyByMonth: [(month: String, stations: [VisitedStation])] {
        var groups: [(String, [VisitedStation])] = []
        for station in visitedExcludingHome {
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
            List {
                statsSection

                if !homeStationCode.isEmpty {
                    homeSection
                }

                if visitedExcludingHome.isEmpty {
                    emptyTimelineSection
                } else {
                    timelineSections
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Logbook")
            .task { await refreshTotalStationCount() }
        }
    }

    // MARK: - Sections

    private var statsSection: some View {
        Section {
            StatsHeader(
                visitedCount: visitedCount,
                totalCount: cachedTotalStations,
                progress: progress
            )
            .listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
        }
    }

    private var homeSection: some View {
        Section("Home") {
            HomeStationRow(
                name: homeStationName.isEmpty ? homeStationCode : homeStationName,
                code: homeStationCode
            )
        }
    }

    private var emptyTimelineSection: some View {
        Section {
            EmptyTimelinePrompt()
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
    }

    @ViewBuilder
    private var timelineSections: some View {
        ForEach(historyByMonth, id: \.month) { group in
            Section(group.month) {
                ForEach(group.stations) { visit in
                    VisitedStationRow(
                        name: visit.stationName,
                        code: visit.stationCode,
                        date: visit.dateVisited
                    )
                }
            }
        }
    }

    // MARK: - Data

    /// Refresh the total Dutch station count from the app's station store,
    /// which downloads the list at most once an hour (#18). Cached value backs
    /// the hero so the next launch renders instantly.
    private func refreshTotalStationCount() async {
        guard let stationsRepository else {
            reportMissingStationStore(in: "The Logbook")
            return
        }
        do {
            let dutchCount = try await stationsRepository.dutchStationCount()
            if dutchCount > 0 {
                cachedTotalStations = dutchCount
            }
        } catch {
            // Cached value (if any) still serves; silent failure is the right
            // call here since this is a non-critical background refresh.
        }
    }
}

// MARK: - Stats Header

private struct StatsHeader: View {
    let visitedCount: Int
    let totalCount: Int
    let progress: Double

    private var percentage: Int { Int((progress * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(countText)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .contentTransition(.numericText(value: Double(visitedCount)))
                    .animation(.easeOut(duration: 0.4), value: visitedCount)
                    .monospacedDigit()

                Spacer()

                if totalCount > 0 {
                    Text("\(percentage)%")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            ProgressView(value: progress)
                .tint(.blue)
                .animation(.easeOut(duration: 0.6), value: progress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var countText: String {
        guard totalCount > 0 else { return "\(visitedCount) visited" }
        return "\(visitedCount) of \(totalCount)"
    }

    private var accessibilityDescription: String {
        guard totalCount > 0 else { return "\(visitedCount) stations visited" }
        return "\(visitedCount) of \(totalCount) stations visited, \(percentage) percent"
    }
}

// MARK: - Station Code Badge

private struct StationCodeBadge: View {
    let code: String

    var body: some View {
        Text(code)
            .font(.system(.subheadline, design: .monospaced).weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.yellow.opacity(0.45))
            )
    }
}

// MARK: - Home Station Row

private struct HomeStationRow: View {
    let name: String
    let code: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text("Home Station")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }

            Spacer()

            Image(systemName: "house.fill")
                .font(.subheadline)
                .foregroundStyle(.blue)

            StationCodeBadge(code: code)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), home station, code \(code)")
    }
}

// MARK: - Visited Row

private struct VisitedStationRow: View {
    let name: String
    let code: String
    let date: Date

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body)
                    .foregroundStyle(.primary)

                Text(VisitDateFormatter.relativeLabel(for: date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            StationCodeBadge(code: code)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(VisitDateFormatter.accessibilityLabel(for: date)), code \(code)")
    }
}

// MARK: - Empty State

private struct EmptyTimelinePrompt: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "tram.fill")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.tertiary)

            Text("No visits yet")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Mark a station as visited from the Discover tab and it will show up here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

// MARK: - Smart relative date formatting

private enum VisitDateFormatter {
    /// "Just now" / "Yesterday" / weekday for recent visits within a month,
    /// "Jan 16" for older within current year, "Jan 16, 2025" for older still.
    static func relativeLabel(for date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let nowDay = calendar.startOfDay(for: now)
        let dateDay = calendar.startOfDay(for: date)
        let daysApart = calendar.dateComponents([.day], from: dateDay, to: nowDay).day ?? 0

        if daysApart == 0 {
            let secondsAgo = now.timeIntervalSince(date)
            return secondsAgo < 3600 ? "Just now" : "Today"
        }
        if daysApart == 1 { return "Yesterday" }
        if daysApart < 7 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.abbreviated).day())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().year())
    }

    static func accessibilityLabel(for date: Date) -> String {
        date.formatted(date: .long, time: .omitted)
    }
}
