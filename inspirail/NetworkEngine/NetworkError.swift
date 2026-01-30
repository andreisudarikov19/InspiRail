//
//  NetworkError.swift
//  rnsapp
//
//  Created by Andrei Sudarikov on 02/01/2026.
//
import Foundation

enum NetworkError: Error {
    case invalidURL
    case noData
    case decodingError(Error)
    case serverError(Int) // Captures HTTP status codes like 401 or 404
    case unknown(Error)
    
    var localizedDescription: String {
        switch self {
        case .invalidURL: return "The URL provided was invalid."
        case .noData: return "The server returned no data."
        case .decodingError(let error): return "Failed to decode JSON: \(error.localizedDescription)"
        case .serverError(let code): return "Server returned an error code: \(code)."
        case .unknown(let error): return error.localizedDescription
        }
    }
}
