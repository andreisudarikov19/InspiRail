# Clear network errors and retries (#20) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When the station list can't be loaded, each screen says what actually went wrong. The app retries only what a retry can fix, as the server asks, without the client-side limiter's waits. It stops sending a key NS has refused until that key changes, and one station it can't read no longer breaks the whole list.

**Architecture:** `NetworkError` gets one case per cause, each with one short message, and one helper gives a screen the message for any error, or none for a cancellation. `APIKeyProvider` tells "no key" from "Keychain unavailable", through a small storage protocol that tests can fake. `BackendAPI.getStations` reads the key once per load and runs a loop of at most three attempts. The loop honours `Retry-After`, reports a failure once, and remembers a refused key by its SHA-256 hash, which the station store exposes as `keyRefusal`. `StationResponse` decodes stations one at a time and lists the ones it skips.

**Tech Stack:** Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, Swift concurrency (actors, `Task`, cancellation), `URLSession` and `URLProtocol`, `Codable`, CryptoKit (`SHA256`), Swift Testing, `xcodebuild`, `xcrun simctl`.

**Spec:** issue #20, https://github.com/andreisudarikov19/InspiRail/issues/20, including its "From #18" section (its line numbers refer to 8c02931), and the owner's direction for its open choices, recorded under Decisions below. Every item was checked against `main` at 68f7c2c (after #17 and #18). The code is now at `InspiRail/BackendAPI.swift:91-93,114-276` (limiter `:242-263`, key read `:123`, status handling `:155-214`, decoding `:219-240`, transport mapping `:265-276`), `InspiRail/APIKeyProvider.swift:32-71` (the Keychain read the issue cites at `BackendAPI.swift:296-343`), `InspiRail/NetworkEngine/NetworkError.swift:10-40`, `InspiRail/Models/Station.swift:11-60`, and the callers `InspiRail/ViewModels/DiscoveryViewModel.swift:31-58`, `InspiRail/Pages/OnboardingView.swift:160-207`, `InspiRail/Pages/SettingsView.swift:161-177,245-261`, `InspiRail/Pages/VisitedListView.swift:121-135` and `InspiRail/BackendHealthMonitor.swift:98-145`. The #18 plan, `docs/superpowers/plans/2026-11-01-shared-station-store.md`, describes the shared store and the limiter as they are now.

## Global Constraints

