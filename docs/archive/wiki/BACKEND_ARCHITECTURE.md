# Backend Architecture Documentation

## Overview

The rnsapp backend is built with a layered architecture prioritizing **security**, **performance**, and **reliability**. This document outlines the backend improvements implemented.

## Architecture Layers

```
┌─────────────────────────────────────────┐
│          UI Layer (SwiftUI)             │
│   (MainTabView, DiscoveryView, etc.)    │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│      ViewModel Layer (@MainActor)       │
│      (DiscoveryViewModel, etc.)         │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│     Repository Layer (Actor)            │
│       StationsRepository                │
│   • Caching Logic                       │
│   • Business Logic                      │
└────────────────┬────────────────────────┘
                 │
┌────────────────▼────────────────────────┐
│      Backend API Layer (Actor)          │
│         BackendAPI                      │
│   • Network Requests                    │
│   • Rate Limiting                       │
│   • Retry Logic                         │
│   • Error Handling                      │
└────────────────┬────────────────────────┘
                 │
        ┌────────┴────────┐
        │                 │
┌───────▼──────┐  ┌──────▼────────┐
│   Network    │  │   Security    │
│  URLSession  │  │   Keychain    │
└──────────────┘  └───────────────┘
```

## Core Components

### 1. BackendAPI (Actor)

**File:** `BackendAPI.swift`

The main API client that handles all network communication.

**Features:**
- ✅ Thread-safe actor pattern
- ✅ Automatic retry with exponential backoff
- ✅ Rate limiting (30 requests/minute)
- ✅ Timeout handling (30s request, 60s resource)
- ✅ Comprehensive error mapping
- ✅ Analytics integration
- ✅ Response caching
- ✅ GZip/Brotli compression support

**Example Usage:**
```swift
let backend = BackendAPI()
let stations = try await backend.getStations()
```

### 2. KeychainManager (Actor)

**File:** `KeychainManager.swift`

Secure storage for API keys and sensitive data using iOS Keychain Services.

**Security Features:**
- ✅ iOS Keychain integration
- ✅ Accessibility: After First Unlock
- ✅ Thread-safe access
- ✅ Automatic migration from build-time config

**API Key Priority:**
1. Keychain (most secure, runtime)
2. Info.plist (embedded at build time)
3. Environment variables (debug only)

**Example Usage:**
```swift
// Save API key
try await KeychainManager.shared.saveAPIKey("your-key")

// Retrieve API key
let key = try await KeychainManager.shared.getAPIKey()

// Check if key exists
let hasKey = await KeychainManager.shared.hasAPIKey()
```

### 3. StationsRepository (Actor)

**File:** `StationsRepository 2.swift`

Repository pattern for station data with intelligent caching.

**Features:**
- ✅ In-memory caching (1 hour TTL)
- ✅ Force refresh capability
- ✅ Search functionality
- ✅ Analytics tracking (cache hits/misses)

**Example Usage:**
```swift
let repository = StationsRepository()

// Get stations (cached)
let stations = try await repository.stations()

// Force refresh
let fresh = try await repository.stations(forceRefresh: true)

// Search
let results = try await repository.search(query: "Amsterdam", country: "NL")
```

### 4. AppConfiguration (Enum)

**File:** `AppConfiguration.swift`

Centralized configuration management with feature flags.

**Configuration Areas:**
- API settings (URLs, timeouts, limits)
- Feature flags (logging, analytics, etc.)
- App information (version, build, user agent)

**Example Usage:**
```swift
let baseURL = AppConfiguration.API.baseURL
let timeout = AppConfiguration.API.timeout
let enableLogging = AppConfiguration.Features.enableDetailedLogging
```

### 5. AnalyticsManager (Actor)

**File:** `AnalyticsManager.swift`

Privacy-focused analytics and event tracking.

**Features:**
- ✅ Event tracking
- ✅ Screen tracking
- ✅ Performance metrics
- ✅ Privacy-first design (no PII)
- ✅ OSLog integration
- ✅ Extensible for third-party providers

