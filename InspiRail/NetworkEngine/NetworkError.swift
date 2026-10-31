//
//  NetworkError.swift
//  InspiRail
//
//  Created by Andrei Sudarikov on 02/01/2026.
//

import Foundation

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case decodingError(Error)
    case serverError(Int)
    case unauthorized
    case rateLimited
    case timeout
    case noConnection
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .decodingError(let error):
            return "Data format error: \(error.localizedDescription)"
        case .serverError(let code):
            return "Server error (\(code))"
        case .unauthorized:
            return "Authentication failed"
        case .rateLimited:
            return "Too many requests"
        case .timeout:
            return "Request timed out"
        case .noConnection:
            return "No internet connection"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}
