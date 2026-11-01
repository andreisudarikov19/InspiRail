# One shared station store (#18) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app downloads the station list once and shares it, for an hour, with every screen and window, through one network session. Screens that load at the same time share one download, and the Dutch-station filter and name sort are written once.

**Architecture:** `InspiRailApp.init` creates one `StationsRepository` with one `BackendAPI`, next to the `Logbook`, and puts it in every window's environment. The repository keeps only a successful download, lets concurrent callers share the one in flight, and hands out the Dutch stations sorted by name and their count. `BackendAPI` builds its one session when it is created, with no `URLCache`, and still reads the API key for each request. Settings' key check keeps its own request, through the shared API.

**Tech Stack:** Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, SwiftUI (`@Entry` environment values), Swift concurrency (actors, `Task`), `URLSession` and `URLProtocol`, Swift Testing, `xcodebuild`, `xcrun simctl`.

**Spec:** issue #18, https://github.com/andreisudarikov19/InspiRail/issues/18 (its line numbers refer to 8c02931), and the owner's direction for its open choices, recorded under Decisions below. Every item was checked against `main` at e8e110a (after #14 to #17). The Debug startup check the issue names is gone (#14). The code is now at `InspiRail/ViewModels/StationsRepository.swift:12-51`, `InspiRail/BackendAPI.swift:29-77`, `InspiRail/Pages/VisitedListView.swift:65,118-130`, `InspiRail/Pages/SettingsView.swift:160-172,236-253`, `InspiRail/Pages/OnboardingView.swift:158-175`, `InspiRail/ViewModels/DiscoveryViewModel.swift:22,31-43` and `InspiRail/BackendHealthMonitor.swift:98-113`.

## Global Constraints