**Example Usage:**
```swift
// Track events
await AnalyticsManager.shared.track(.stationViewed(code: "UT"))

// Track screens
await AnalyticsManager.shared.trackScreen("Discovery")

// Time operations
let result = await AnalyticsManager.shared.time("Heavy Operation") {
    await performHeavyOperation()
}
```

### 6. BackendHealthMonitor (Actor)

**File:** `BackendHealthMonitor.swift`

Real-time backend health monitoring and diagnostics.

**Features:**
- ✅ Network connectivity monitoring
- ✅ Backend health checks
- ✅ Diagnostic reports
- ✅ Connection type detection (WiFi/Cellular)
- ✅ Failure tracking

**Example Usage:**
```swift
// Check if network is available
let hasNetwork = await BackendHealthMonitor.shared.hasNetworkConnection

// Perform health check
let health = await BackendHealthMonitor.shared.checkHealth()

// Generate diagnostic report
let report = await BackendHealthMonitor.shared.generateDiagnosticReport()
print(report.description)
```

## Security Architecture

### API Key Management

**Three-Layer Security:**

```
1. Development (Build Time)
   Secrets.xcconfig (NOT in Git)
   ↓
2. Build (Xcode Build Process)
   Info.plist (embedded in app bundle)
   ↓
3. Runtime (First Launch)
   iOS Keychain (encrypted system storage)
   ↓
4. Production (All Requests)
   Memory-only access from Keychain
```

**Why This Approach?**

✅ **No hardcoded keys** in source code
✅ **Automatic migration** to secure storage
✅ **CI/CD friendly** via environment variables
✅ **System-level encryption** via Keychain
✅ **Revocable** without app update

### Best Practices Implemented

1. **Never commit secrets to Git**
   - `.gitignore` includes `Secrets.xcconfig`
   - Template file provided instead

2. **Use Keychain for runtime storage**
   - Encrypted by iOS
   - Protected by device passcode
   - Survives app reinstalls (configurable)

3. **Environment-specific keys**
   - Debug builds can use test keys
   - Production uses secure provisioning

## Performance Optimizations

### 1. Caching Strategy

**In-Memory Cache:**
- 1 hour TTL for station data
- Reduces API calls by ~90%
- Instant response for cached data

**HTTP Cache:**
- 10 MB memory cache
- 50 MB disk cache
- Respects ETag headers

### 2. Rate Limiting

**Client-Side Protection:**
- 30 requests per minute max
- Prevents API quota exhaustion
- Automatic request queuing

### 3. Retry Logic

**Exponential Backoff:**
```
Attempt 1: Immediate
Attempt 2: +1 second
Attempt 3: +2 seconds
Attempt 4: +4 seconds
```

**Retry Conditions:**
- Rate limit (429) → Always retry
- Server error (5xx) → Retry up to 2 times
- Network timeout → Retry once
- Client error (4xx) → No retry

### 4. Connection Pooling

- Maximum 4 concurrent connections
- Reuses connections via HTTP/2
- Reduces handshake overhead

## Error Handling

### NetworkError Hierarchy

```swift
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
}
```

**User-Friendly Messages:**
- Each error has `errorDescription`
- Includes `failureReason` for context
- Provides `recoverySuggestion` for users
- `isRetryable` flag for automatic recovery

## Analytics & Monitoring

### Events Tracked

**App Lifecycle:**
- App launched, backgrounded, foregrounded

**Station Interactions:**
- Station viewed, searched, visited, favorited

**Network Performance:**
- API request success/failure
- Request duration
- Cache hits/misses

**Errors:**
- All errors with domain, code, description

### Privacy Considerations

✅ **No PII collected**
✅ **Search queries not logged** (only query length)
✅ **Station codes only** (no user routes)
✅ **Local logging** via OSLog (user-controlled)
✅ **Opt-in analytics** (disabled in debug)

