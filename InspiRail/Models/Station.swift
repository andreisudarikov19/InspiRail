//
//  Station.swift
//  InspiRail
//
//  Decodes the NS stations (v3) response
//

import Foundation
import CoreLocation

struct StationResponse: Codable {
    let payload: [Station]
}

struct Station: Codable, Identifiable {
    // The "id" object in JSON maps to "identifiers" here
    var id: String { identifiers.code }
    
    let identifiers: StationIdentifiers
    let stationType: String
    let names: StationNames
    let location: StationLocation
    let country: String
    
    // --- Rich Data Fields (Matched to English API v3) ---
    let tracks: [String]?
    let hasKnownFacilities: Bool?
    let hasTravelAssistance: Bool?
    
    enum CodingKeys: String, CodingKey {
        case identifiers = "id"
        case stationType
        case names
        case location
        case country
        case tracks
        case hasKnownFacilities
        case hasTravelAssistance
    }
}

// 1. Identifiers
struct StationIdentifiers: Codable {
    let code: String
    let uicCode: String?
}

// 2. Names (Synonyms are nested here now)
struct StationNames: Codable {
    let long: String
    let medium: String
    let short: String
    let synonyms: [String]?
}

// 3. Location
struct StationLocation: Codable {
    let lat: Double
    let lng: Double
}

// 4. Extensions
extension Station {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: location.lat, longitude: location.lng)
    }
    
    var readableType: String {
        // The default fallback works perfectly for English enums like "LOCAL_TRAIN_STATION"
        // "LOCAL_TRAIN_STATION" -> "Local Train Station"
        return stationType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