- Every screen shows what it shows on `main`: the same stations, in the same order, with the same count and the same messages. The only differences a user can notice are fewer downloads and faster screens.
- `InspiRailApp.init` is the only place that creates a `StationsRepository` or a `BackendAPI`. Tests create their own.
- #15's test-host gate stays: `isHostingUnitTests`, the early return in `init()`, and the `Color.clear` scene. While hosting the unit tests the app creates no repository, no API and no session, and starts no fetch.
- Tests never reach the network. Every request in a test goes through a session whose only protocol class is the test stub.
- Out of scope, and left as they are: what Settings' key check reports (#19), error mapping, retries and the rate limiter's tuning (#20), failed loads and the offline wait (#21), onboarding (#22, #42), the home station's counting (#23), visits (#24), search and the apostrophe sort (#25), Randomize (#29), keeping the list between launches (#36), the Logbook UI (#37).
- Typecheck after every task: `xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios26.2-simulator -swift-version 5 -default-isolation MainActor $(find InspiRail -name '*.swift')`. On `main` it prints 0 errors and 13 warnings (26 `warning:` lines, since each is echoed under its source line). No task may add a warning. Task 1 removes two (`memoryCacheSize`, `diskCacheSize`).
- Test command: `xcodebuild test -project InspiRail.xcodeproj -scheme InspiRail -destination 'platform=iOS Simulator,name=<throwaway simulator>' -derivedDataPath <scratch>`. On `main`: `** TEST SUCCEEDED **`, 33 tests passed.
- Commit subjects end with `(#18)`. Blank lines inside the app's code are indented to the enclosing level. Test files keep their empty blank lines.

## The four copies of the filter and the sort

| Where (`main`, e8e110a) | Filter | Sort | What the user sees |
|---|---|---|---|
| Logbook, `VisitedListView.refreshTotalStationCount()`, `VisitedListView.swift:118-130` | `country == "NL"` | none | The count, as "N of total" and a percentage, kept in `cachedTotalStations` when above 0 |
| Home Station picker, `StationSelectorView.fetchStations()`, `SettingsView.swift:239-253` | `country == "NL"` | `names.long <` | The list, in that order |
| Onboarding, `OnboardingView.loadStations()`, `OnboardingView.swift:158-175` | `country == "NL"` | `names.long <` | The list, in that order |
| Discover, `DiscoveryViewModel.loadStations(forceRefresh:)`, `DiscoveryViewModel.swift:35-43` | `country == "NL"` | none (API order) | One station from `randomElement()`, and the home station found by code with `first(where:)` |

The filter is the same in all four. Only the sort differs, and no screen can show the difference: the Logbook shows a count, which the order can't change, and Discover never shows the order. Its pick is uniform over the same set whatever the order, and its lookup is by code, which is unique (`Station.id` is the code and is already the list identity in both pickers). So the shared list is the sorted form, with the plain `<` comparison the pickers use (#25 changes it), and each screen's visible result stays as it is. Settings' key check (`BackendHealthMonitor.swift:113`) doesn't filter; it only checks that the request succeeds.

## Decisions

1. **One repository, one API, one session.** `InspiRailApp` holds `@State private var stationsRepository: StationsRepository?`, set in `init()` after the test-host guard to `StationsRepository(backend: BackendAPI())`, next to the `Logbook`. Every window's root gets it with `.environment(\.stationsRepository, stationsRepository)`, and the screens read it from there. Reason: one instance means one cache, one session (so connections are reused) and one limiter, and every window shares them. The environment value is optional, with `nil` as its default, so reading it never builds a store. It is `nil` only while hosting the unit tests, where no screen exists, so a test run starts no fetch. A screen that finds no store loads nothing. Sheets and pushed views inherit it, so onboarding's Settings sheet and the Home Station picker use the same store.
2. **One request in flight, and only a success is kept.** The repository keeps the running download as a `Task`. A caller that finds one waits for it instead of starting another. The task stores the list and clears itself before it finishes, so a caller arriving after a failure starts a new request, and one arriving after a success reads the stored list. A screen that goes away doesn't cancel the download, since other screens may be waiting for it. As a result, leaving Discover mid-load no longer ends that load in the "cancelled" error that #20 describes; #20 still owns cancellation everywhere else. `forceRefresh` skips the stored list but still joins a download in flight, which is fresh anyway.
3. **The API key is read for each request.** It already is: `BackendAPI.request` calls `keyProvider.currentKey()` before every attempt, and `APIKeyProvider` reads the Keychain each time. Only the `NS_API_KEY` launch-environment override is read once, when the provider is created, and the environment can't change while the app runs. So a key saved in Settings is used by the next request without a relaunch. Tests pin it at the API and at the repository, and Task 4 checks it on a simulator.
4. **One place for the Dutch stations.** The repository provides `dutchStations()` (filtered to `country == "NL"`, sorted by `names.long <`) and `dutchStationCount()`. The four screens read them, and the copies above go. The repository no longer offers the unfiltered list, which nothing else used.
5. **No `URLCache`.** The session's requests use `.reloadIgnoringLocalCacheData`, so the 10 MB / 50 MB cache was written and never read. The configuration sets `urlCache = nil`, and `AppConfiguration.API.memoryCacheSize` and `diskCacheSize` go. The repository's in-memory list is the cache. Keeping it between launches is #36.
6. **The rate limiter now engages, and no named flow is refused or held up at a person's pace.** What it does (`BackendAPI.swift:233-254`, unchanged): before every attempt, retries included and before the key is read, it drops timestamps older than 60 s. If 30 (`maxRequestsPerMinute`) remain, it sleeps until the oldest is 60 s old, then records the attempt and goes on. It never refuses; it only waits, and a wait whose task is cancelled throws `CancellationError`. On `main` each screen load had its own API, so a limiter saw at most four attempts and never waited. Now every attempt in the app counts against one limiter.
   - Settings' key check: one attempt per Settings visit and per saved key (three against a 5xx, four against a 429).
   - Try Again after a failed load (coming back to Discover or the Logbook, or closing onboarding's Settings sheet): failures aren't kept, so each load tries again, with one attempt against a 401 or with no key, three against a 5xx and four against a 429.
   - Discover right after onboarding: no attempt; it reads onboarding's list.

   A wait needs 30 attempts within 60 s. With the list loaded, only Settings' key check makes requests, so that takes 30 Settings visits in a minute. While NS answers with a 5xx, each failed load makes three attempts, so a visit to a tab every six seconds for a minute would make the next load wait up to a minute before it fails or succeeds. That case needs an outage and comes from #20's retries; #20 also decides whether the limiter stays ("drop the client-side limiter, or move it into the single shared client"). This plan doesn't retune it, and the report flags the outage case for #20.
7. **Settings' key check keeps its own request, through the shared API.** `BackendHealthMonitor.checkHealth(using:)` takes the shared `BackendAPI` (Settings passes `stationsRepository.backend`) instead of creating one. It still downloads the list to test the key, doesn't read or fill the store's list, and reports exactly what it reports on `main` (#19). Consequence for the measurement: each Settings visit still makes one request, so 20 rounds of Logbook → Settings → Discover make 20 requests, all key checks, instead of 40. The station store itself downloads once.

## Review Focus

1. **A screen left mid-load must not cancel the download other screens wait for, or leave the store stuck.** Pinned by Task 2's `leavingScreenKeepsTheSharedDownload`.
2. **A key saved in Settings after a rejected one must be used by the next load, without a relaunch.** Pinned by Task 1's `changedKeyIsUsedByTheNextRequest` and Task 2's `rejectedKeyIsNotKeptAndTheNextLoadUsesTheNewKey`, and checked on a simulator in Task 4, Step 6, through the Settings tab and through onboarding's Settings sheet.
3. **Each screen must show the same stations, in the same order, with the same count as on `main`.** Pinned by Task 2's `dutchStationsAreFilteredAndSortedByName` (with an apostrophe name, which the plain sort puts first until #25), and checked with screenshots in Task 4, Step 7.
4. **A unit-test run must start no fetch.** The store is created only after the test-host guard, and the environment's default builds nothing: Task 3's `environmentHasNoStoreByDefault`, the leftover check in Task 3, Step 4, and the 3 `TestHostTests`.
5. **No screen or sheet may build its own store or API again.** Task 3, Step 4: `git grep` finds `StationsRepository(` and `BackendAPI(` only in `InspiRailApp.swift`. Task 4, Step 6 checks that onboarding's Settings sheet reaches the shared API.

---

### Task 1: `BackendAPI` builds one session without a URL cache, and reads the key for each request

**Files:**
- Modify: `InspiRail/BackendAPI.swift:11-77` (init, session)
- Modify: `InspiRail/AppConfiguration.swift:46-49` (delete `memoryCacheSize` and `diskCacheSize`)
- Create: `InspiRailTests/StubURLProtocol.swift`
- Test: `InspiRailTests/StationStoreTests.swift`

**Interfaces:**
- Consumes: `APIKeyProvider(keychain:environment:allowsEnvironmentOverride:)`, `KeychainManager(service:)`, `removeKeychainItems(service:)` and `.requiresKeychain` from the test target.
- Produces:
  - `init(keyProvider: APIKeyProvider? = nil, sessionConfiguration: URLSessionConfiguration = .default)`. `nil` means the app's provider, built as today (the shared Keychain, and the launch environment in Debug builds). The API applies its own settings to the configuration and creates the session once, in `init`. `.default` keeps working with the offline review stub, which hooks `+[NSURLSessionConfiguration defaultSessionConfiguration]`.
  - `let session: URLSession`, with `requestCachePolicy == .reloadIgnoringLocalCacheData` and `urlCache == nil`. The other settings are unchanged: timeouts 30 s and 60 s, `waitsForConnectivity`, cellular, expensive and constrained access allowed, 4 connections per host, no cookies.
  - Test target: `final class StubURLProtocol: URLProtocol` with `struct Reply { let status: Int; let body: Data }`, `Reply.stations` (200 with the fixture) and `Reply.status(_:)` (that status, body `{}`), and statics `configuration() -> URLSessionConfiguration` (an ephemeral configuration whose only protocol class is the stub), `reset(replies: [Reply] = [.stations])` (forgets the requests; replies are used in order and the last repeats), `requests: [URLRequest]`, `hold()`, `release()` and `waitForRequests(_ count: Int) async`. A held request is answered at `release()`, on the run loop its `startLoading()` ran on (`CFRunLoopPerformBlock` and `CFRunLoopWakeUp`). The state is behind an `NSLock`. `canInit` returns `true` for every request. The fixture has six stations: `UT` "Utrecht Centraal", `ASD` "Amsterdam Centraal", `HT` "'s-Hertogenbosch", `ZL` "Zwolle" (all `NL`), `BHF` "Berlin Hbf" (`D`) and `BRUZ` "Brussel-Zuid" (`B`), in that order.

- [x] **Step 1: Write the failing tests.** A suite `@Suite("Station store", .serialized) final class StationStoreTests`, serialized because the stub's state is shared. `init()` calls `StubURLProtocol.reset()` and makes a throwaway `KeychainManager(service: "test.<UUID>.stations")`. `deinit` calls `removeKeychainItems(service:)`. A helper `api(keyProvider:)` returns `BackendAPI(keyProvider:sessionConfiguration: StubURLProtocol.configuration())`. The default provider is `APIKeyProvider(keychain: keychain, environment: ["NS_API_KEY": "test-key"], allowsEnvironmentOverride: true)`, which works with or without a usable Keychain. Tests:
  - `sessionKeepsNoURLCache`: `await api().session.configuration` has `urlCache == nil` and `requestCachePolicy == .reloadIgnoringLocalCacheData`.
  - `changedKeyIsUsedByTheNextRequest` (`.requiresKeychain`): a provider with `environment: [:]`. Save `"first-test-key"`, call `getStations()`, save `"second-test-key"`, call it again on the same API. Expect the stub's requests' `Ocp-Apim-Subscription-Key` values to be `["first-test-key", "second-test-key"]`.
- [x] **Step 2: Run them to verify they fail.** Run the test command with `-only-testing:InspiRailTests/StationStoreTests`. Expected: a build failure, `extra arguments at positions #1, #2 in call` or similar, since `BackendAPI.init` takes none.
- [x] **Step 3: Implement the init and the session** as in Interfaces. Delete `memoryCacheSize` and `diskCacheSize` from the API and from `AppConfiguration.API`. The comment on the cache policy says that the session keeps no cache because its requests ignore cached data, and that the station store keeps the list (#18).
- [x] **Step 4: Run them to verify they pass.** Expected: 2 passed. Then check that the key test can fail: a mutant API that keeps the first key it reads makes `changedKeyIsUsedByTheNextRequest` fail. Restore the file.
- [x] **Step 5: Typecheck.** Expected: 0 errors and 11 warnings, all of kinds already on `main`.
- [x] **Step 6: Commit** `refactor: build the API session once, without its unused URL cache, and make its key provider injectable (#18)`

### Task 2: The repository shares one download, keeps only a success, and provides the Dutch stations

**Files:**
- Modify: `InspiRail/ViewModels/StationsRepository.swift` (rewrite the body)
- Modify: `InspiRail/Pages/VisitedListView.swift:118-130`, `InspiRail/Pages/SettingsView.swift:239-253`, `InspiRail/Pages/OnboardingView.swift:158-175`, `InspiRail/ViewModels/DiscoveryViewModel.swift:35-45`: read the new methods. Each still creates its own `StationsRepository(backend: BackendAPI())` until Task 3.
- Test: `InspiRailTests/StationStoreTests.swift`

**Interfaces:**
- Consumes: Task 1's `BackendAPI.init(keyProvider:sessionConfiguration:)` and `StubURLProtocol`.
- Produces:
  - `actor StationsRepository { init(backend: BackendAPI) }`
  - `let backend: BackendAPI`
  - `func dutchStations(forceRefresh: Bool = false) async throws -> [Station]`: the stations with `country == "NL"`, sorted by `names.long <`, from the stored list while it is younger than `AppConfiguration.API.cacheLifetime` (an hour), otherwise from the download in flight or a new one.
  - `func dutchStationCount() async throws -> Int`
  - `stations(forceRefresh:)` is removed.

- [x] **Step 1: Write the failing tests** in the same suite. A helper `repository(keyProvider:)` wraps Task 1's `api(keyProvider:)`. Tests:
  - `concurrentCallersShareOneRequest`: `StubURLProtocol.hold()`. Start `async let first = repository.dutchStations()`, `await StubURLProtocol.waitForRequests(1)`, then `async let count = repository.dutchStationCount()`. Sleep 300 ms and expect 1 request. `release()`. Expect `first` to be the four Dutch stations, `count == 4`, and still 1 request.
  - `secondConsumerGetsTheStoredList`: `dutchStations()`, then `dutchStationCount()` and `dutchStations()` again. Expect 1 request and the same codes both times.
  - `failedDownloadIsNotKept`: `reset(replies: [.status(404), .stations])`. The first `dutchStations()` throws `NetworkError`. The second returns the four stations. Expect 2 requests.
  - `rejectedKeyIsNotKeptAndTheNextLoadUsesTheNewKey` (`.requiresKeychain`): `reset(replies: [.status(401), .stations])`, a provider with `environment: [:]`. Save `"rejected-test-key"`; `dutchStations()` throws `NetworkError.unauthorized`. Save `"accepted-test-key"`; `dutchStations()` returns the four stations. Expect the requests' keys to be `["rejected-test-key", "accepted-test-key"]`.
  - `leavingScreenKeepsTheSharedDownload`: `hold()`. Start `let leaving = Task { try await repository.dutchStations() }`, wait for 1 request, `leaving.cancel()`. Start `async let staying = repository.dutchStations()`, sleep 300 ms, `release()`. Expect `staying` to be the four stations, and 1 request. Then a third call returns them with still 1 request.
  - `dutchStationsAreFilteredAndSortedByName`: expect the codes `["HT", "ASD", "UT", "ZL"]` (the plain comparison puts the apostrophe name first, as the pickers do until #25), and `dutchStationCount() == 4`.
  (Changed during execution: the suite is `@MainActor`, since `Station` is main-actor isolated in the app module and the tests read its properties.)
- [x] **Step 2: Run them to verify they fail.** `-only-testing:InspiRailTests/StationStoreTests`. Expected: a build failure, `value of type 'StationsRepository' has no member 'dutchStations'`.
- [x] **Step 3: Implement the repository.** State: `private var stored: (stations: [Station], date: Date)?` and `private var download: Task<[Station], Error>?`. `dutchStations` returns the stored list when it is fresh and `forceRefresh` is false, otherwise awaits `download` when there is one, otherwise sets `download = Task { try await fetch() }` and awaits it. `fetch()` runs on the actor: it clears `download` in a `defer`, calls `backend.getStations(includeNonPlannable: false)`, filters and sorts the payload once, and stores the result with the date. Keep the existing debug log lines ("Returning cached stations", "Fetching fresh station data from API", "Cached … stations"), and add one when a caller joins the download in flight. The doc comment says the app creates one for every window (#18).
- [x] **Step 4: Point the four screens at the new methods**, with no other change: the Logbook calls `dutchStationCount()`, the picker and onboarding call `dutchStations()` and drop their filter and sort, and the view model sets `allStations` from `dutchStations(forceRefresh:)`.
- [x] **Step 5: Run them to verify they pass.** Expected: 8 passed in the suite. Then check that the tests can fail: a repository that doesn't join the download in flight fails `concurrentCallersShareOneRequest`, and one that keeps a failed download fails `failedDownloadIsNotKept`. Restore the file.
- [x] **Step 6: Typecheck.** Expected: 0 errors, 11 warnings.
- [x] **Step 7: Commit** `fix: share one station download between callers, keep only a success, and filter the Dutch stations once (#18)`

### Task 3: Create the store once for the whole app, and give every screen and Settings' key check the shared one

**Files:**
- Modify: `InspiRail/InspiRailApp.swift` (the store, the environment entry, the injection)
- Modify: `InspiRail/Pages/VisitedListView.swift`, `InspiRail/Pages/SettingsView.swift`, `InspiRail/Pages/OnboardingView.swift`, `InspiRail/Pages/DiscoveryView.swift:13-58`, `InspiRail/ViewModels/DiscoveryViewModel.swift:20-45`
- Modify: `InspiRail/BackendHealthMonitor.swift:97-113`
- Test: `InspiRailTests/StationStoreTests.swift`

**Interfaces:**
- Consumes: Task 2's `StationsRepository(backend:)`, `backend`, `dutchStations(forceRefresh:)`, `dutchStationCount()`. Task 1's `BackendAPI()`.
- Produces:
  - In `InspiRailApp.swift`: `extension EnvironmentValues { @Entry var stationsRepository: StationsRepository? = nil }`, documented as the app's one station store, set on every window, and `nil` only while hosting the unit tests.
  - `DiscoveryViewModel.loadStations(from repository: StationsRepository, forceRefresh: Bool = false) async`. The view model no longer holds a repository.
  - `BackendHealthMonitor.checkHealth(using backend: BackendAPI) async -> HealthReport`. Its body is unchanged apart from using `backend`.

- [x] **Step 1: Write the failing test.** `environmentHasNoStoreByDefault` (`@MainActor`): `#expect(EnvironmentValues().stationsRepository == nil)`. It pins that reading the value without the App's injection builds nothing.
- [x] **Step 2: Run it to verify it fails.** Expected: a build failure, `value of type 'EnvironmentValues' has no dynamic member 'stationsRepository'`.
- [x] **Step 3: The App.** `@State private var stationsRepository: StationsRepository?`, documented like the `Logbook`'s. In `init()`, after the test-host guard and the logbook: `_stationsRepository = State(initialValue: StationsRepository(backend: BackendAPI()))`. In the `WindowGroup`, `LogbookRootView(logbook: logbook)` gets `.environment(\.stationsRepository, stationsRepository)`. The test-host branch is unchanged.
- [x] **Step 4: The screens.** Each reads `@Environment(\.stationsRepository) private var stationsRepository` and does nothing when it is `nil`. The Logbook, the picker and onboarding call the repository instead of creating one. `DiscoveryView`'s `.task` passes it to `loadStations(from:)`. `SettingsView.refreshKeyStatus()` passes `stationsRepository.backend` to `checkHealth(using:)` when a key is present, and keeps `healthy = true` otherwise, as now. Then check for leftovers: `git grep -nE "StationsRepository\(|BackendAPI\(" -- InspiRail`. Expected: only `InspiRail/InspiRailApp.swift`.
- [x] **Step 5: Typecheck.** Expected: 0 errors, 11 warnings.
- [x] **Step 6: Run the default test plan.** Expected: `** TEST SUCCEEDED **`, 42 tests passed (33 + 2 + 6 + 1), including the 3 `TestHostTests`.
- [x] **Step 7: Commit** `fix: use one station store and one network session for the whole app (#18)`

### Task 4: Record the fix, and measure it on a simulator

**Files:**
- Modify: `CHANGELOG.md`, `[Unreleased]`
- Modify: `README.md:36-45` (the layout's `ViewModels/` and `BackendAPI.swift` lines)

- [x] **Step 1: `CHANGELOG.md`.** Under `### Fixed`, append:
  - The station list is downloaded once and shared by every screen and window for an hour. Opening the Logbook or the Home Station picker no longer downloads it again, Discover no longer downloads it again right after onboarding, and screens that load at the same time share one download. All requests go through one network session, so they reuse its connections.

  Under `### Removed`, append:
  - The network session's response cache (10 MB in memory, 50 MB on disk), which was written and never read.
- [x] **Step 2: `README.md`.** `ViewModels/` reads "View-models, and the station store every screen shares", and `BackendAPI.swift` reads "NS API client (actor) and the app's one network session".
- [x] **Step 3: Builds.** In scratch worktrees of `main` (e8e110a) and of this branch, add a throwaway XCUITest driver to `InspiRailUITests/`, and add the UI target to the worktree's test plan and the scheme's testables. Build each with its own `-derivedDataPath` outside the repo. Create a throwaway iPhone 17 simulator on iOS 26.3 and run the driver on it with `-parallel-testing-enabled NO`, so it runs on that simulator and not a clone. Every launch uses the offline review stub and a dummy key, as in `docs/superpowers/plans/2026-10-28-remove-dead-key-path.md`, Task 2, Step 3: `NS_API_KEY=dummy-key`, `DYLD_INSERT_LIBRARIES=<stub>/ReviewStub.dylib`, `REVIEW_STUB_PAYLOAD=<stub>/stations.json`, set in the driver's `launchEnvironment`. The stub is a local review tool outside the repo, so these steps run only where it is installed. Never use a real key. Requests are counted from the stub's `REVIEWSTUB request #n` lines, streamed with `log stream --predicate 'subsystem == "annisu.inspirail" OR subsystem == "review.stub" OR subsystem == "review.uidriver"'`, between the driver's `UIDRIVER phase=…` markers, as #12 counted them.
  (Changed during execution: each scenario ran with `xcodebuild test-without-building -xctestrun` on a freshly erased simulator, and the driver finds list rows by their button labels, since a lazy list keeps rows off screen out of the accessibility tree.)
- [x] **Step 4: Twenty rounds.** Launch with `-homeStationCode ASD`, wait until Discover shows a station, then 20 rounds of Logbook → Settings → Discover with 2 s on each tab, then open Settings › Home Station once.
  Expected: on `main`, 1 request at launch and 40 in the rounds (20 from the Logbook, 20 key checks), and 1 more for the picker. On the branch, 1 at launch, 20 in the rounds (the key checks, Decision 7, with no "Fetching fresh station data" line) and none for the picker.
  (The driver's check that the picker's rows appeared failed on both builds, for the reason above. The picker had loaded: its log lines are counted under Measurements.)
- [x] **Step 5: Onboarding, then Discover.** On an erased simulator, launch with no home station, wait for the list, tap a station, and wait 10 s on Discover.
  Expected: 2 requests on `main`, 1 on the branch.
- [x] **Step 6: A key changed in Settings.** On an erased simulator, with no key anywhere, use a copy of the stub in the scratch directory that also answers 401 to one dummy key and logs a short hash of each request's key (never the key). Launch with `-homeStationCode ASD`: Discover fails with no key. In the Settings tab, save the rejected dummy key, then a second dummy key, then return to Discover. Then repeat through onboarding's Settings sheet: launch with no home station, Open Settings, save the rejected key, then the other.
  Expected on the branch: the Settings tab shows "Configured key isn't working" after the first key and hides the key section after the second; the stub logs the first key's hash with 401, then the second's with 200 for the key check and for Discover's load, which shows a station. In the sheet, the same two states, with the key checks logged, which shows that the sheet reaches the shared API.
- [x] **Step 7: Screenshots.** On the branch and on `main`, with the stub and `-homeStationCode ASD`, the driver attaches screenshots of Discover, the Logbook and Settings. Export them with `xcrun xcresulttool export attachments`, save them in the session's scratch directory as `18-<screen>-<branch|main>.png`, and compare them.
  Expected: the same layout and text, apart from Discover's random station. The Logbook reads "0 of 400".
  (Added during execution: the Logbook and Settings screenshots are byte for byte the same on both builds below the status bar.)
- [x] **Step 8: Clean up.** Delete the simulator, the scratch worktrees and the derived data.
  (Changed during execution: the clean-up ran after this task's commit, because the final test run needs the simulator.)
- [x] **Step 9: Commit** `docs: record the shared station store in the changelog and README (#18)`

## Measurements

On a throwaway iPhone 17 simulator (iOS 26.3), with the offline review stub and a dummy key. Requests are the stub's `REVIEWSTUB request` lines.

| Scenario | `main` (e8e110a) | This branch |
|---|---|---|
| Launch with a home station | 1 | 1 |
| 20 rounds of Logbook → Settings → Discover | 40: 20 Logbook downloads, 20 key checks | 20: the key checks; the Logbook and Discover read the stored list (40 "Returning cached stations") |
| Then Settings › Home Station | 1 download | 0 (read the stored list) |
| Onboarding, then Discover | 2 | 1 |

A key changed in Settings, on the branch, with a scratch copy of the stub that answers 401 to one dummy key and logs a short hash of each request's key: with no key, Discover fails and nothing is sent. The first key is sent by the key check and rejected, and Settings says "Configured key isn't working". The second is sent by the next key check, which passes and hides the key section, and by Discover's next load, which shows a station. The same two states appear in onboarding's Settings sheet, and onboarding's list loads with the second key once the sheet is closed. No relaunch was needed.

The default test plan passes 42 tests. A run on the simulator itself, with its network log streamed, shows the 10 requests the station-store tests make and no network connection.

## Review fixes

The review found no Critical or Important issues. The owner's rulings on its other findings:

| Finding | Ruling | Commit |
|---|---|---|
| Nothing pins the hour's expiry: the lifetime comes from `AppConfiguration` and the clock is `Date()`, so a store that never expires passes every test, and expiry is now the only thing that refreshes the list. | Inject a clock, `init(backend:now:)`, defaulting to `Date()`, and test first: one request just before the configured lifetime passes, a second at it. A store that never expires fails the test. | 2651c79 |
| The changelog says the list is downloaded once and shared for an hour, but Settings' key check still makes its own request on each visit. | Say so, pointing to #19. | b279e51 |
| A screen that finds no store in its environment loads nothing, silently. | One helper, `reportMissingStationStore(in:)`, logs a fault and stops a Debug build, outside the test host only. The Logbook, Discover, onboarding, Settings' key check and the Home Station picker call it. What each screen shows, and what Settings reports, is unchanged (#19). A test pins that the test host isn't stopped. | c09134d |
| `forceRefresh` has no caller, and this branch gave it new, untested behaviour. | Remove it from the store and from Discover's load. #29 can add what it needs. | 316b0ba |
| `BackendAPI.session` is module-visible with no reason given. | A comment says it is visible for tests, and that app code goes through the API's methods, which read the key and apply the limiter. | dae77b7 |

The consequences of one shared client for the rate limiter, and for failed loads with a rejected key, are recorded on #20. The key check's remaining download, and its timing that includes the limiter's wait, are recorded on #19.

After the fixes: the typecheck prints 0 errors and the same 11 warnings, and the default test plan passes 44 tests (42 + 2). A Debug launch with the offline stub, a dummy key and `-homeStationCode ASD` makes one request and shows a station on Discover. Opening Settings then makes the key check's request, and the Logbook reads the stored list. No fault is logged and no assertion fires.
