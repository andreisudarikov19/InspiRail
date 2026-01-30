//
//  Disruption.swift
//  rnsapp
//
//  Created by Andrei Sudarikov on 02/01/2026.
//
import Foundation

/// Represents a service disruption on a specific route.
struct Disruption: Codable, Identifiable {
    let id: String
    let title: String
    let isActive: Bool
    
    // We can add more fields later as we explore the API response
}
