//
//  Station.swift
//  InspiRail
//
//  Decodes the NS stations (v3) response
//

import Foundation
import CoreLocation

/// The stations (v3) response. Stations are decoded one at a time, so one
/// that can't be read is skipped instead of failing the whole list (#20).
/// The types are nonisolated, so the API actor can decode them.
nonisolated struct StationResponse: Decodable {
    let payload: [Station]
    /// The entries that couldn't be read as stations, in list order.
    let skipped: [SkippedStation]
    
    private enum CodingKeys: String, CodingKey {
        case payload
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var list = try container.nestedUnkeyedContainer(forKey: .payload)
        var stations: [Station] = []
        var skipped: [SkippedStation] = []
        while !list.isAtEnd {
            if try list.decodeNil() {
                skipped.append(SkippedStation(code: nil, field: ""))
                continue
            }
            do {
                stations.append(try list.decode(Station.self))
            } catch {
                // A failed decode leaves the list where it was: read the
                // entry again for its code, which also moves past it.
                let code = try list.decode(StationCode.self).code
                let field = SkippedStation.field(of: error, below: list.codingPath.count + 1)
                skipped.append(SkippedStation(code: code, field: field))
            }
        }
        self.payload = stations
        self.skipped = skipped
    }
}

/// An entry in the station list that couldn't be read as a station (#20).
nonisolated struct SkippedStation: Sendable, Equatable {
    /// Its `id.code`, when it has a readable one.
    let code: String?
    /// The field that couldn't be read, such as `location` or `names.short`.
    /// Empty when the entry isn't a station at all, such as `null`.
    let field: String
    
    /// The field `error` names, below the first `depth` keys of its path,
    /// which lead to the entry.
    static func field(of error: Error, below depth: Int) -> String {
        guard let error = error as? DecodingError else {
            return ""
        }
        let path: [CodingKey]
        switch error {
        case .keyNotFound(let key, let context):
            path = context.codingPath + [key]
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            path = context.codingPath
        @unknown default:
            path = []
        }
        return path.dropFirst(depth).map(\.stringValue).joined(separator: ".")
    }
}

/// The code of an entry that couldn't be read, if it has a readable one.
/// Never fails, so it can always move the list past the entry.
nonisolated private struct StationCode: Decodable {
    let code: String?
    
    private enum CodingKeys: String, CodingKey {
        case id, code
    }
    
    init(from decoder: Decoder) {
        let id = try? decoder.container(keyedBy: CodingKeys.self).nestedContainer(keyedBy: CodingKeys.self, forKey: .id)
        code = try? id?.decode(String.self, forKey: .code)
    }
}

nonisolated struct Station: Codable, Identifiable {
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
nonisolated struct StationIdentifiers: Codable {
    let code: String
    let uicCode: String?
}

// 2. Names (Synonyms are nested here now)
nonisolated struct StationNames: Codable {
    let long: String
    /// Not shown anywhere, so a station without it still loads (#20).
    let medium: String?
    let short: String
    let synonyms: [String]?
}

// 3. Location
nonisolated struct StationLocation: Codable {
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