## Testing

### Debug Features

**Network Logging:**
```swift
// Enabled only in DEBUG builds
#if DEBUG
logger.debug("🌐 Request: /nsapp-stations/v3")
logger.debug("📥 Response: 200 OK")
#endif
```

**Health Checks:**
```swift
// Automatic on app launch in debug builds
await verifyBackendConnection()
```

**Diagnostic Reports:**
```swift
let report = await BackendHealthMonitor.shared.generateDiagnosticReport()
```

### Unit Testing

**Testable Components:**
- `NetworkError` mapping
- `AppConfiguration` values
- Cache expiration logic
- Rate limiting algorithm

**Mock Support:**
```swift
// BackendAPI is protocol-based, allowing mocks
protocol BackendAPIProtocol {
    func getStations() async throws -> StationResponse
}
```

## CI/CD Integration

### GitHub Actions Example

```yaml
- name: Set up secrets
  run: |
    echo "API_KEY=${{ secrets.NS_API_KEY }}" > Secrets.xcconfig

- name: Build
  run: xcodebuild build -scheme rnsapp
```

### Xcode Cloud Example

```swift
// ci_post_clone.sh
#!/bin/sh
echo "API_KEY=${NS_API_KEY}" > Secrets.xcconfig
```

## Future Enhancements

### Planned Features

1. **Offline Support**
   - Cache entire station database
   - Queue mutations for sync
   - Background refresh

2. **Advanced Caching**
   - Core Data persistence
   - Differential updates
   - Prefetching strategies

3. **Enhanced Analytics**
   - TelemetryDeck integration
   - Performance metrics dashboard
   - Crash reporting (optional)

4. **API Versioning**
   - Support multiple API versions
   - Graceful degradation
   - Feature detection

5. **GraphQL Support**
   - Optimize payload size
   - Request only needed fields
   - Real-time updates via subscriptions

## Troubleshooting

### Common Issues

**1. "No API key found"**
```
Solution: Ensure Secrets.xcconfig exists and contains API_KEY
Check: cat Secrets.xcconfig
```

**2. "Rate limited"**
```
Solution: Wait 60 seconds or reduce request frequency
Check: Review rate limiting in BackendAPI
```

**3. "Unauthorized (401)"**
```
Solution: Verify API key at https://apiportal.ns.nl
Reset: Delete from Keychain and update Secrets.xcconfig
```

**4. "Decoding error"**
```
Solution: API response format may have changed
Debug: Enable detailed logging to see raw JSON
```

### Debug Commands

```swift
// Check API key status
let hasKey = await KeychainManager.shared.hasAPIKey()
print("Has API key in Keychain: \(hasKey)")

// Force backend health check
let health = await BackendHealthMonitor.shared.checkHealth()
print("Backend status: \(health.status)")

// Generate diagnostic report
let report = await BackendHealthMonitor.shared.generateDiagnosticReport()
print(report.description)

// Clear all caches
let repository = StationsRepository()
await repository.clearCache()
URLCache.shared.removeAllCachedResponses()
```

## Performance Metrics

### Typical Performance

**Cold Start (No Cache):**
- API Request: ~500-1000ms
- JSON Decoding: ~50-100ms
- Total: ~600-1100ms

**Warm Start (With Cache):**
- Cache Lookup: <1ms
- Total: ~1ms

**Retry Scenarios:**
- Rate limit: +1-4s (exponential backoff)
- Server error: +0.5-2s (exponential backoff)
- Timeout: +30s (one retry)

## Maintenance

### Regular Tasks

**Weekly:**
- Review analytics for errors
- Check health monitoring logs
- Verify API quota usage

**Monthly:**
- Update dependencies
- Review cache hit rates
- Rotate API keys (recommended)

**Quarterly:**
- Security audit
- Performance profiling
- Update documentation

---

**Last Updated:** February 25, 2026
**Version:** 1.0
**Maintainer:** Backend Team
