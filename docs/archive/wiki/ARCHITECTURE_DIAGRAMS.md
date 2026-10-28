# Backend Architecture - Visual Overview

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         iOS Application                              │
│                                                                      │
│  ┌────────────────────────────────────────────────────────────┐    │
│  │                    UI Layer (SwiftUI)                       │    │
│  │   MainTabView │ DiscoveryView │ MapView │ HistoryView      │    │
│  └───────────────────────────┬────────────────────────────────┘    │
│                              │                                       │
│  ┌───────────────────────────▼────────────────────────────────┐    │
│  │              ViewModel Layer (@MainActor)                   │    │
│  │        DiscoveryViewModel │ MapViewModel │ etc.             │    │
│  └───────────────────────────┬────────────────────────────────┘    │
│                              │                                       │
│  ┌───────────────────────────▼────────────────────────────────┐    │
│  │            Repository Layer (Actor)                         │    │
│  │                                                              │    │
│  │              StationsRepository                             │    │
│  │              ┌──────────────────────┐                       │    │
│  │              │  In-Memory Cache     │                       │    │
│  │              │  TTL: 1 hour         │                       │    │
│  │              │  Analytics Tracking  │                       │    │
│  │              └──────────────────────┘                       │    │
│  └───────────────────────────┬────────────────────────────────┘    │
│                              │                                       │
│  ┌───────────────────────────▼────────────────────────────────┐    │
│  │              Backend API Layer (Actor)                      │    │
│  │                                                              │    │
│  │                    BackendAPI                               │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐     │    │
│  │  │ Rate Limiter │  │ Retry Logic  │  │ Error Handler│     │    │
│  │  │ 30 req/min   │  │ Exponential  │  │ 13 Types     │     │    │
│  │  │ Auto-queue   │  │ 3 attempts   │  │ User-friendly│     │    │
│  │  └──────────────┘  └──────────────┘  └──────────────┘     │    │
│  └───────────────────────────┬────────────────────────────────┘    │
│                              │                                       │
│  ┌───────────────────────────┴────────────────────────────────┐    │
│  │          Cross-Cutting Concerns (Actors)                    │    │
│  │                                                              │    │
│  │  ┌──────────────────┐  ┌───────────────────────────┐       │    │
│  │  │ KeychainManager  │  │   AnalyticsManager        │       │    │
│  │  │                  │  │                            │       │    │
│  │  │ • API Key Store  │  │ • Event Tracking          │       │    │
│  │  │ • Secure Access  │  │ • Screen Tracking         │       │    │
│  │  │ • Auto-migrate   │  │ • Performance Metrics     │       │    │
│  │  └──────────────────┘  └───────────────────────────┘       │    │
│  │                                                              │    │
│  │  ┌──────────────────┐  ┌───────────────────────────┐       │    │
│  │  │ BackendHealth    │  │  AppConfiguration         │       │    │
│  │  │ Monitor          │  │                            │       │    │
│  │  │                  │  │ • API Settings            │       │    │
│  │  │ • Network Status │  │ • Feature Flags           │       │    │
│  │  │ • Health Checks  │  │ • Environment Config      │       │    │
│  │  │ • Diagnostics    │  │ • App Information         │       │    │
│  │  └──────────────────┘  └───────────────────────────┘       │    │
│  └──────────────────────────────────────────────────────────────┘  │
│                                                                      │
└──────────────────────────┬───────────────────────────────────────────┘
                           │
         ┌─────────────────┴──────────────────┐
         │                                     │
    ┌────▼─────┐                      ┌───────▼──────┐
    │ URLSession│                      │iOS Keychain  │
    │           │                      │              │
    │ • HTTP/2  │                      │ • Encrypted  │
    │ • Caching │                      │ • Secure     │
    │ • GZip    │                      │ • Protected  │
    └────┬──────┘                      └──────────────┘
         │
         │ HTTPS
         │
    ┌────▼──────────────────────────────┐
    │  NS API Gateway                   │
    │  https://gateway.apiportal.ns.nl  │
    │                                    │
    │  Endpoints:                        │
    │  • /nsapp-stations/v3             │
    │  • /nsapp-departures/v3 (future)  │
    │  • /nsapp-disruptions/v3 (future) │
    └────────────────────────────────────┘
```

## Security Flow - API Key Management

```
┌─────────────────────────────────────────────────────────────┐
│                     Development Phase                        │
└─────────────────────────────────────────────────────────────┘

Step 1: Developer Setup
┌──────────────────────┐
│ Developer            │
│ Gets API key from    │──────┐
│ https://apiportal.ns.nl │    │
└──────────────────────┘      │
                              │
Step 2: Local Configuration   │
┌──────────────────────┐      │
│ Secrets.xcconfig     │◄─────┘
│ (NOT in Git)         │
│                      │
│ API_KEY = abc123...  │
└──────┬───────────────┘
       │
       │ Xcode Build Process
       │
       ▼
┌──────────────────────┐
│ Info.plist           │
│ (Embedded in app)    │
│                      │
│ NS_API_KEY=$(API_KEY)│
└──────┬───────────────┘
       │
       │
