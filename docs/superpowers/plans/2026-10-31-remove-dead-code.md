# Remove the dead code (#16) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The code that never runs or has no effect is gone. The app does exactly what it did before, and the logbook's stored schema doesn't change.

**Architecture:** Deletion only, in three code tasks and one docs task. Task 1 deletes the files nothing uses. Task 2 removes event tracking and every call to it. Task 3 removes unused members from types that stay. Task 4 updates the docs and checks the running app. Where a removal leaves a live line without its dead caller, that line changes only as much as the removal needs.

**Tech Stack:** Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, SwiftUI, SwiftData, Swift Testing, `xcodebuild`, `xcrun simctl`.

**Spec:** issue #16, https://github.com/andreisudarikov19/InspiRail/issues/16. Its line numbers refer to 8c02931. Every item was checked against `main` at 378233e (after #14 and #15). All of them are still there, and none has gained a caller in the app, the tests, previews or the README.

## Global Constraints

- No change a user can see or feel. Every message, request, log line in Debug builds and stored visit stays as it is. Release builds lose only the analytics log lines.
- `VisitedStation`'s stored fields stay: `stationCode`, `stationName`, `dateVisited`, `notes`, `rating`, `_isFavorite`. Removing a stored field changes the SwiftData schema, and only #17's versioned schema may do that.
- #15's test-host gate stays as it is: `isHostingUnitTests`, the early return in `init()`, and the `Color.clear` scene with its in-memory store.
- Out of scope, and left as they are: the store wipe and `VisitedStationMigration.swift` (#17); the per-screen `StationsRepository` and session (#18); Settings' key check and the rest of `BackendHealthMonitor` (#19); error mapping and retries in `BackendAPI` (#20); failed-load states (#21); the rest of the README (#28).
- Typecheck after every task: `xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios26.2-simulator -swift-version 5 -default-isolation MainActor $(find InspiRail -name '*.swift')`. On `main` it prints 0 errors and 19 warnings (38 `warning:` lines, since each warning is echoed under its source line). No task may add a warning.
- Commit subjects end with `(#16)`. Blank lines inside the app's code are indented to the enclosing level.

## Decisions taken here (the issue left them open)

1. **`NetworkError`: remove `noData`, `failureReason`, `recoverySuggestion` and `isRetryable`.** `noData` is never thrown. `failureReason` and `recoverySuggestion` reach the user only through `NSError`'s `localizedFailureReason` and `localizedRecoverySuggestion`, which nothing reads, and `localizedDescription` never falls back on them because `errorDescription` returns a string for every case. #20 doesn't build on `isRetryable` as it stands. #20 adds new cases (Keychain unavailable, 403, offline or unreachable) and retries a 429 after its `Retry-After`. `isRetryable` calls `.rateLimited` not retryable, and calls timeouts and lost connections retryable, though no code retries them. #20 would have to rewrite it.
2. **`DiscoveryViewModel.refresh()`: remove.** #21 asks for a Retry action and pull to refresh on Discover. Both can call `loadStations(forceRefresh: true)`, which stays, and `refresh()` only wraps that call. The unreachable `guard let repository … throw` goes too. The view model still creates its `StationsRepository` on the first load and keeps it for later loads.
3. **`VisitedStation`: remove only the computed helpers.** These are `isFavorite` (the get/set wrapper around `_isFavorite`) and the extension with `isVisitedToday`, `isVisitedThisWeek` and `daysSinceVisit`. The initialiser keeps its `isFavorite:` parameter, which sets `_isFavorite`: it is the live initialiser, and the parameter isn't a schema change. On `main`, the `@Model` expansion lists exactly the six stored fields, without the computed `isFavorite`. Task 3 checks that this list is unchanged.
4. **Analytics: two of the four `AppConfiguration.Features` flags are unused.** `enableAnalytics` (read only by `AnalyticsManager`) and `enableCrashReporting` (read nowhere) go. `enableNetworkLogging` and `enableDetailedLogging` stay, because `BackendAPI` reads them for its Debug request logging. All 9 `track` calls go: the launch event in `InspiRailApp`, 4 in `BackendAPI`, 2 in `StationsRepository` and 2 in `BackgroundRefreshManager` (deleted in Task 1). `BackendAPI`'s `startTime` goes too, since it only timed the success event.
5. **`BackendHealthMonitor`: the listed members, and the report's private inputs.** The listed members are `hasNetworkConnection`, the actor's `connectionType`, `lastResponseTime` with its one write, `HealthStatus.unknown`, `DiagnosticReport` and `generateDiagnosticReport()`. The private `deviceModel`, `osVersion` and `lastHealthCheck` (with its two writes), and `import Darwin`, go with them. Only the report read them, and leaving them would leave new dead code. `HealthReport`, `checkHealth()` and the path monitor stay for #19.
6. **Leftover mentions in kept files are corrected.** These are the comment on `AppConfiguration.subsystem` ("background task ids"), the `BackendHealthMonitor.swift` header ("and diagnostics") and the notes at the top of `docs/design/proof-of-concept.md`, which describe the code as it is today and point at `Models/Disruption.swift`. The rest of the design document is the original design, and it stays.
7. **`contents.xcworkspacedata` keeps only its `self:` entry**, which is what Xcode writes for a new project. None of the six other entries exists in the repo.

## Review Focus

1. **The logbook must survive the upgrade.** A schema change would send an existing store into `createModelContainer()`'s delete path (#17). Task 3, Step 3 compares the `@Model` schema metadata with `main`'s. Task 4, Step 5 opens a store written by a `main` build with this branch's build.
2. **Error messages must read exactly as before.** In `BackendAPI`, the `catch let error as NetworkError` arm must still rethrow unchanged, so that a `NetworkError` isn't wrapped in `.unknown`. `errorDescription` may lose only its `.noData` arm. To check in review: the diff of `BackendAPI.swift` and `NetworkError.swift`.
3. **Debug request logging must keep working.** It depends on the two flags that stay. Task 4, Step 5 expects one `🌐 Request: /nsapp-stations/v3` line.
4. **The test host must still skip all startup work.** Task 2, Step 3 runs `TestHostTests` with the rest of the plan.
5. **Discover must still load and pick a station after the `guard` goes.** Task 4, Step 5 launches straight into Discover.

---

### Task 1: Delete the files nothing uses

**Files:**
- Delete: `InspiRail/BackgroundRefreshManager.swift`, `InspiRail/NetworkMonitor.swift`, `InspiRail/NetworkEngine/NetworkManager.swift` (with the global `networkLog`), `InspiRail/Models/Disruption.swift`, `InspiRail/Models/RouteModels.swift`
- Modify: `InspiRail/BackendAPI.swift:103-112`: delete `request(_:as:)`, the only caller of which was `NetworkManager`. The private `request(url:as:retryCount:)` stays.
- Modify: `InspiRail/AppConfiguration.swift:13-15`: the `subsystem` comment lists "the logger subsystem and dispatch queue labels".
- Modify: `InspiRail.xcodeproj/project.xcworkspace/contents.xcworkspacedata`: keep only the `self:` `FileRef`.

**Interfaces:**
- Consumes: nothing.
- Produces: nothing. The `NWInterface.InterfaceType.description` extension goes with `NetworkMonitor.swift`. `BackendHealthMonitor` uses its own `connectionTypeDescription`.

- [x] **Step 1: Delete the five files and make the three edits.**
- [x] **Step 2: Typecheck.** Expected: 0 errors, 18 warnings (`NetworkManager`'s `networkLog` warning is gone).
- [x] **Step 3: Commit** `refactor: delete the never-started managers, the network shim and the unused models (#16)`

### Task 2: Remove event tracking

**Files:**
- Delete: `InspiRail/AnalyticsManager.swift`
- Modify: `InspiRail/AppConfiguration.swift:95-101`: delete `enableCrashReporting` and `enableAnalytics`.
- Modify: `InspiRail/BackendAPI.swift`: delete `startTime` (`:117`) and the 4 `track` calls (`:164-166`, `:219-227`). The `200...299` arm returns `decodeResponse(data:type:)`. Each `catch` arm keeps its pattern and throws what it threw before.
- Modify: `InspiRail/ViewModels/StationsRepository.swift:36`, `:42`: delete the cache hit and cache miss `track` calls.
- Modify: `InspiRail/InspiRailApp.swift:33-36`: delete the `.task` with the launch event. `MainTabView().modelContainer(createModelContainer())` and the test-host gate stay unchanged.

**Interfaces:**
- Consumes: Task 1, which deleted `BackgroundRefreshManager` and its two `track` calls. Without it, this task doesn't compile.
- Produces: `AppConfiguration.Features` with only `enableDetailedLogging` and `enableNetworkLogging`.

- [x] **Step 1: Make the changes.**
- [x] **Step 2: Typecheck.** Expected: 0 errors, 14 warnings (`AnalyticsManager`'s 4 are gone).
- [x] **Step 3: Run the default test plan**

  Run: `xcodebuild test -project InspiRail.xcodeproj -scheme InspiRail -destination 'platform=iOS Simulator,name=iPhone 17'`
  Expected: `** TEST SUCCEEDED **`, 17 tests passed, including the 3 `TestHostTests`.

- [x] **Step 4: Commit** `refactor: remove event tracking, which reached no analytics service (#16)`

### Task 3: Remove the unused members

**Files:**
- Modify: `InspiRail/NetworkEngine/NetworkError.swift`: delete `case noData` and its `errorDescription` arm, and delete `failureReason`, `recoverySuggestion` and `isRetryable`.
- Modify: `InspiRail/ViewModels/StationsRepository.swift:53-81`: delete `station(byCode:)`, `search(query:country:)` and `clearCache()`. (`DiscoveryViewModel.getStation(byCode:)` is a different method, used by Discover. It stays.)
- Modify: `InspiRail/KeychainManager.swift:192-253`: delete the "Generic Keychain Storage" section (`save(_:forKey:)`, `get(forKey:)`, `delete(forKey:)`). Every `KeychainError` case is still thrown by the API-key methods.
- Modify: `InspiRail/Models/VisitedStation.swift`: the header names `VisitedStation.swift`. Delete the computed `isFavorite` and the "Convenience Extensions" extension. The comment above `_isFavorite` says that it, `notes` and `rating` are unused but part of the stored schema, so they go only with a versioned schema (#17).
- Modify: `InspiRail/Models/Station.swift`: add the standard header with a one-line description, as in `APIKeyProvider.swift`.
- Modify: `InspiRail/ViewModels/DiscoveryViewModel.swift:36-43`, `:105-107`: delete `refresh()`. The `if repository == nil` block and the `guard` become a non-optional local that is stored back, so the first load creates the repository and later loads reuse it.
- Modify: `InspiRail/BackendHealthMonitor.swift`: the members in Decision 5. The header drops "and diagnostics".

- [x] **Step 1: Make the changes.**
- [x] **Step 2: Typecheck.** Expected: 0 errors, 13 warnings (the `async` warning in `generateDiagnosticReport()` is gone).
- [x] **Step 3: Check that the stored schema is unchanged**

  Run: the typecheck command with `-Xfrontend -dump-macro-expansions`, then `grep -E 'PropertyMetadata\(name: .*\\VisitedStation\.' | sort -u`, on this branch and on `main`.
  Expected: the same 6 lines on both: `stationCode` (with `.unique`), `stationName`, `dateVisited`, `notes`, `rating`, `_isFavorite`.

- [x] **Step 4: Run the default test plan.** Expected: as in Task 2, Step 3.
- [x] **Step 5: Commit** `refactor: remove unused members from the network, storage, model and view-model types (#16)`

### Task 4: Update the docs, and check the app still works

**Files:**
- Modify: `README.md:45-47`: delete the layout lines for `BackgroundRefreshManager.swift`, `NetworkMonitor.swift` and `AnalyticsManager.swift`.
- Modify: `CHANGELOG.md`, `[Unreleased]`, `### Removed`
- Modify: `docs/design/proof-of-concept.md:7`, `:9`, `:11`

- [ ] **Step 1: README layout.** Delete only the three lines.

- [ ] **Step 2: `CHANGELOG.md`, `[Unreleased]`, `### Removed`.** Append:
  - Code that never ran: the background refresh (`BackgroundRefreshManager`), which was never registered or scheduled, the network monitor (`NetworkMonitor`), which nothing created, and the deprecated `NetworkManager` shim.
  - Event tracking (`AnalyticsManager`) and its unused feature flags. No analytics service was connected. Release builds only wrote the events to the log, and Debug builds dropped them.
  - The disruption and route models, which nothing fetched.
  - Unused members of `NetworkError`, `StationsRepository`, `KeychainManager`, `VisitedStation`, `DiscoveryViewModel` and `BackendHealthMonitor`. `VisitedStation`'s stored fields stay, so the logbook's storage is unchanged.
  - Six files listed in the Xcode workspace that don't exist.

- [ ] **Step 3: Design notes.**
  - **Database:** only `Station` is decoded from the API.
  - **Disruption model:** the app has none, and nothing fetches disruptions yet.
  - **Service classes:** there's no `NetworkManager`, `StationService` or `PersistenceManager`.

- [ ] **Step 4: Check for leftovers**

  Run: `git grep -nE "BackgroundRefreshManager|NetworkMonitor|AnalyticsManager|enableAnalytics|enableCrashReporting|NetworkManager|networkLog|noData|isRetryable|failureReason|recoverySuggestion|station\(byCode|search\(query|clearCache|forKey|Disruption\.swift|DisruptionsResponse|RouteModels|RouteResponse|RouteLeg|RouteLocation|RouteMessage|isVisitedToday|isVisitedThisWeek|daysSinceVisit|refresh\(\) async|hasNetworkConnection|lastResponseTime|lastHealthCheck|DiagnosticReport|generateDiagnosticReport|Visited Station\.swift|BackendAPI 2|StationsRepository 2|RoutesRepository|DisruptionsRepository|BACKEND_REVIEW" -- . ':!docs/archive'`
  Expected: hits only in `CHANGELOG.md` (the 1.3.0 entry and the new one), in `docs/superpowers/plans/`, and in `docs/design/proof-of-concept.md`: the original design's `NetworkManager`, and the note saying the app has none.

- [ ] **Step 5: Launch check with the offline review stub.** The stub answers the NS gateway with a synthetic station list and never reaches the network. It is a local review tool kept outside the repo (`.superpowers/` is excluded from git), so this step runs only where the tool is installed. Use a dummy key, never a real one. Build a Debug app from `main` (in a scratch worktree) and from this branch. On a throwaway iPhone 17 simulator (iOS 26.3), as in `launch-check.sh`:
  1. Install the `main` build, and launch it once with the dummy key. This primes the Keychain and creates `default.store`.
  2. Install this branch's build over it, and launch it while streaming `subsystem == "annisu.inspirail" OR subsystem == "review.stub"`. Take a screenshot.
     Expected: the onboarding station list, one `REVIEWSTUB request … -> 200`, one `🌐 Request: /nsapp-stations/v3`, and no `Failed to create ModelContainer`.
  3. Relaunch with the launch argument `-homeStationCode UT`, and take a screenshot.
     Expected: Discover shows a station.

  Then delete the simulator.

- [ ] **Step 6: Commit** `docs: drop the deleted files from the README and record the removals in the changelog (#16)`
