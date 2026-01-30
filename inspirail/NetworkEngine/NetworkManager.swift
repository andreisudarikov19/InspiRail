//
//  NetworkManager.swift
//  rnsapp
//
//  Created by Andrei Sudarikov on 02/01/2026.
//

import Foundation

actor NetworkManager {
    
    static let shared = NetworkManager()
    private init() {}
    
    private let apiKey = "dbd719b0ae324a8e8d7dc673e013da25"
    
    func fetch<T: Decodable>(from urlString: String, as type: T.Type) async throws -> T {
        
        guard let url = URL(string: urlString) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.noData
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.serverError(httpResponse.statusCode)
        }
        
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(T.self, from: data)
        } catch {
            print("Decoding Error: \(error)")
            throw NetworkError.decodingError(error)
        }
    }
}
