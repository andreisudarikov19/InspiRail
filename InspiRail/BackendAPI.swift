//
//  BackendAPI.swift
//  InspiRail
//
//  Core backend API layer with security, caching, and error handling
//

import Foundation
import OSLog

/// Main backend API client with security and performance optimizations
actor BackendAPI {
    // MARK: - Configuration
    
    private let baseURL: String
    private let maxAttempts: Int
    private let longestRetryWait: TimeInterval
    private let enableNetworkLogging: Bool
    private let enableDetailedLogging: Bool
    private let userAgent: String
    private let keyProvider: APIKeyProvider
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void
    private let reportFailure: @Sendable (NetworkError) -> Void

    private let logger = Logger(subsystem: AppConfiguration.subsystem, category: "backend")
    
    /// - Parameters:
    ///   - keyProvider: Finds the API key for each request. Nil means the
    ///     app's: the Keychain and, in Debug builds, the launch environment.
    ///   - sessionConfiguration: The configuration the session starts from.
    ///     The API applies its own settings to it. Tests pass one whose
    ///     protocol classes answer every request.
    ///   - now: The clock a `Retry-After` date is measured by.
    ///   - sleep: Waits that many seconds between attempts. Tests pass one
    ///     that returns at once.
    ///   - reportFailure: Told once about each load that fails. By default
    ///     it logs the failure.
    init(
        keyProvider: APIKeyProvider? = nil,
        sessionConfiguration: URLSessionConfiguration = .default,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        reportFailure: @escaping @Sendable (NetworkError) -> Void = { BackendAPI.logFailure($0) }
    ) {
        // Access configuration values during initialization
        self.baseURL = AppConfiguration.API.baseURL
        self.maxAttempts = AppConfiguration.API.maxAttempts
        self.longestRetryWait = AppConfiguration.API.longestRetryWait
        self.enableNetworkLogging = AppConfiguration.Features.enableNetworkLogging
        self.enableDetailedLogging = AppConfiguration.Features.enableDetailedLogging
        self.userAgent = AppConfiguration.userAgent

        #if DEBUG
        let allowsEnvironmentOverride = true
        #else
        let allowsEnvironmentOverride = false
        #endif
        self.keyProvider = keyProvider ?? APIKeyProvider(
            keychain: KeychainManager.shared,
            environment: ProcessInfo.processInfo.environment,
            allowsEnvironmentOverride: allowsEnvironmentOverride
        )
        self.now = now
        self.sleep = sleep
        self.reportFailure = reportFailure
        self.session = Self.makeSession(
            configuration: sessionConfiguration,
            timeout: AppConfiguration.API.timeout,
            resourceTimeout: AppConfiguration.API.resourceTimeout
        )
    }
    
    // MARK: - Session Configuration
    
    /// The API's one session, created with it. The app creates one API, so
    /// every request shares this session and its connections (#18).
    /// Visible to the module for tests only: app code goes through the API's
    /// methods, which read the key, retry and hold back a refused key.
    let session: URLSession
    
    private static func makeSession(
        configuration config: URLSessionConfiguration,
        timeout: TimeInterval,
        resourceTimeout: TimeInterval
    ) -> URLSession {
        // Performance optimizations
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = resourceTimeout
        config.waitsForConnectivity = true
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        
        // Cache policy: requests ignore cached responses, so the session
        // keeps no URLCache. The station store keeps the list (#18).
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        
        // HTTP settings
        config.httpMaximumConnectionsPerHost = 4
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        
        return URLSession(configuration: config)
    }
    
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
    
    // MARK: - Private Request Logic
    
    /// One attempt's result: the decoded reply, or the failure with the wait
    /// before the next attempt, nil when another attempt can't help.
    private enum Outcome<T> {
        case success(T)
        case failure(NetworkError, wait: TimeInterval?)
    }
    
    /// Sends the request, and tries again what a retry can fix (#20): at most
    /// `maxAttempts` attempts, waiting as long as `Retry-After` asks on a 429
    /// or 503, otherwise 1 s and then 2 s. When the server asks for a wait
    /// longer than `longestRetryWait`, it fails at once. The key is read once,
    /// so every attempt sends the same one. A failure is reported once; a
    /// cancellation passes through unreported.
    private func request<T: Decodable>(url: URL, as type: T.Type) async throws -> T {
        do {
            return try await sendWithRetries(url: url, as: type)
        } catch let error as NetworkError {
            reportFailure(error)
            throw error
        }
    }
    
    private func sendWithRetries<T: Decodable>(url: URL, as type: T.Type) async throws -> T {
        // Build request
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        
        // Security: Add API key from secure storage
        let apiKey = try await keyProvider.currentKey()
        urlRequest.setValue(apiKey, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        
        // Headers
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        urlRequest.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        
        if enableNetworkLogging {
            logger.debug("🌐 Request: \(url.path, privacy: .public)")
            logger.debug("   Method: \(urlRequest.httpMethod ?? "UNKNOWN")")
            logger.debug("   Has API Key header: \(urlRequest.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") != nil)")
        }
        
        var attempt = 1
        while true {
            try Task.checkCancellation()
            switch try await send(urlRequest, as: type, attempt: attempt) {
            case .success(let value):
                return value
            case .failure(let error, let wait):
                try Task.checkCancellation()
                guard attempt < maxAttempts, let wait else {
                    throw error
                }
                guard wait <= longestRetryWait else {
                    logger.notice("NS asked to wait \(wait)s, longer than \(self.longestRetryWait)s: not retrying")
                    throw error
                }
                logger.notice("Attempt \(attempt) failed (\(String(describing: error), privacy: .public)): retrying in \(wait)s")
                try await sleep(wait)
                attempt += 1
            }
        }
    }
    
    /// One attempt: sends the request and maps what comes back.
    private func send<T: Decodable>(_ urlRequest: URLRequest, as type: T.Type, attempt: Int) async throws -> Outcome<T> {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            let failure = try failure(for: error)
            return .failure(failure, wait: RetryPolicy.isTransient(error.code) ? RetryPolicy.backoff(afterAttempt: attempt) : nil)
        } catch let error as CancellationError {
            // A cancellation passes through unchanged, and callers ignore it (#20).
            throw error
        } catch {
            return .failure(.offline(.unknown), wait: nil)
        }
        
        // Handle HTTP response
        guard let httpResponse = response as? HTTPURLResponse else {
            return .failure(.unreadableData, wait: nil)
        }
        
        logger.debug("📥 Response: \(httpResponse.statusCode) from \(urlRequest.url?.path ?? "", privacy: .public)")
        
        // Log response details in debug mode
        if enableDetailedLogging {
            if let headers = httpResponse.allHeaderFields as? [String: String] {
                logger.debug("Response headers: \(headers, privacy: .private)")
            }
        }
        
        // Handle status codes
        let status = httpResponse.statusCode
        switch status {
        case 200...299:
            // Success - decode response
            return .success(try decodeResponse(data: data, type: type))
            
        case 401, 403:
            logger.error("❌ Authentication failed with status \(status)")
            logger.error("   This usually means:")
            if status == 401 {
                if keyProvider.usesEnvironmentKey {
                    logger.error("   - The API key from NS_API_KEY is invalid or expired: change or remove it in the launch environment (it overrides Settings)")
                } else {
                    logger.error("   - The API key is missing, invalid or expired: check it in Settings")
                }
            } else {
                logger.error("   - The API key is over its usage quota, or isn't allowed to use this API")
            }
            
            #if DEBUG
            // In debug, log response body for more details
            if let responseText = String(data: data, encoding: .utf8) {
                logger.debug("Response body: \(responseText, privacy: .private)")
            }
            #endif
            
            return .failure(failure(forStatus: status), wait: nil)
            
        case 429, 503:
            // Throttled or unavailable: wait as long as the server asks
            let asked = RetryPolicy.retryAfter(httpResponse.value(forHTTPHeaderField: "Retry-After"), now: now())
            return .failure(failure(forStatus: status), wait: asked ?? RetryPolicy.backoff(afterAttempt: attempt))
            
        case 500...599:
            return .failure(failure(forStatus: status), wait: RetryPolicy.backoff(afterAttempt: attempt))
            
        default:
            return .failure(failure(forStatus: status), wait: nil)
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
            
            throw NetworkError.unreadableData
        }
    }
    
    /// The error a status that isn't a success stands for (#20). Any status
    /// the app doesn't expect, such as 404, means NS answered with something
    /// this version can't use.
    private func failure(forStatus status: Int) -> NetworkError {
        switch status {
        case 401:
            return .keyRejected
        case 403:
            return .forbidden
        case 429:
            return .tooManyRequests
        case 500...599:
            return .serviceUnavailable(status: status)
        default:
            return .unreadableData
        }
    }
    
    /// The error a transport failure stands for (#20). A cancellation isn't
    /// one: it is thrown as `CancellationError`. A reply URLSession can't
    /// parse is unreadable data. Every other failure means NS can't be
    /// reached, so a failed name lookup or connection no longer reads as an
    /// NS server error.
    private func failure(for error: URLError) throws -> NetworkError {
        switch error.code {
        case .cancelled:
            throw CancellationError()
        case .badServerResponse, .cannotParseResponse, .cannotDecodeContentData, .cannotDecodeRawData, .zeroByteResource:
            return .unreadableData
        default:
            return .offline(error.code)
        }
    }
    
    /// Logs a failed load: once per load, not once per attempt (#20).
    nonisolated static func logFailure(_ error: NetworkError) {
        Logger(subsystem: AppConfiguration.subsystem, category: "backend")
            .error("❌ Station request failed: \(String(describing: error), privacy: .public)")
    }
}
