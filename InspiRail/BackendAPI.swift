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
    
    // MARK: - Refused Key
    
    /// The key NS last refused, while it is held back (#20). Loads with that
    /// key fail at once and send nothing, until the pause ends, another key
    /// is used or a key is saved. Keeps only a hash of the key.
    private(set) var keyRefusal: KeyRefusal?
    
    /// Forgets the refused key, so the next load sends the key, whatever it
    /// is. Settings calls it when a key is saved, even the one NS refused,
    /// since a refusal can pass (#20).
    func forgetKeyRefusal() {
        keyRefusal = nil
    }
    
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
        
        let response = try await request(url: url, as: StationResponse.self)
        
        // A station that can't be read is skipped, and the rest load (#20)
        for station in response.skipped {
            logger.warning("⚠️ Skipped station \(station.code ?? "without a code", privacy: .public): can't read \(station.field.isEmpty ? "the entry" : station.field, privacy: .public)")
        }
        guard !response.payload.isEmpty else {
            logger.error("❌ No station in the list could be read")
            reportFailure(.unreadableData)
            throw NetworkError.unreadableData
        }
        return response
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
    /// or 503, otherwise as long as `RetryPolicy.backoff` says. When the
    /// server asks for a wait longer than `longestRetryWait`, it fails at
    /// once. The key is read once, so every attempt sends the same one. A
    /// failure is reported once; a cancellation passes through unreported.
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
        
        // A key NS refused isn't sent again until the pause ends, it
        // changes or a key is saved (#20)
        if let keyRefusal {
            guard !keyRefusal.holds(for: apiKey, at: now()) else {
                logger.notice("Not sending the API key NS refused (\(String(describing: keyRefusal.reason), privacy: .public)) until the pause ends, it changes or a key is saved")
                throw keyRefusal.error
            }
            self.keyRefusal = nil
        }
        
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
                // Only a refusal of the key this load sent: a late success
                // for an old key leaves the refusal of a newer one (#20)
                if keyRefusal?.refuses(apiKey) == true {
                    keyRefusal = nil
                }
                return value
            case .failure(let error, let wait):
                switch error {
                case .keyRejected:
                    keyRefusal = KeyRefusal(.rejected, key: apiKey, at: now())
                case .forbidden:
                    keyRefusal = KeyRefusal(.forbidden, key: apiKey, at: now())
                default:
                    break
                }
                // A load whose task was cancelled ends as a cancellation,
                // whatever the attempt failed with, such as the request
                // URLSession cancelled for it (#20)
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
            let failure = failure(for: error)
            return .failure(failure, wait: RetryPolicy.isTransient(error.code) ? RetryPolicy.backoff(after: failure, attempt: attempt) : nil)
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
            let failure = failure(forStatus: status)
            let asked = RetryPolicy.retryAfter(httpResponse.value(forHTTPHeaderField: "Retry-After"), now: now())
            return .failure(failure, wait: asked ?? RetryPolicy.backoff(after: failure, attempt: attempt))
            
        case 501, 505, 511:
            // Another attempt can't help: NS doesn't offer the request (501)
            // or the HTTP version (505), or the network wants the user to
            // sign in, as a captive portal does (511) (#20)
            return .failure(failure(forStatus: status), wait: nil)
            
        case 500...599:
            let failure = failure(forStatus: status)
            return .failure(failure, wait: RetryPolicy.backoff(after: failure, attempt: attempt))
            
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
    /// this version can't use. A 511 means NS wasn't reached.
    private func failure(forStatus status: Int) -> NetworkError {
        switch status {
        case 401:
            return .keyRejected
        case 403:
            return .forbidden
        case 429:
            return .tooManyRequests
        case 511:
            // Network Authentication Required: the network, such as a captive
            // portal, answered instead of NS, and wants the user to sign in
            return .offline(.userAuthenticationRequired)
        case 500...599:
            return .serviceUnavailable(status: status)
        default:
            return .unreadableData
        }
    }
    
    /// The error a transport failure stands for (#20). A reply URLSession
    /// can't parse is unreadable data. Every other failure means NS can't be
    /// reached, so a failed name lookup or connection no longer reads as an
    /// NS server error. So does a request the system cancelled when no task
    /// asked it to stop, so the screen doesn't keep loading. When the load's
    /// own task was cancelled, the loop throws `CancellationError` instead.
    private func failure(for error: URLError) -> NetworkError {
        switch error.code {
        case .badServerResponse, .cannotParseResponse, .cannotDecodeContentData, .cannotDecodeRawData, .zeroByteResource:
            return .unreadableData
        default:
            return .offline(error.code)
        }
    }
    
    /// Reports a load that failed after the reply was read, such as a list
    /// with no Dutch station, once, as the API reports its own failures
    /// (#20).
    func report(_ failure: NetworkError) {
        reportFailure(failure)
    }
    
    /// Logs a failed load: once per load, not once per attempt (#20).
    nonisolated static func logFailure(_ error: NetworkError) {
        Logger(subsystem: AppConfiguration.subsystem, category: "backend")
            .error("❌ Station request failed: \(String(describing: error), privacy: .public)")
    }
}
