//
//  NetworkManager.swift
//  InspiRail
//
//  Deprecated shim forwarding to BackendAPI/StationsRepository.
//

import Foundation
import OSLog

let networkLog = Logger(subsystem: "com.rnsapp", category: "network")

actor NetworkManager {
    static let shared = NetworkManager()
    private init() {}

    private let backend = BackendAPI()

    /// Deprecated: Use `StationsRepository` or `BackendAPI` directly.
    func fetch<T: Decodable>(from urlString: String, as type: T.Type) async throws -> T {
        networkLog.warning("Deprecated direct fetch used for: \(urlString, privacy: .public)")

        // Known mapping: stations endpoint
        if urlString.contains("/nsapp-stations/v3") {
            let stations = try await backend.getStations()
            if let typed = stations as? T {
                return typed
            } else {
                throw NetworkError.decodingError(NSError(domain: "NetworkManagerShim", code: -1, userInfo: [NSLocalizedDescriptionKey: "Type mismatch in shim. Expected \(T.self)"]))
            }
        }

        // Attempt to derive a relative path from the provided URL
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        let relativePath = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relativePath.isEmpty else {
            throw NetworkError.invalidURL
        }
        return try await backend.request(relativePath, as: T.self)
    }
}
