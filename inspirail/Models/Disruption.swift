//
//  Disruption.swift
//  rnsapp
//
//  Created by Andrei Sudarikov on 02/01/2026.
//
import Foundation

/// Represents a service disruption on a specific route.
struct Disruption: Codable, Identifiable, Sendable {
    let id: String
    let title: String
    let description: String?
    let isActive: Bool
    let start: Date?
    let end: Date?
    let impact: Impact?
    let alternativeTransport: AlternativeTransport?
    
    enum Impact: String, Codable, Sendable {
        case noImpact = "NO_IMPACT"
        case minor = "MINOR"
        case significant = "SIGNIFICANT"
        case major = "MAJOR"
    }
    
    struct AlternativeTransport: Codable, Sendable {
        let type: String?
        let description: String?
    }
    
    enum CodingKeys: String, CodingKey {
        case id, title, description, isActive, start, end, impact, alternativeTransport
    }
}
/// Response wrapper for disruptions API
struct DisruptionsResponse: Codable, Sendable {
    let payload: [Disruption]
}