┌──────┴─────────────────────────────────────────────────────┐
│                      Runtime Phase                          │
└────────────────────────────────────────────────────────────┘
       │
       │ First App Launch
       ▼
┌──────────────────────┐
│ BackendAPI           │
│                      │
│ 1. Check Keychain    │───────┐
│ 2. If empty, load    │       │
│    from Info.plist   │       │
│ 3. Save to Keychain  │       │
└──────────────────────┘       │
                               │
                               ▼
                        ┌──────────────────┐
                        │ iOS Keychain     │
                        │                  │
                        │ • Encrypted      │
                        │ • Secure         │
                        │ • Persistent     │
                        └──────┬───────────┘
                               │
                               │ All Subsequent Launches
                               │
                               ▼
                        ┌──────────────────┐
                        │ API Requests     │
                        │                  │
                        │ Uses key from    │
                        │ Keychain only    │
                        └──────────────────┘
```

## Request Flow - With Caching & Retry

```
User Action (e.g., "View Discovery")
│
▼
┌─────────────────────────────────────────┐
│ DiscoveryViewModel                      │
│ await repository.stations()             │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│ StationsRepository                      │
│                                          │
│ Cache Check?                             │
│ ┌─────────────────────────────────┐     │
│ │ Valid & Not Expired?            │     │
│ └─┬────────────────────────────┬──┘     │
│   │ YES                        │ NO     │
│   │                            │         │
│   ▼                            ▼         │
│ Return Cache        Track Cache Miss    │
│ Track Hit                   │            │
│   │                         │            │
└───┼─────────────────────────┼────────────┘
    │                         │
    │ <1ms response           │
    │                         ▼
    │              ┌──────────────────────┐
    │              │ BackendAPI           │
    │              │                      │
    │              │ Rate Limit Check?    │
    │              │ ┌──────────────────┐ │
    │              │ │ < 30 req/min?    │ │
    │              │ └─┬────────────┬───┘ │
    │              │   │ YES        │ NO  │
    │              │   │            │     │
    │              │   ▼            ▼     │
    │              │ Proceed      Wait    │
    │              │   │                  │
    │              │   ▼                  │
    │              │ Build Request        │
    │              │ • Add API Key        │
    │              │ • Add Headers        │
    │              │ • Log Request        │
    │              └──────┬───────────────┘
    │                     │
    │                     ▼
    │              ┌──────────────────────┐
    │              │ URLSession           │
    │              │ HTTP GET Request     │
    │              └──────┬───────────────┘
    │                     │
    │                     │ Network Call
    │                     │
    │              ┌──────▼───────────────┐
    │              │ NS API Gateway       │
    │              │ (External Server)    │
    │              └──────┬───────────────┘
    │                     │
    │              ┌──────▼───────────────┐
    │              │ Response Handler     │
    │              │                      │
    │              │ Status Code?         │
    │              │ ┌─────────────────┐  │
    │              │ │ 200 OK          │  │
    │              │ │ ▼               │  │
    │              │ │ Decode JSON     │  │
    │              │ │ Track Success   │  │
    │              │ │ Cache Result    │  │
    │              │ │ Return Data  ───┼──┼──┐
    │              │ └─────────────────┘  │  │
    │              │                      │  │
    │              │ ┌─────────────────┐  │  │
    │              │ │ 429 Rate Limit  │  │  │
    │              │ │ ▼               │  │  │
    │              │ │ Wait 1s         │  │  │
    │              │ │ Retry (attempt 1)  │  │
    │              │ │ ▼               │  │  │
    │              │ │ Wait 2s         │  │  │
    │              │ │ Retry (attempt 2)  │  │
    │              │ │ ▼               │  │  │
    │              │ │ Wait 4s         │  │  │
    │              │ │ Retry (attempt 3)  │  │
    │              │ │ ▼               │  │  │
    │              │ │ Success? Return │  │  │
    │              │ │ Fail? Throw Error  │  │
    │              │ └─────────────────┘  │  │
    │              │                      │  │
    │              │ ┌─────────────────┐  │  │
    │              │ │ 500 Server Err  │  │  │
    │              │ │ ▼               │  │  │
    │              │ │ Wait 0.5s       │  │  │
    │              │ │ Retry (max 2x)  │  │  │
    │              │ └─────────────────┘  │  │
    │              │                      │  │
    │              │ ┌─────────────────┐  │  │
    │              │ │ 401 Unauthorized│  │  │
    │              │ │ ▼               │  │  │
    │              │ │ Check API Key   │  │  │
    │              │ │ Throw Error     │  │  │
    │              │ └─────────────────┘  │  │
    │              └──────────────────────┘  │
    │                                        │
    ▼◄───────────────────────────────────────┘
┌─────────────────────────────────────────┐
│ UI Updates                               │
│ • Show stations                          │
│ • Display error if any                   │
│ • Stop loading indicator                 │
└─────────────────────────────────────────┘
```

## Error Handling Flow

```
┌──────────────────┐
│ Error Occurs     │
└────────┬─────────┘
         │
         ▼
