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
    
    init(stationCode: String, stationName: String, dateVisited: Date = .now) {
        self.stationCode = stationCode
        self.stationName = stationName
        self.dateVisited = dateVisited
    }
}