- What changes for a user: which message a screen shows, and fewer pointless waits and requests. Where key entry appears, which buttons a screen offers, and what Settings' key check reports (apart from ignoring a cancelled check, Decision 2) stay as they are on `main`. A fix that would change what a user can do is stopped and reported, not built.
- Out of scope, and left as they are: Settings' key check, what it reports and its timing (#19). Retry buttons, pull to refresh, key entry on more screens, the 60-second offline wait (`waitsForConnectivity`) and an explicit refresh (#21). Onboarding's behaviour (#22, #42). Also #23, #24, #25, #29, #36 and #37.
- `InspiRailApp.init` stays the only place that creates a `StationsRepository` or a `BackendAPI`. #15's test-host gate stays: while hosting the unit tests the app creates no store, no API and no session.
- Tests never reach the network: every request in a test goes through `StubURLProtocol`. Tests never wait for real: the API's clock, sleep and failure report are injected.
- No key, and no part of a key, is ever logged, kept or shown. The refused-key memory keeps a SHA-256 hash only, and doesn't print it. The public repo, the PR and the docs never say that a key was leaked, exposed or rotated.
- Typecheck after every task: `xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios26.2-simulator -swift-version 5 -default-isolation MainActor $(find InspiRail -name '*.swift')`. On `main` it prints 0 errors and 11 warnings (22 `warning:` lines, each echoed under its source line). No task may add a warning. Task 2 removes two (`maxRequestsPerMinute`, `maxRetries`) and Task 4 one (`StationResponse`'s main-actor `Decodable` conformance).
- Test command, one `xcodebuild` at a time: `xcodebuild test -project InspiRail.xcodeproj -scheme InspiRail -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath <scratch>`, on a throwaway iPhone 15 simulator (iOS 26.3) created for this branch. On `main`: `** TEST SUCCEEDED **`, 44 passed, 0 skipped.
- Commit subjects use a conventional prefix and end with `(#20)`. Blank lines inside the app's code are indented to the enclosing level. Test files keep their empty blank lines.

## The messages

One message per case, the same on Discover and in onboarding. Discover shows it under its title "Connection Issue", onboarding under "Error"; both titles stay (see Notes for other issues). Onboarding still shows its "Open Settings" button for the four key cases, exactly the errors that were `.unauthorized` on `main`, so what a user can do there is unchanged. The Logbook still fails silently, and the Home Station picker still shows an empty list.

| Case | Cause | Discover on `main` | Onboarding on `main` | Both screens now |
|---|---|---|---|---|
| `noKey` | No key in the Keychain, and none from `NS_API_KEY` | "Authentication failed" | "No valid NS API key. Tap below to enter one (get a free key at apiportal.ns.nl)." + Open Settings | "No NS API key is set. Add one in Settings." (+ Open Settings) |
| `keychainUnavailable` | The Keychain read failed for a reason other than "not found", e.g. `errSecInteractionNotAllowed` or unreadable data: a key may be stored | "Authentication failed" | as `noKey` | "Your NS API key can't be read right now. Try again in a moment." (+ Open Settings) |
| `keyRejected` | HTTP 401 | "Authentication failed" | as `noKey` | "NS didn't accept your API key. Check it in Settings." (+ Open Settings) |
| `forbidden` | HTTP 403: forbidden, or over the key's quota | "Authentication failed" | as `noKey` | "NS refused your API key. It may be over its usage limit. Try again later." (+ Open Settings) |
| `tooManyRequests` | HTTP 429 | "Too many requests", after waits of 1, 2 and 4 s | "Could not load stations: Too many requests" | "NS is getting too many requests. Try again in a minute." |
| `serviceUnavailable(status:)` | HTTP 500–599 | "Server error (503)" (the status), after waits of 0.5 and 1 s | "Could not load stations: Server error (503)" | "NS isn't available right now. Try again later." |
| `offline(_:)` | Any transport failure: no internet, connection lost, timeouts, DNS (`cannotFindHost`, `dnsLookupFailed`), `cannotConnectToHost`, TLS and certificate errors, roaming or data not allowed | Depends on the error: "No internet connection" (no internet, connection lost), "Request timed out", "Server error (503)" (`cannotFindHost`, `cannotConnectToHost`), or the system's own text, e.g. "An SSL error has occurred and a secure connection to the server cannot be made." | "No internet connection. Please check your network.", "Connection timeout. Please try again.", or "Could not load stations: " + Discover's text | "Can't reach NS. Check your internet connection." |
| `unreadableData` | A 2xx body that doesn't decode, a list where no station decodes or that is empty, any other status (404, other 4xx, 3xx), a non-HTTP response, or a body URLSession can't parse | "Data format error: …" + the decoder's text, "Server error (404)", or "The operation couldn't be completed. (BackendAPI error -1.)" | "Could not load stations: " + Discover's text | "NS sent data this version of InspiRail can't read. Try again later." |
| cancelled | `CancellationError`, `URLError.cancelled` | "cancelled", or "The operation couldn't be completed. (Swift.CancellationError error 1.)". Since #18 a screen's own load can't be cancelled; Settings' key check can be | "Could not load stations: cancelled" | Nothing: the screen keeps what it showed |
| `invalidURL` | The stations URL can't be built. It is built from constants, so this can't happen | "Invalid URL" | "Could not load stations: Invalid URL" | "Invalid URL" (unchanged) |

Any other error, which the API no longer throws, shows "Couldn't load stations. Try again later." on both screens (on `main`, Discover's "Could not load stations. Please check your connection." and onboarding's "Could not load stations. Please check your internet connection.").

## The station fields each screen uses

| Field | Used by | Now |
|---|---|---|
| `id.code` | Every screen: identity, Discover's badge and visited mark, Randomize's exclusions, the home lookup, the pickers' badge, search and selection | Required |
| `names.long` | Discover's title and the visit's saved name, the pickers' rows, search and saved name, the store's sort | Required |
| `names.short` | Discover's map marker | Required |
| `names.synonyms` | Discover's synonym badge | Optional, as now |
| `stationType` | `readableType`: Discover's badge, the pickers' subtitles | Required |
| `location.lat`, `location.lng` | Discover's map, distance and travel time, the home station's location | Required |
| `country` | The store's Dutch filter (and so the Logbook's count) | Required |
| `hasKnownFacilities`, `hasTravelAssistance` | Discover's Amenities and Assist ("No" when missing) | Optional, as now |
| `id.uicCode`, `tracks` | Nothing | Optional, as now |
| `names.medium` | Nothing | Optional (was required) |

Settings' key check uses no field: it only needs the request to succeed.

## Decisions

1. **Separate error cases, one plain message each** (the table above). Reason: the message should name the cause and the one thing the user can do about it, so a Keychain hiccup no longer reads as a missing key, a quota as a bad key, or a captive portal as an NS outage. The cases replace `unauthorized`, `rateLimited`, `timeout`, `noConnection`, `serverError`, `decodingError` and `unknown`. Every status and transport failure maps to exactly one case, so no screen shows a system or decoder text again. A 404 or other unexpected status counts as unreadable data: NS answered, but not with something this version can use. The onboarding button keeps its exact `main` conditions (`NetworkError.concernsTheKey`), because offering or hiding it is a flow change (#22). `NetworkError.message(for:)` gives a screen the text for any error, or `nil` for a cancellation, so the screens can't drift apart again.
2. **Cancellation passes through unchanged.** The API turns `URLError.cancelled` into `CancellationError`, rethrows `CancellationError` from a wait, and checks for cancellation before each attempt and after each failure. It never wraps one in a `NetworkError`, and never reports one. Every `catch` on the station-loading paths ignores it, leaving the screen as it was:
   - Discover's view model (`DiscoveryViewModel.swift:49-57`): no message, no state change.
   - Onboarding (`OnboardingView.swift:178-206`): no message, no state change.
   - The Home Station picker (`SettingsView.swift:257-260`): leaves `isLoading` as it is. On `main` it ended the spinner and showed an empty list.
   - The Logbook (`VisitedListView.swift:131-134`): already ignores every error.
   - Settings' key check (`BackendHealthMonitor.swift:131-144`, `SettingsView.swift:161-177`): `checkHealth(using:)` rethrows a cancellation instead of counting a failure, and Settings keeps its previous status. On `main`, leaving the Settings tab mid-check cancels its `.task`, the check fails, and Settings shows "Configured key isn't working" on the next visit until the new check ends. This changes what the check reports only for a cancelled check. Everything else about the check is #19's.

   Since #18 the store's download runs in its own task and isn't cancelled when a screen leaves, so the three screens can't see a cancellation today. Their guards keep it that way if that changes.
3. **Retries: a loop of at most 3 attempts.**
   - Retried: 429, 500–599, and the transport failures that fail fast and often pass on a second try: `networkConnectionLost` (a dropped connection), `cannotConnectToHost`, `cannotFindHost` and `dnsLookupFailed`.
   - Not retried: 401, 403, 404 and every other status, unreadable data, and the other transport failures. `notConnectedToInternet` and `timedOut` come after the session has already waited (up to 30 s for a request, and up to 60 s for connectivity, which is #21's), so a retry would double or triple that wait. TLS and certificate failures come from a captive portal or a wrong clock, which seconds don't fix.
   - The wait: on 429 and 503, `Retry-After` in seconds or as an HTTP date (IMF-fixdate, e.g. `Mon, 01 Jan 2001 00:00:07 GMT`); a date in the past means no wait. Otherwise, or when the header can't be read, 1 s before the second attempt and 2 s before the third.
   - The cap is **10 s**. When the server asks for longer, the load fails at once with "too many requests" or "NS unavailable". Reason: about ten seconds is as long as someone will watch a loading screen before giving up, so a load waits at most 2 × 10 s plus three requests. A gateway that asks for more than that is pausing for a quota window, which won't end during a load.
   - The key is read once per load, so every attempt sends the same key.
   - The failure is reported once per load, after the last attempt, through an injected `reportFailure`, which by default logs one error line. Each retry logs one notice with its wait. A load refused for its key (Decision 5) counts as one failure; a cancellation is never reported.
   - Cancellation ends the loop at once, including during a wait.
   - `NetworkError.isRetryable` doesn't come back; `RetryPolicy` decides.
4. **The client-side limiter goes**, with `AppConfiguration.API.maxRequestsPerMinute` and `maxRetries` (replaced by `maxAttempts`). Reason: with one shared client, one download in flight and a list kept for an hour (#18), the app makes very few requests. The limiter only added waits of up to a minute during an outage, and it counted attempts that were never sent, such as those with no key. Server throttling is handled through `Retry-After`.
5. **A refused key isn't sent again until it changes.**
   - After a 401 the API records a `KeyRefusal` (reason `.rejected`) holding the key's SHA-256 hash. After a 403 it records one with reason `.forbidden` and an end date 15 minutes later.
   - Before each load it hashes the current key. When the hash matches and the pause hasn't ended, the load fails at once with that refusal's case, sends nothing and is reported once. When the key differs, or the cool-off has ended, the refusal is cleared and the request is sent. A success also clears it. The memory lives only as long as the process.
   - The state sits in `BackendAPI`, because the API is the only place that reads the key, and a 401 seen by Settings' key check then also stops Discover and the Logbook from resending (and the reverse). That covers every path in the issue's "From #18" item, including Settings, whose check now reports a refused key without a request; what it reports is unchanged. The store exposes it as `StationsRepository.keyRefusal` for #19.
   - `KeyRefusal`'s description and debug description hide the hash, and the key is never logged.
   - The **15-minute** cool-off: on NS's gateway (Azure API Management) a per-minute limit answers 429, so a 403 means a longer quota, or a key not allowed this API, which doesn't pass in a minute or two. Fifteen minutes caps the requests a refused key makes at four an hour, whatever the user does, and a user whose quota has reset waits at most 15 minutes more. Saving another key ends the pause at once.
6. **Stations decode one by one.** `StationResponse.init(from:)` walks the `payload` array. A station that fails to decode is skipped and recorded as a `SkippedStation` with its `id.code`, when it has a readable one, and the field that failed (e.g. `location` or `names.short`). The API logs each skipped station at warning level by code and field. When no station decodes, or the list is empty, the load fails as unreadable data and nothing is stored. `names.medium` becomes optional; the other fields stay as they are (table above). The station types become `nonisolated`, so the API actor can decode them, which removes one existing warning.
7. **The fixture is built from the documented shape, not taken from a real response.** No real NS response exists in the repo or the scratch tools. `docs/reference/` has only a field table, and the review stub's `stations.json` comes from `make_payload.py`, whose header says the values are made up ("shape after the public API"). So `stationFixture` keeps its six stations and their order (`UT`, `ASD`, `HT` "'s-Hertogenbosch", `ZL`, `BHF` Berlin Hbf in `D`, `BRUZ` Brussel-Zuid in `B`), and each now carries every field `docs/reference/ns-api.md` documents, with unknown extra keys of the kind the stub's generator models (`evaCode`, `names.festive: null`, `isBorderStop`, `radius`). The codes, UIC codes, names and countries are those of the real stations, which are public data. Coordinates are approximate and the other values illustrative. The fixture holds station data only: no headers, no keys.
8. **Nothing in this plan changes what a user can do.** Each change is a message, a cancelled result ignored, or waits and requests that no longer happen. Settings still shows its key section under the same conditions, onboarding still offers Open Settings for the same errors, and saving a new key still takes effect at the next load.

## Review Focus

1. **A key saved in Settings after a 401 or 403 must be sent by the very next load and key check, with no wait and no relaunch.** Pinned by Task 3's `changedKeyIsSentAfterARefusal` (for both statuses), and checked on the simulator in Task 5.
2. **No part of a key may end up in the refusal, its description or the log.** Pinned by Task 3's `keyRefusalHoldsNothingOfTheKey`. Task 5 searches the simulator's log for the dummy key.
3. **A load cut short must leave the screen as it was: never "cancelled", never "isn't working".** Pinned by Task 1's `cancelledRequestPassesThroughAsCancellation` and `eachErrorHasItsMessage` (no message for a cancellation), and Task 2's `cancellationDuringAWaitStopsTheLoop`.
4. **Someone offline or behind a captive portal must see "Can't reach NS", never an NS outage, and must not sit through retries that can't help.** Pinned by Task 1's `transportFailuresMeanOffline` and Task 2's `otherTransportFailuresAreNotRetried`, and checked on the simulator in Task 5 with no internet and with a failed DNS lookup.
5. **A person must never wait more than two capped waits and three requests, and a load must never be held back by earlier loads.** Pinned by Task 2's `retryAfterOverTheCapFailsAtOnce`, `retriedAtMostThreeTimes` and `manyLoadsInAMinuteAreNotHeldBack`.

## Notes for other issues

- **#21:** the new messages say "try again", but Discover offers no way to retry except leaving the tab and coming back, and the Home Station picker shows an empty list with no message whatever fails. An offline load still waits up to 60 s for connectivity before "Can't reach NS" appears.
- **#19:** Settings' key check now fails at once for a refused key without sending it, but still reports any failure, including offline, 429 and 5xx, as "Configured key isn't working". `StationsRepository.keyRefusal` tells a refused key from the rest.
- **#22, #42:** onboarding still offers Open Settings when the Keychain can't be read, where entering a key doesn't help, and for a 403, where another key may or may not.
- **#31:** Discover's error title "Connection Issue" and its Wi-Fi icon also appear above the key messages.
- **#33:** the station models are now `nonisolated`, which removes one Swift 6 warning.

---

### Task 1: One error case per cause, with its message, and cancellation passed through

**Files:**
- Modify: `InspiRail/NetworkEngine/NetworkError.swift` (rewrite)
- Modify: `InspiRail/APIKeyProvider.swift` (the storage protocol, the two key errors)
- Modify: `InspiRail/KeychainManager.swift` (conformance only)
- Modify: `InspiRail/BackendAPI.swift:114-276` (the mapping, cancellation; the recursion stays until Task 2)
- Modify: `InspiRail/ViewModels/DiscoveryViewModel.swift:49-57`, `InspiRail/Pages/OnboardingView.swift:178-206`, `InspiRail/Pages/SettingsView.swift:161-177,257-260`, `InspiRail/BackendHealthMonitor.swift:97-145`
- Modify: `InspiRailTests/StubURLProtocol.swift` (replies with headers or a transport failure), `InspiRailTests/StationStoreTests.swift:128-145` (`.keyRejected`), `InspiRailTests/APIKeyProviderTests.swift:77-86` (`.noKey`)
- Create: `InspiRailTests/NetworkErrorTests.swift`

**Interfaces:**
- Consumes: #18's `BackendAPI(keyProvider:sessionConfiguration:)`, `StubURLProtocol`, the suite's `api(keyProvider:)` and `sentKeys`.
- Produces:
  - `nonisolated enum NetworkError: Error, LocalizedError, Equatable` with `invalidURL`, `noKey`, `keychainUnavailable`, `keyRejected`, `forbidden`, `tooManyRequests`, `serviceUnavailable(status: Int)`, `offline(URLError.Code)`, `unreadableData`. `errorDescription` holds the table's texts. `var concernsTheKey: Bool` is true for the first four key cases. `static func message(for error: Error) -> String?` returns `nil` for `CancellationError` and `URLError.cancelled`, the case's text for a `NetworkError`, and "Couldn't load stations. Try again later." otherwise.
  - `nonisolated protocol APIKeyStorage: Sendable { func getAPIKey() async throws -> String; func saveAPIKey(_ key: String) async throws }`, with `extension KeychainManager: APIKeyStorage {}`. `APIKeyProvider.init(keychain: any APIKeyStorage, environment:allowsEnvironmentOverride:)`. `currentKey()` throws `.noKey` when nothing is stored (`KeychainError.notFound`) and `.keychainUnavailable` for any other read failure, both only when no environment key applies.
  - In `BackendAPI`: `private func failure(forStatus status: Int) -> NetworkError` (401, 403, 429, 500–599, otherwise `.unreadableData`) and `private func failure(for error: URLError) throws -> NetworkError` (throws `CancellationError` for `.cancelled`; `.badServerResponse`, `.cannotParseResponse`, `.cannotDecodeContentData`, `.cannotDecodeRawData` and `.zeroByteResource` are `.unreadableData`; every other code is `.offline(code)`). A non-HTTP response and a 2xx body that doesn't decode are `.unreadableData`. Any other error from the session is `.offline(.unknown)`.
  - `BackendHealthMonitor.checkHealth(using:) async throws -> HealthReport`, which throws only `CancellationError`.
  - Test target: `StubURLProtocol.Reply` becomes `Sendable` and gains `headers: [String: String]` and `failure: URLError.Code?`, with `Reply.status(_:headers:)`, `Reply.body(_ json: String)` (200 with that body) and `Reply.failure(_:)`. A failure reply calls `urlProtocol(_:didFailWithError:)`. `actor TestKeyStorage: APIKeyStorage` with `init(key: String? = nil, failure: KeychainError? = nil)` and `func setKey(_:)`.

- [ ] **Step 1: Write the failing tests** in `NetworkErrorTests.swift`, as `extension StationStoreTests`, so they share the serialized suite and its stub. Each expects its case, and the number of requests:
  - `keyRejectedFor401`: `.status(401)` → `.keyRejected`.
  - `forbiddenFor403`: `.status(403)` → `.forbidden`.
  - `otherStatusIsUnreadableData`: `.status(404)` → `.unreadableData`.
  - `undecodableReplyIsUnreadableData`: `.body("{}")` → `.unreadableData`.
  - `transportFailuresMeanOffline`, with arguments `.notConnectedToInternet`, `.networkConnectionLost`, `.timedOut`, `.cannotFindHost`, `.dnsLookupFailed`, `.cannotConnectToHost`, `.secureConnectionFailed` and `.serverCertificateUntrusted`: `.failure(code)` → `.offline(code)`.
  - `cancelledRequestPassesThroughAsCancellation`: `.failure(.cancelled)` throws `CancellationError`.
  - `noStoredKeyIsNoKey`: a provider over `TestKeyStorage()` with `environment: [:]` → `.noKey`, 0 requests.
  - `unreadableKeychainIsKeychainUnavailable`: `TestKeyStorage(failure: .retrievalFailed(errSecInteractionNotAllowed))` → `.keychainUnavailable`, 0 requests.
  - `eachErrorHasItsMessage`: `NetworkError.message(for:)` gives each case its text from the table, `nil` for `CancellationError()` and `URLError(.cancelled)`, and the fallback for another error. `concernsTheKey` is true for exactly `noKey`, `keychainUnavailable`, `keyRejected` and `forbidden`.

  Also change `rejectedKeyIsNotKeptAndTheNextLoadUsesTheNewKey` to expect `.keyRejected`, and `noKeyThrowsUnauthorized` to `noKeyThrowsNoKey`, expecting `.noKey`.
- [ ] **Step 2: Run them to verify they fail.** Test command with `-only-testing:InspiRailTests/StationStoreTests -only-testing:InspiRailTests/APIKeyProviderTests`. Expected: a build failure, `type 'NetworkError' has no member 'keyRejected'` or similar.
- [ ] **Step 3: Implement** the Interfaces above. The 401 branch keeps its log lines on where the key came from. The screens take their text from `NetworkError.message(for:)` and return without touching their state when it is `nil`. Onboarding sets `isUnauthorized` from `concernsTheKey`. The picker returns early on a cancellation. `checkHealth` rethrows a `CancellationError` without counting a failure, and `refreshKeyStatus()` returns without changing its state when the check throws.
- [ ] **Step 4: Run them to verify they pass.** Expected: the two suites pass, 9 new tests. Then check that a test can fail: mapping `.cannotFindHost` back to `.serviceUnavailable(status: 503)` fails `transportFailuresMeanOffline`. Restore the file.
- [ ] **Step 5: Typecheck.** Expected: 0 errors, 11 warnings.
- [ ] **Step 6: Commit** `fix: give each network failure its own case and message, and pass cancellation through (#20)`

### Task 2: Retry in a loop, as the server asks, and drop the client-side limiter

**Files:**
- Create: `InspiRail/NetworkEngine/RetryPolicy.swift`
- Modify: `InspiRail/BackendAPI.swift` (init, the loop; delete `checkRateLimit`, `requestTimestamps`, `maxRequestsPerMinute`, `maxRetries`)
- Modify: `InspiRail/AppConfiguration.swift:42-44`
- Modify: `InspiRailTests/StationStoreTests.swift` (the suite's clock, sleep and failure recorders), `InspiRailTests/NetworkErrorTests.swift`

**Interfaces:**
- Consumes: Task 1's `NetworkError`, `failure(forStatus:)`, `failure(for:)` and `StubURLProtocol.Reply`.
- Produces:
  - `AppConfiguration.API`: `nonisolated static let maxAttempts = 3` and `nonisolated static let longestRetryWait: TimeInterval = 10`. `maxRequestsPerMinute` and `maxRetries` are removed.
  - `nonisolated enum RetryPolicy` with:
    - `static func isTransient(_ code: URLError.Code) -> Bool`, true for the four codes in Decision 3.
    - `static func retryAfter(_ value: String?, now: Date) -> TimeInterval?`: whole seconds, or an IMF-fixdate read with an `en_US_POSIX` formatter in GMT, never negative. `nil` when the header is missing or unreadable.
    - `static func backoff(afterAttempt attempt: Int) -> TimeInterval`: 1, then 2.
  - `BackendAPI.init(keyProvider:sessionConfiguration:now:sleep:reportFailure:)`, with `now: @escaping @Sendable () -> Date = { Date() }`, `sleep: @escaping @Sendable (TimeInterval) async throws -> Void` (`Task.sleep` by default) and `reportFailure: @escaping @Sendable (NetworkError) -> Void` (one `logger.error` line by default).
  - The loop in `getStations` checks for cancellation, sends, and maps the outcome. On a failure it works out the wait: `retryAfter` on 429 and 503, else `backoff`, for retryable outcomes only. It retries while attempts remain and the wait is at most `longestRetryWait`; otherwise it reports once and throws.
  - Test target: `final class Recorder<Value: Sendable>: @unchecked Sendable` with `append(_:)` and `values`. The suite holds `clock = TestClock()`, `sleeps: Recorder<TimeInterval>` and `failures: Recorder<NetworkError>`, and `api(keyProvider:sleep:)` wires them, with a default sleep that records and returns at once.

- [ ] **Step 1: Write the failing tests.**
  - `retriedAtMostThreeTimes`, with arguments 429, 500, 502, 503 and 504, each the only reply: 3 requests, sleeps `[1, 2]`, and the case `.tooManyRequests` or `.serviceUnavailable(status:)`.
  - `retryAfterInSecondsIsHonoured`, with arguments 429 and 503 × `"7"` and `"10"`: replies `[.status(status, headers: ["Retry-After": value]), .stations]`. The load succeeds, sleeps are `[7]` or `[10]`, 2 requests.
  - `retryAfterAsADateIsHonoured`, with arguments 429 and 503: `Retry-After: Mon, 01 Jan 2001 00:00:07 GMT`, which is the test clock's start plus 7 s. Sleeps `[7]`.
  - `retryAfterOverTheCapFailsAtOnce`, with arguments 429 and 503 × `"11"` and `"Mon, 01 Jan 2001 00:00:11 GMT"`: fails with its case, 1 request, no sleep.
  - `refusedMissingAndUnreadableAreNotRetried`, with arguments `.status(401)`, `.status(403)`, `.status(404)` and `.body("{}")`: 1 request, no sleep.
  - `transientFailuresAreRetried`, with arguments `.networkConnectionLost`, `.cannotConnectToHost`, `.cannotFindHost` and `.dnsLookupFailed`: 3 requests, sleeps `[1, 2]`, `.offline(code)`.
  - `otherTransportFailuresAreNotRetried`, with arguments `.notConnectedToInternet`, `.timedOut`, `.secureConnectionFailed` and `.serverCertificateUntrusted`: 1 request.
  - `cancellationDuringAWaitStopsTheLoop`: `.status(503, headers: ["Retry-After": "5"])`, and a sleep that records and then waits an hour with `Task.sleep`. Start the load in a `Task`, wait until one sleep is recorded, and cancel. Expected: `CancellationError`, 1 request, no failure reported.
  - `failureIsReportedOncePerLoad`: three 503s give one report, `[.serviceUnavailable(status: 503)]`. Then `[.status(429), .stations]` adds none. Then a load through the store with two callers sharing it gives one more.
  - `manyLoadsInAMinuteAreNotHeldBack`: 31 loads answered 404 in a row give 31 requests, no sleep, and take under 5 s. On `main` the 31st waits a minute.
- [ ] **Step 2: Run them to verify they fail.** Expected: a build failure, `extra arguments at positions #3, #4, #5 in call`, since `BackendAPI.init` has no clock, sleep or report yet.
- [ ] **Step 3: Implement** `RetryPolicy`, the init and the loop as in Interfaces, and delete the limiter and its configuration. The session's doc comment says app code goes through the API's methods, "which read the key, retry and hold back a refused key".
- [ ] **Step 4: Run them to verify they pass.** Expected: the suite passes, 10 new tests. Then check that the tests can fail: a loop that ignores `Retry-After` fails `retryAfterInSecondsIsHonoured`, and one that allows four attempts fails `retriedAtMostThreeTimes`. Restore the file.
- [ ] **Step 5: Typecheck.** Expected: 0 errors, 9 warnings (the `maxRequestsPerMinute` and `maxRetries` ones are gone).
- [ ] **Step 6: Commit** `fix: retry only what can succeed, as Retry-After asks, and drop the client-side rate limiter (#20)`

### Task 3: Don't send a refused key again until it changes

**Files:**
- Create: `InspiRail/NetworkEngine/KeyRefusal.swift`
- Modify: `InspiRail/BackendAPI.swift` (record, check, clear), `InspiRail/ViewModels/StationsRepository.swift` (`keyRefusal`), `InspiRail/AppConfiguration.swift`
- Modify: `InspiRailTests/NetworkErrorTests.swift`

**Interfaces:**
- Consumes: Task 2's loop, clock and `reportFailure`. Task 1's `TestKeyStorage`.
- Produces:
  - `AppConfiguration.API.forbiddenKeyPause: TimeInterval = 15 * 60`, `nonisolated`.
  - `nonisolated struct KeyRefusal: Sendable, Equatable, CustomStringConvertible, CustomDebugStringConvertible` with `enum Reason: Sendable { case rejected, forbidden }`, `let reason: Reason`, `let since: Date`, `let until: Date?` (`nil` means until the key changes), `init(_ reason: Reason, key: String, at date: Date)` (the 403 end date from `forbiddenKeyPause`), `func holds(for key: String, at date: Date) -> Bool` and `var error: NetworkError` (`.keyRejected` or `.forbidden`). It keeps `SHA256.hash(data: Data(key.utf8))` in a private property. Its descriptions name the reason and dates only.
  - `BackendAPI.keyRefusal: KeyRefusal?` (`private(set)`), and `StationsRepository.keyRefusal: KeyRefusal? { get async }`, which reads it.

- [ ] **Step 1: Write the failing tests.** Each uses a provider over `TestKeyStorage` with `environment: [:]`.
  - `rejectedKeyIsNotSentAgain`: `[.status(401), .stations]`. The store's load fails with `.keyRejected`. A second load through the store, and one through `repository.backend.getStations()` (Settings' path), also fail with `.keyRejected`. 1 request, 3 failures reported. `keyRefusal?.reason == .rejected`, with `until == nil`.
  - `changedKeyIsSentAfterARefusal`, with arguments 401 and 403: replies `[.status(status), .stations]`, key `"refused-test-key"`. The load fails. After `setKey("accepted-test-key")` the next load succeeds. `sentKeys == ["refused-test-key", "accepted-test-key"]`, and `keyRefusal == nil`.
  - `forbiddenKeyPausesUntilTheCoolOffEnds`: `[.status(403), .stations]`. The load fails with `.forbidden`. After advancing the clock by `forbiddenKeyPause - 1`, it fails again with 1 request. After 1 s more it succeeds, with 2 requests, and `keyRefusal == nil`.
  - `keyRefusalHoldsNothingOfTheKey`: after a 401 with key `"QWERTY-test-key"`, neither `String(describing:)` nor `String(reflecting:)` of the refusal, nor `dump`'s output, contains `"QWERTY"` (no hexadecimal digest can).
- [ ] **Step 2: Run them to verify they fail.** Expected: a build failure, `value of type 'StationsRepository' has no member 'keyRefusal'`.
- [ ] **Step 3: Implement** as in Interfaces and Decision 5. The check runs after the key is read and before the first attempt. It logs one notice without the key, e.g. "Not sending the API key NS refused (401) until it changes". It reports the failure once and throws `refusal.error`. A 401 or 403 records the refusal before reporting, and a 2xx clears it.
- [ ] **Step 4: Run them to verify they pass.** Expected: the suite passes, 4 new tests. Then check that they can fail: an API that never records a refusal fails `rejectedKeyIsNotSentAgain`, and one whose 403 pause never ends fails `forbiddenKeyPausesUntilTheCoolOffEnds`. Restore the file.
- [ ] **Step 5: Typecheck.** Expected: 0 errors, 9 warnings.
- [ ] **Step 6: Commit** `fix: stop sending an API key NS refused until it changes, or for 15 minutes after a 403 (#20)`

### Task 4: Decode stations one by one, and skip the ones that can't be read

**Files:**
- Modify: `InspiRail/Models/Station.swift` (`nonisolated` types, `names.medium` optional, `StationResponse.init(from:)`, `SkippedStation`)
- Modify: `InspiRail/BackendAPI.swift` (log the skipped stations; an empty list is unreadable)
- Modify: `InspiRailTests/StubURLProtocol.swift` (`stationFixture` with the full documented shape), `InspiRailTests/NetworkErrorTests.swift`

**Interfaces:**
- Consumes: Task 1's `.unreadableData` and `Reply.body(_:)`.
- Produces:
  - `nonisolated struct StationResponse: Decodable { let payload: [Station]; let skipped: [SkippedStation] }`. `Station`, `StationIdentifiers`, `StationNames` and `StationLocation` become `nonisolated`, with `StationNames.medium: String?`.
  - `nonisolated struct SkippedStation: Sendable, Equatable { let code: String?; let field: String }`. `field` is the failing coding path below the station, dot-joined (`"location"`, `"names.short"`; `""` for an element that isn't a station, such as `null`). For `keyNotFound` it is the path plus the missing key.
  - `init(from:)` walks the `payload` array with an unkeyed container. For each element: `decodeNil()` skips a `null`. Otherwise it tries `Station`, and on failure decodes a private `StationCode` whose init never throws (it reads `id.code` with `try?`), so the container moves past the element.

- [ ] **Step 1: Write the failing tests.**
  - `documentedShapeFixtureDecodes`: `stationFixture` gives six stations and no skipped ones, in fixture order. `HT`'s long name is "'s-Hertogenbosch" and its first synonym "Den Bosch". `BHF`'s country is `"D"`. `UT` has tracks and `hasKnownFacilities == true`.
  - `malformedStationIsSkippedAndTheRestLoad`: a list of `UT` (whole), `"BAD"` without `location`, `null`, an object without `id`, `NM` "Nijmegen" (`NL`) without `names.medium`, and `ASD` (whole). The payload is `["UT", "NM", "ASD"]` and the skipped are `[("BAD", "location"), (nil, ""), (nil, "id")]`. Through the store, the Dutch stations are `["ASD", "NM", "UT"]`.
  - `listWhereNothingDecodesIsUnreadable`, with arguments a list of two broken stations and `{"payload":[]}`: `.unreadableData`. A following load is sent again, so nothing was stored.
- [ ] **Step 2: Run them to verify they fail.** Expected: a build failure, `value of type 'StationResponse' has no member 'skipped'`.
- [ ] **Step 3: Implement** as in Interfaces and Decision 6. The API logs each skipped station at warning level as "Skipped station \<code or 'without a code'\>: can't read \<field\>", and throws `.unreadableData` when `payload` is empty. Upgrade `stationFixture` as in Decision 7, with a doc comment that says where its shape comes from.
- [ ] **Step 4: Run them to verify they pass.** Expected: the suite passes, 3 new tests. Then check that one can fail: decoding the array in one go again fails `malformedStationIsSkippedAndTheRestLoad`. Restore the file.
- [ ] **Step 5: Typecheck.** Expected: 0 errors, 8 warnings (`StationResponse`'s conformance warning is gone).
- [ ] **Step 6: Run the default test plan.** Expected: `** TEST SUCCEEDED **`, 70 passed (44 + 9 + 10 + 4 + 3), 0 skipped.
- [ ] **Step 7: Commit** `fix: decode stations one by one, skipping and logging any that can't be read (#20)`

### Task 5: Record the fix, and check each failure on a simulator

**Files:**
- Modify: `CHANGELOG.md`, `[Unreleased]`
- Modify: `README.md:39` (the `NetworkEngine/` line of the layout)
- Modify: `docs/reference/ns-api.md:33-45` (the decoded fields)
- Modify: this plan (Measurements)

- [ ] **Step 1: `CHANGELOG.md`.** Under `### Fixed`, append:
  - When the station list can't be loaded, the message says why: no key stored, a stored key that can't be read right now, a key NS rejected, a key over its usage limit, too many requests, NS unavailable, no connection, or data this version can't read. Before, a Keychain problem and a usage limit both read as a missing key, and a failed name lookup read as an NS server error.
  - A load or key check that is cut short, for example by leaving Settings while it checks the key, no longer counts as a failure.
  - Retries follow NS's `Retry-After`, up to three attempts. A wait longer than 10 seconds fails at once instead of keeping the screen loading. Key, permission and data errors aren't retried, and a failure is logged once instead of once per attempt.
  - After NS rejects an API key, the app doesn't send it again until a different key is saved. After a refusal for usage (403), it waits 15 minutes before sending the same key again.
  - A station the app can't read is skipped and logged instead of failing the whole list. The medium name, which no screen shows, may be missing.

  Under `### Removed`, append:
  - The client-side limit of 30 requests a minute, which delayed loads during an outage and counted requests that were never sent.
- [ ] **Step 2: `README.md`.** The `NetworkEngine/` line reads "Network errors, retry timing, refused-key memory".
- [ ] **Step 3: `docs/reference/ns-api.md`.** Mark `names.medium` and `tracks` as decoded but unused. Say that the app reads stations one at a time and skips, with a log line, any it can't read.
- [ ] **Step 4: Build and stub.** Build a Debug app of this branch for the throwaway iPhone 15 (x86_64 simulator), with its own `-derivedDataPath` outside the repo. Make a scratch copy of the offline review stub (`.superpowers/scratch/review/runtime/stub/`), outside the repo, that still answers only `gateway.apiportal.ns.nl` and never forwards a request. It reads `REVIEW_STUB_STATUS`, `REVIEW_STUB_RETRY_AFTER` and `REVIEW_STUB_FAIL` (a `URLError` code to fail with), and logs each request as `REVIEWSTUB request #n <path> -> <status or error>`. Build it for x86_64 with `xcrun --sdk iphonesimulator clang`. Every launch uses `SIMCTL_CHILD_NS_API_KEY=dummy-key`, `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=<copy>` and `-homeStationCode ASD`, as in `docs/superpowers/plans/2026-10-28-remove-dead-key-path.md`, Task 2, Step 3. Never use a real key. Stream `log stream --predicate 'subsystem == "annisu.inspirail" OR subsystem == "review.stub"'`. Boot the simulator only for this step and Step 6, and shut it down between them.
- [ ] **Step 5: One launch per case.** Wait until Discover settles, then screenshot it as `20-<case>.png` in the session's scratch directory. Count the stub's requests.
  - Expected: 401 gives "NS didn't accept your API key. Check it in Settings.", 1 request. 403 gives "NS refused your API key…", 1 request.
  - 429 with `Retry-After: 30` gives "NS is getting too many requests…" at once, 1 request. 429 with `Retry-After: 3` gives the same after about 6 s, 3 requests.
  - 503 gives "NS isn't available right now…" after about 3 s, 3 requests.
  - A list with one station missing `location` shows a station, 1 request, and one "Skipped station" line naming its code.
  - No internet (`-1009`) gives "Can't reach NS…", 1 request. A failed DNS lookup (`-1003`) gives the same, 3 requests. On `main`, `-1003` gave "Server error (503)".
  - No log line contains `dummy-key`.
- [ ] **Step 6: The 401 tab count.** In a scratch worktree of this branch, add a throwaway XCUITest driver to `InspiRailUITests/`, and add that target to the worktree's test plan and the scheme's testables. The driver launches with the 401 stub, waits on Discover, then makes 5 rounds of Logbook → Settings → Discover, 2 s each. It runs with `-parallel-testing-enabled NO`, on the throwaway simulator, with nothing else booted. Expected: 1 request in all (on `main` there would be one per Discover, Logbook and Settings visit). Settings shows "Configured key isn't working".
- [ ] **Step 7: Clean up.** Delete the worktree, the derived data, the stub copy's build, any test clones (`xcrun simctl --set ~/Library/Developer/XCTestDevices list devices`), the simulator once the last test run is done, and any crash reports the runs left in `~/Library/Logs/DiagnosticReports/`.
- [ ] **Step 8: Commit** `docs: record clear network errors and retries in the changelog, README and API reference (#20)`

## Measurements

To be filled in during Task 5.
