//
//  NetworkError.swift
//  rnsapp
//
//  Created by Andrei Sudarikov on 02/01/2026.
//

import Foundation

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case noData
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
        case .noData:
            return "No data received"
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
    
    var failureReason: String? {
        switch self {
        case .invalidURL:
            return "The requested resource could not be found."
        case .noData:
            return "The server did not return any data."
        case .decodingError:
            return "The data received was in an unexpected format."
        case .serverError(let code) where code == 401:
            return "Your API key may be invalid or expired."
        case .serverError(let code) where code == 403:
            return "Access to this resource is forbidden."
        case .serverError(let code) where code == 429:
            return "You have made too many requests. Please wait before trying again."
        case .serverError(let code) where code >= 500:
            return "The server is experiencing issues."
        case .serverError:
            return "The server returned an unexpected response."
        case .unauthorized:
            return "Check your API credentials in the app settings."
        case .rateLimited:
            return "The API rate limit has been exceeded."
        case .timeout:
            return "The server took too long to respond."
        case .noConnection:
            return "Please check your internet connection and try again."
        case .unknown:
            return "Something went wrong."
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidURL:
            return "Please try again or contact support."
        case .noData:
            return "Try again in a few moments."
        case .decodingError:
            return "The app may need an update. Check the App Store."
        case .serverError(let code) where code == 401:
            return "Verify your API key configuration."
        case .serverError(let code) where code >= 500:
            return "Please try again later."
        case .serverError:
            return "Try again or contact support if the problem persists."
        case .unauthorized:
            return "Re-authenticate or contact support."
        case .rateLimited:
            return "Wait a few minutes before trying again."
        case .timeout:
            return "Check your connection and try again."
        case .noConnection:
            return "Connect to WiFi or cellular data."
        case .unknown:
            return "Try again or restart the app."
        }
    }
    
    /// Whether this error should trigger a retry
    var isRetryable: Bool {
        switch self {
        case .timeout, .noConnection:
            return true
        case .serverError(let code):
            return code >= 500
        default:
            return false
        }
    }
}
