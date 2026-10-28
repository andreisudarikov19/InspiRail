//
//  BackendAPI.swift
//  rnsapp
//
//  Core backend API layer with security, caching, and error handling
//

import Foundation
import OSLog

/// Main backend API client with security and performance optimizations
actor BackendAPI {
    // MARK: - Configuration
    
    private let baseURL: String
    private let timeout: TimeInterval
    private let resourceTimeout: TimeInterval
    private let memoryCacheSize: Int
    private let diskCacheSize: Int
    private let maxRequestsPerMinute: Int
    private let maxRetries: Int
    private let enableNetworkLogging: Bool
    private let enableDetailedLogging: Bool
    private let userAgent: String
    
    private let logger = Logger(subsystem: "com.rnsapp", category: "backend")
    
    init() {
        // Access configuration values during initialization
        self.baseURL = AppConfiguration.API.baseURL
        self.timeout = AppConfiguration.API.timeout
        self.resourceTimeout = AppConfiguration.API.resourceTimeout
        self.memoryCacheSize = AppConfiguration.API.memoryCacheSize
        self.diskCacheSize = AppConfiguration.API.diskCacheSize
        self.maxRequestsPerMinute = AppConfiguration.API.maxRequestsPerMinute
        self.maxRetries = AppConfiguration.API.maxRetries
        self.enableNetworkLogging = AppConfiguration.Features.enableNetworkLogging
        self.enableDetailedLogging = AppConfiguration.Features.enableDetailedLogging
        self.userAgent = AppConfiguration.userAgent
    }
    
    // MARK: - Session Configuration
    
    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.default
        
        // Performance optimizations
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = resourceTimeout
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        
        // Cache policy
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = URLCache(
            memoryCapacity: memoryCacheSize,
            diskCapacity: diskCacheSize
        )
        
        // HTTP settings
        config.httpMaximumConnectionsPerHost = 4
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        
        return URLSession(configuration: config)
    }()
    
    // MARK: - Rate Limiting
    
    private var requestTimestamps: [Date] = []
    
    // MARK: - Public API Methods
    
    /// Fetch all stations from the NS API
    func getStations(includeNonPlannable: Bool = false) async throws -> StationResponse {
        let endpoint = "/nsapp-stations/v3"
        var components = URLComponents(string: baseURL + endpoint)
        components?.queryItems = [
            URLQueryItem(name: "includeNonPlannableStations", value: "\(includeNonPlannable)")
        ]
        
        guard let url = components?.url else {
            throw NetworkError.invalidURL
        }
        
        return try await request(url: url, as: StationResponse.self)
    }
    
    /// Generic request method for future endpoints
    func request<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        let url = URL(string: baseURL + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        
        guard let validURL = url else {
            throw NetworkError.invalidURL
        }
        
        return try await request(url: validURL, as: type)
    }
    
    // MARK: - Private Request Logic
    
    private func request<T: Decodable>(url: URL, as type: T.Type, retryCount: Int = 0) async throws -> T {
        let startTime = Date()
        
        // Rate limiting check
        try await checkRateLimit()
        
        // Build request
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        
        // Security: Add API key from secure storage
        let apiKey = try await getAPIKey()
        urlRequest.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        
        // Headers
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        
        if enableNetworkLogging {
            logger.debug("🌐 Request: \(url.path, privacy: .public)")
            logger.debug("   Method: \(urlRequest.httpMethod ?? "UNKNOWN")")
            logger.debug("   Has API Key header: \(urlRequest.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") != nil)")
            
            #if DEBUG
            // In debug builds, show first/last 4 chars of API key for verification
            if let key = urlRequest.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key"), key.count > 8 {
                let preview = "\(key.prefix(4))...\(key.suffix(4))"
                logger.debug("   API Key preview: \(preview, privacy: .public)")
            }
            #endif
        }
        
        do {
            let (data, response) = try await session.data(for: urlRequest)
            
            // Handle HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.unknown(NSError(domain: "BackendAPI", code: -1))
            }
            
            logger.debug("📥 Response: \(httpResponse.statusCode) from \(url.path, privacy: .public)")
            
            // Log response details in debug mode
            if enableDetailedLogging {
                if let headers = httpResponse.allHeaderFields as? [String: String] {
                    logger.debug("Response headers: \(headers, privacy: .private)")
                }
            }
            
            // Handle status codes
            switch httpResponse.statusCode {
            case 200...299:
                // Success - decode response
                let result = try decodeResponse(data: data, type: type)
                
                // Track successful request
                let duration = Date().timeIntervalSince(startTime)
                await AnalyticsManager.shared.track(.apiRequestSucceeded(endpoint: url.path, duration: duration))
                
                return result
                
            case 401, 403:
                logger.error("❌ Authentication failed with status \(httpResponse.statusCode)")
                logger.error("   This usually means:")
                if httpResponse.statusCode == 401 {
                    logger.error("   - API key is missing, invalid, or expired")
                    logger.error("   - Check that your NS_API_KEY in Secrets.xcconfig is correct")
                } else {
                    logger.error("   - API key is valid but doesn't have permission for this endpoint")
                }
                
                #if DEBUG
                // In debug, log response body for more details
                if let responseText = String(data: data, encoding: .utf8) {
                    logger.debug("Response body: \(responseText, privacy: .private)")
                }
                #endif
                
                throw NetworkError.unauthorized
                
            case 429:
                // Rate limited - implement exponential backoff
                if retryCount < maxRetries {
                    let delay = pow(2.0, Double(retryCount)) * 1.0 // 1s, 2s, 4s
                    logger.warning("⚠️ Rate limited. Retrying in \(delay)s...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await request(url: url, as: type, retryCount: retryCount + 1)
                } else {
                    throw NetworkError.rateLimited
                }
                
            case 500...599:
                // Server error - retry if appropriate
                if retryCount < maxRetries - 1 {
                    let delay = pow(2.0, Double(retryCount)) * 0.5
                    logger.warning("⚠️ Server error \(httpResponse.statusCode). Retrying in \(delay)s...")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    return try await request(url: url, as: type, retryCount: retryCount + 1)
                } else {
                    throw NetworkError.serverError(httpResponse.statusCode)
                }
                
            default:
                throw NetworkError.serverError(httpResponse.statusCode)
            }
            
        } catch let error as NetworkError {
            // Track failed request
            await AnalyticsManager.shared.track(.apiRequestFailed(endpoint: url.path, error: error.localizedDescription))
            throw error
        } catch let error as URLError {
            let networkError = mapURLError(error)
            await AnalyticsManager.shared.track(.apiRequestFailed(endpoint: url.path, error: networkError.localizedDescription))
            throw networkError
        } catch {
            await AnalyticsManager.shared.track(.apiRequestFailed(endpoint: url.path, error: error.localizedDescription))
            throw NetworkError.unknown(error)
        }
    }
    
    // MARK: - Helper Methods
    
    private func decodeResponse<T: Decodable>(data: Data, type: T.Type) throws -> T {
        let decoder = JSONDecoder()
        
        // Configure decoder for snake_case if needed
        // decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            let decoded = try decoder.decode(T.self, from: data)
            return decoded
        } catch {
            logger.error("❌ Decoding error: \(error.localizedDescription)")
            
            // Log raw data for debugging (only in debug builds)
            #if DEBUG
            if let jsonString = String(data: data, encoding: .utf8) {
                logger.debug("Raw response: \(jsonString, privacy: .private)")
            }
            #endif
            
            throw NetworkError.decodingError(error)
        }
    }
    
    private func checkRateLimit() async throws {
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)
        
        // Remove old timestamps
        requestTimestamps = requestTimestamps.filter { $0 > oneMinuteAgo }
        
        // Check if we're over the limit
        if requestTimestamps.count >= maxRequestsPerMinute {
            logger.warning("⚠️ Rate limit reached. Waiting...")
            // Wait for the oldest request to expire
            if let oldest = requestTimestamps.first {
                let waitTime = 60 - now.timeIntervalSince(oldest)
                if waitTime > 0 {
                    try await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
                }
            }
        }
        
        // Record this request
        requestTimestamps.append(now)
    }
    
    private func mapURLError(_ error: URLError) -> NetworkError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return .noConnection
        case .timedOut:
            return .timeout
        case .cannotFindHost, .cannotConnectToHost:
            return .serverError(503)
        default:
            return .unknown(error)
        }
    }
    
    // MARK: - API Key Management
    
    /// Retrieves the API key from secure storage
    /// Priority: Keychain > Info.plist > Environment (Debug only)
    private func getAPIKey() async throws -> String {
        // 1. Try to get from Keychain (most secure, used after first launch)
        do {
            let keychainKey = try await KeychainManager.shared.getAPIKey()
            logger.debug("🔐 Using API key from Keychain")
            return keychainKey
        } catch KeychainError.notFound {
            // Expected on first launch - continue to fallback options
            logger.debug("ℹ️ No key in Keychain yet, checking other sources...")
        } catch {
            // Unexpected keychain error - log but continue to fallback
            logger.warning("⚠️ Keychain error: \(error.localizedDescription). Trying fallback sources...")
        }
        
        // 2. Try to get from Info.plist (embedded at build time from Secrets.xcconfig)
        if let infoPlistKey = Bundle.main.object(forInfoDictionaryKey: "NS_API_KEY") as? String,
           !infoPlistKey.isEmpty,
           infoPlistKey != "$(NS_API_KEY)",  // Check for unexpanded variable
           infoPlistKey != "YOUR_API_KEY_HERE" { // Check for placeholder
            
            logger.info("✅ Found API key in Info.plist, migrating to Keychain...")
            
            // Store in keychain for future use (first launch migration)
            do {
                try await KeychainManager.shared.saveAPIKey(infoPlistKey)
                logger.info("✅ API key successfully migrated to Keychain")
            } catch {
                logger.error("❌ Failed to save API key to Keychain: \(error.localizedDescription)")
                // Continue anyway - we can still use the key from Info.plist
            }
            
            return infoPlistKey
        }
        
        // 3. Fallback for debug builds: check environment variables
        #if DEBUG
        if let envKey = ProcessInfo.processInfo.environment["NS_API_KEY"],
           !envKey.isEmpty {
            logger.warning("⚠️ Using API key from environment variable (DEBUG only)")
            
            // Try to save to keychain for next time
            try? await KeychainManager.shared.saveAPIKey(envKey)
            return envKey
        }
        #endif
        
        // 4. No API key found anywhere
        logger.error("❌ No API key found in any location:")
        logger.error("   - Not in Keychain")
        logger.error("   - Not in Info.plist (NS_API_KEY)")
        logger.error("   - Not in environment variables")
        logger.error("📖 See API_SECURITY_SETUP.md for configuration instructions")
        
        throw NetworkError.unauthorized
    }
}
