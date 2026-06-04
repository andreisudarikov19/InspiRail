//
//  Visited Station.swift
//  rnsapp
//
//  Created by Andrei Sudarikov on 03/01/2026.
//
import Foundation
import SwiftData

@Model
final class VisitedStation {
    @Attribute(.unique) var stationCode: String // Unique ID (e.g., "UT")
    var stationName: String
    var dateVisited: Date
    
    // Optional: Store additional metadata
    var notes: String?
    var rating: Int? // 1-5 star rating
    
    // Make isFavorite optional to support migration from older versions
    // Default to false for existing records
    private var _isFavorite: Bool?
    var isFavorite: Bool {
        get { _isFavorite ?? false }
        set { _isFavorite = newValue }
    }
    
    init(
        stationCode: String,
        stationName: String,
        dateVisited: Date = .now,
        notes: String? = nil,
        rating: Int? = nil,
        isFavorite: Bool = false
    ) {
        self.stationCode = stationCode
        self.stationName = stationName
        self.dateVisited = dateVisited
        self.notes = notes
        self.rating = rating
        self._isFavorite = isFavorite
    }
}
// MARK: - Convenience Extensions
extension VisitedStation {
    /// Check if visited today
    var isVisitedToday: Bool {
        Calendar.current.isDateInToday(dateVisited)
    }
    
    /// Check if visited this week
    var isVisitedThisWeek: Bool {
        guard let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else {
            return false
        }
        return dateVisited >= weekAgo
    }
    
    /// Days since visit
    var daysSinceVisit: Int {
        Calendar.current.dateComponents([.day], from: dateVisited, to: Date()).day ?? 0
    }
}

