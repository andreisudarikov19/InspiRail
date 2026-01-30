//
//  RouteModels.swift
//  rnsapp
//
//  Created for Swift 6 Concurrency Compliance
//

import Foundation

// 1. Define the Top-Level Response
// Marked 'Sendable' to guarantee safe passage between background & main threads.
struct RouteResponse: Codable, Sendable {
    let trips: [Route]
}

// 2. Define the Route (formerly Trip)
struct Route: Codable, Identifiable, Sendable {
    // We create a local UUID for SwiftUI lists, ignored by JSONDecoder
    let id = UUID()
    
    let ctxReisnummer: String?
    let plannedDurationInMinutes: Int?
    let legs: [RouteLeg]
    let messages: [RouteMessage]?

    // Explicit keys to map API JSON to our Struct
    enum CodingKeys: String, CodingKey {
        case ctxReisnummer
        case plannedDurationInMinutes
        case legs
        case messages
    }
}

// 3. Define the Legs (Train, Bus, Walk parts)
struct RouteLeg: Codable, Identifiable, Sendable {
    let id = UUID()
    
    let name: String?
    let origin: RouteLocation
    let destination: RouteLocation
    let direction: String?
    
    enum CodingKeys: String, CodingKey {
        case name, origin, destination, direction
    }
}

// 4. Define Locations
struct RouteLocation: Codable, Sendable {
    let name: String
    let plannedDateTime: String?
}

// 5. Define Messages (Warnings/Disruptions)
struct RouteMessage: Codable, Identifiable, Sendable {
    let id = UUID()
    
    let head: String?
    let text: String?
    let type: String?
    
    enum CodingKeys: String, CodingKey {
        case head, text, type
    }
}