┌────────────────────────────────────────┐
│ Error Classification                   │
│                                         │
│ Is it retryable?                        │
│ • Timeout        → YES (max 1 retry)   │
│ • No Connection  → YES (max 1 retry)   │
│ • Rate Limited   → YES (max 3 retries) │
│ • Server Error   → YES (max 2 retries) │
│ • Unauthorized   → NO                   │
│ • Invalid URL    → NO                   │
│ • Decoding Error → NO                   │
└────┬───────────────────────┬────────────┘
     │                       │
     │ YES                   │ NO
     │                       │
     ▼                       ▼
┌────────────────┐    ┌──────────────────┐
│ Retry Logic    │    │ Log Error        │
│                │    │ Track Analytics  │
│ Exponential    │    │ Show User Error  │
│ Backoff        │    │                  │
│                │    │ User-friendly    │
│ Try again...   │    │ message          │
└────┬───────────┘    │                  │
     │                │                  │
     │ Success?       │                  │
     │                │                  │
     ▼                ▼                  │
┌────────────────────────────────────────┤
│ Final Result                           │
│                                         │
│ • Return data (if successful)          │
│ • Throw NetworkError (if failed)       │
│ • Analytics tracked                    │
│ • User notified                        │
└────────────────────────────────────────┘
```

## Thread Safety - Actor Pattern

```
┌────────────────────────────────────────────────────────┐
│                   Main Actor                           │
│                   (UI Thread)                          │
│                                                         │
│  ┌──────────────────────────────────────────────┐     │
│  │  @MainActor class DiscoveryViewModel         │     │
│  │                                               │     │
│  │  @Published var stations: [Station] = []     │     │
│  │                                               │     │
│  │  func loadStations() async {                 │     │
│  │      let result = await repository.stations()│─┐   │
│  │      self.stations = result.payload          │ │   │
│  │  }                                            │ │   │
│  └──────────────────────────────────────────────┘ │   │
└────────────────────────────────────────────────────┼───┘
                                                     │
                                                     │
┌────────────────────────────────────────────────────▼───┐
│                Repository Actor                        │
│              (Background Thread)                       │
│                                                         │
│  ┌──────────────────────────────────────────────┐     │
│  │  actor StationsRepository                    │     │
│  │                                               │     │
│  │  private var cache: [Station]?               │     │
│  │                                               │     │
│  │  func stations() async throws -> Response {  │     │
│  │      if let cached = cache { return cached } │     │
│  │      let fresh = await backend.getStations()│─┐   │
│  │      cache = fresh                           │ │   │
│  │      return fresh                            │ │   │
│  │  }                                            │ │   │
│  └──────────────────────────────────────────────┘ │   │
└────────────────────────────────────────────────────┼───┘
                                                     │
                                                     │
┌────────────────────────────────────────────────────▼───┐
│                 Backend Actor                          │
│              (Background Thread)                       │
│                                                         │
│  ┌──────────────────────────────────────────────┐     │
│  │  actor BackendAPI                            │     │
│  │                                               │     │
│  │  private var rateLimitQueue: [Date] = []     │     │
│  │                                               │     │
│  │  func getStations() async throws {           │     │
│  │      try await checkRateLimit()              │     │
│  │      let (data, _) = await URLSession...     │     │
│  │      return decode(data)                     │     │
│  │  }                                            │     │
│  └──────────────────────────────────────────────┘     │
└────────────────────────────────────────────────────────┘

Benefits of Actor Pattern:
✅ No race conditions
✅ No manual locks needed
✅ Sequential access guaranteed
✅ Clean async/await syntax
✅ Compiler-enforced safety
```

## Performance Timeline - Cached vs Non-Cached

```
Non-Cached Request (First Time):
┌────┬────┬────┬────┬────┬────┬────┬────┬────┬────┐
│    │    │    │    │    │    │    │    │    │    │
0ms  100  200  300  400  500  600  700  800  900  1000ms
│    │    │         │              │         │     │
│    │    │         │              │         │     └─ UI Updated
│    │    │         │              │         └─ JSON Decoded
│    │    │         │              └─ Response Received
│    │    │         └─ Request Sent
│    │    └─ Rate Limit Check
│    └─ Cache Miss
└─ User Action

Total: ~900ms


Cached Request (Subsequent Times):
┌┐
││
0ms 1ms
││
│└─ UI Updated
└─ Cache Hit

Total: <1ms (900x faster!)
```

## Legend

```
┌─────┐
│ Box │  = Component or Step
└─────┘

  │
  ▼      = Data/Control Flow

─────►   = Network Request

◄─────   = Network Response

Actor    = Thread-safe component
         (Swift Actor)

@MainActor = UI Thread
           (Main Queue)
```

---

**This diagram shows:**
1. Layered architecture (UI → ViewModel → Repository → Backend)
2. Security flow (xcconfig → Info.plist → Keychain)
3. Request flow with caching and retry logic
4. Error handling with retry strategy
5. Thread safety with actors
6. Performance comparison (cached vs non-cached)
