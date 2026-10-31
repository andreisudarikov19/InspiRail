//
//  VisitedStation.swift
//  InspiRail
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
    
    // Optional to support migration from older versions. Nothing reads
    // `notes`, `rating` or `_isFavorite`, but they are part of the stored
    // schema: they go only with a versioned schema (#17).
    private var _isFavorite: Bool?
    
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
