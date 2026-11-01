//
//  VisitedStation.swift
//  InspiRail
//
//  Created by Andrei Sudarikov on 03/01/2026.
//
import Foundation
import SwiftData

/// A visit in the logbook.
///
/// The stored fields have changed once: 1.3.0 added the optional `notes`,
/// `rating` and `_isFavorite`, which SwiftData migrates by itself. The first
/// change it can't migrate by itself must bring in versioned schemas (a
/// `VersionedSchema` per shape and a `SchemaMigrationPlan`), with this shape
/// as V1 (#17).
@Model
final class VisitedStation {
    @Attribute(.unique) var stationCode: String // Unique ID (e.g., "UT")
    var stationName: String
    var dateVisited: Date
    
    // Optional: Store additional metadata
    var notes: String?
    var rating: Int? // 1-5 star rating
    
    // Optional, so that stores from before 1.3.0 open. Nothing reads
    // `notes`, `rating` or `_isFavorite`, but they are stored: removing them
    // changes the schema.
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
