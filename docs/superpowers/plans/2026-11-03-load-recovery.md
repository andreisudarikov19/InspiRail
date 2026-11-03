# A way out of every failed station load (#21) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every screen whose station load failed offers one way forward: Retry where trying again can help, and the way to Settings' key section where only a key can. Offline, a load fails at once with "Can't reach NS" instead of waiting up to a minute.

**Architecture:** One mapping next to `NetworkError.message(for:)` gives each error its `RecoveryAction` (`.retry` or `.keyEntry`, none for a cancellation), and a `LoadFailure` carries a failed load's message and action to a screen. Retry is `StationsRepository.forgetStations(keyChanged: false)` followed by the screen's usual load: Discover's view model, a small `StationList` model that the Home Station picker and onboarding share, and `APIKeyCheck` for Settings' key section. Key entry is the Settings tab (Discover switches its window's `TabView` to it), onboarding's existing Settings sheet with a new Done button, or, in the picker, the way back to Settings. The shared session stops waiting for connectivity, with a shorter request timeout.

**Tech Stack:** Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, SwiftUI (`TabView` selection, toolbars, sheets, `ContentUnavailableView`) with Observation (`@Observable`) and Combine (`ObservableObject`), Swift concurrency, `URLSession` and `URLProtocol`, Swift Testing, `xcodebuild`, `xcrun simctl`, XCUITest (a throwaway driver for the runtime checks, never committed).

**Spec:** issue #21, https://github.com/andreisudarikov19/InspiRail/issues/21, with its "From #18", "From #20" and "From #19" sections (its line numbers refer to 8c02931), and the owner's direction for its open choices, recorded under Decisions below. Every item was checked against `main` at 40b8eb2 (after #18, #20 and #19). The code is now at `InspiRail/Pages/OnboardingView.swift:59-111` (the list and its error panel; the issue's `:58-73`), `:130-137` (the `.task` and the Settings sheet; the issue's `:128-135`) and `:160-195` (the load; the issue's `:187-197`); `InspiRail/Pages/DiscoveryView.swift:40-51` (the states; the issue's `:46-47`) and `:330-332` (the error panel; the issue's `:325-327`); `InspiRail/ViewModels/DiscoveryViewModel.swift:31-57` (the load and its `catch`; the issue's `:60-61`; the unused `refresh()` the issue cites at `:105-107` is gone); `InspiRail/Pages/SettingsView.swift:30-72` (the key section) and `:203-265` (the Home Station picker; the issue's `:239-252`); `InspiRail/BackendAPI.swift:96-120` (the session; the issue's `:48-50`); `InspiRail/AppConfiguration.swift:39-40`; and `InspiRail/ContentView.swift:18-41` (the tabs). The #20 and #19 plans, `docs/superpowers/plans/2026-11-02-network-errors.md` and `docs/superpowers/plans/2026-11-03-settings-key-check.md`, describe the errors, their messages, the store and Settings' key check as they are now.

## Global Constraints

- What changes for a user: Retry on load errors, "Open Settings" on Discover's key errors, a Done button on onboarding's Settings sheet, the Home Station picker's error row, Retry in Settings' key section, and failing fast when offline. Nothing else a user can do changes. A fix that would change more is stopped and reported, not built.
- Out of scope, and left as they are: onboarding's key step, its labels, its first tap and closing the sheet on save (#22, #42); the layout and design of error panels, titles and icons (#31); also #23, #24, #25, #27, #29, #35, #36 and #37. A state that needs one of them to make full sense is noted for that issue under Notes for other issues.
- `InspiRailApp.init` stays the only place that creates a `StationsRepository`, a `BackendAPI` or an `APIKeyCheck`. #15's test-host gate stays: while hosting the unit tests the app creates none of them.
- Tests never reach the network: every request goes through `StubURLProtocol`. The API's clock, sleep and failure report are the suite's (`StationStoreTests.api(keyProvider:sleep:)`), so no test sits through a retry's wait.
- No key, and no part of a key, is ever logged, kept or shown. The public repo, the PR and the docs never say that a key was leaked, exposed or rotated.
- Typecheck after every task: `xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios26.2-simulator -swift-version 5 -default-isolation MainActor $(find InspiRail -name '*.swift')`. On `main` it prints 0 errors and 7 warnings (14 `warning:` lines, each echoed under its source line). No task may add a warning. Task 2 removes two (`timeout`, `resourceTimeout`).
- Test command, one `xcodebuild` at a time: `xcodebuild test -project InspiRail.xcodeproj -scheme InspiRail -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath <scratch>`, on a throwaway iPhone 15 simulator (iOS 26.3) created for this branch, with nothing else of ours booted. On `main`: `** TEST SUCCEEDED **`, 100 test functions, run as 145 cases (each argument of a parameterized test counted), 0 skipped.
- Commit subjects use a conventional prefix and end with `(#21)`. Blank lines inside the app's code are indented to the enclosing level. Test files keep their empty blank lines.

## Every load-error state

The message is `NetworkError.message(for:)`'s, as #20 set it, on every screen; Settings' key section keeps #19's captions. The action comes from `NetworkError.recoveryAction(for:)` (Task 1). Discover shows its panel under "Connection Issue" (Wi-Fi icon), and only while no station is shown; onboarding shows its under "Error"; both titles stay (#31).

| Error | Message | Action | Discover | Onboarding | Home Station picker | Settings' key section |
|---|---|---|---|---|---|---|
| `.noKey`: no key stored | "No NS API key is set. Add one in Settings." | Key entry | Open Settings: this window's Settings tab | Open Settings: the Settings sheet, as on `main` | Back to Settings | "Not configured", key field, Save Key (as on `main`) |
| `.keychainUnavailable` | "Your NS API key can't be read right now. Try again in a moment." | Key entry | Open Settings | Open Settings, as on `main` | Back to Settings | Its message, key field, Save Key |
| `.keyRejected`: 401, or a 401 for this key held back | "NS didn't accept your API key. Check it in Settings." | Key entry | Open Settings | Open Settings, as on `main` | Back to Settings | "NS didn't accept this key.", key field, Save Key, Remove Key |
| `.forbidden`: 403, or held back | "NS refused your API key. It may be over its usage limit. Try again later." | Key entry | Open Settings | Open Settings, as on `main` | Back to Settings | Its message, key field, Save Key |
| `.tooManyRequests`: 429 | "NS is getting too many requests. Try again in a minute." | Retry | Retry | Retry | Retry | Its message, Retry |
| `.serviceUnavailable`: 5xx | "NS isn't available right now. Try again later." | Retry | Retry | Retry | Retry | Its message, Retry |
| `.offline`: no connection, a timeout, a failed lookup or connection, TLS, a captive portal | "Can't reach NS. Check your internet connection." | Retry | Retry | Retry | Retry | Its message, Retry |
| `.unreadableData` | "NS sent data this version of InspiRail can't read. Try again later." | Retry | Retry | Retry | Retry | Its message, Retry |
| `.invalidURL` (can't happen), or an error that isn't a `NetworkError` | "Invalid URL", or "Couldn't load stations. Try again later." | Retry | Retry | Retry | Retry | Its message, Retry |
| Cancelled | None | None | Stays loading (#20) | Stays loading (#20) | Stays loading (#20) | Status unchanged (#19) |

On `main`: Discover showed the message with no action, and Randomize disabled; onboarding offered Open Settings for the four key errors and nothing for the rest; the picker printed the error to the console and showed an empty list; Settings' "can't check" states offered nothing.

While a Retry runs, each screen shows its usual loading state: Discover "Consulting the timetable...", onboarding and the picker "Loading stations...". Settings has no loading state of its own: its key section keeps the last status while a check runs (#19), so the Retry button reads "Checking…" and is disabled, as Save Key reads "Saving…".

## Decisions

1. **One recovery action per error, from one place.** `NetworkError.recoveryAction(for:)`, next to `message(for:)`, returns `.retry` for offline, 429, 5xx and unreadable data, `.keyEntry` for no key, Keychain unavailable, 401 and 403, and nil for a cancellation (exactly when `message(for:)` is nil). `.invalidURL`, which can't happen, and an error that isn't a `NetworkError` also get `.retry`, so that no error state is a dead end; "Couldn't load stations. Try again later." asks for it. A refused key isn't sent again for 15 minutes unless a key is saved (#20), so a Retry after a 401 or 403 would only repeat the message: key errors lead to key entry instead (the issue's second "From #20" item). A Keychain that can't be read leads to key entry too, though its message says "Try again in a moment": an item that can't be read fails every read, and saving a key, which replaces it, is the only way out in the app (#19 Decision 3); a passing failure clears on the next load, which Discover runs when it next appears. `LoadFailure(error)` pairs the message with the action for a screen to keep, and is nil for a cancellation. `NetworkError.concernsTheKey` goes: its four cases are exactly `.keyEntry`, so onboarding offers Open Settings for the same errors as on `main`. Reason: every screen offers the same action for the same error, and the screens can't drift apart, as their messages couldn't since #20.
2. **Retry is `forgetStations(keyChanged: false)`, then the screen's usual load.** It drops the stored list, joins a download already in flight and keeps a refusal (#19 Decision 4; the issue's "From #18" and "From #19" items), so a Retry never starts a second download and never resends a refused key. Each screen's model sets its loading state before it awaits anything, so the spinner shows from the tap. A failed Retry shows its own error, which the API reports once, as it reports every failed load (#20). Retry goes on every load-error state with a Retry action: Discover's error panel, onboarding's error panel, the Home Station picker's new error row, and Settings' key section when it can't check, through `APIKeyCheck.retry(using:)`. A Retry started from a button runs in a `Task` of its own, so leaving the screen doesn't cancel it, and its answer still shows.
3. **No pull to refresh on Discover**, a deliberate departure from the issue's first Fix item. Discover has no vertical scroll container to pull: its station card and map fill the screen above Randomize. On success the list is stored for an hour, so a refresh would change nothing visible, and on failure the Retry button does the same job.
4. **Key entry is the Settings tab, plus a Done button; no new key screen.** Settings' key section (#19) already shows the key's state with the right controls.
   - **Discover:** its key errors offer "Open Settings", as onboarding already does, which switches this window to the Settings tab. `MainTabView` gets `TabView(selection:)` over a `@State` selection, so each window, which has its own `MainTabView`, keeps its own tab, and a tap in one iPad window doesn't move another. `DiscoveryView(openSettings:)` takes the switch as a closure. Discover reloads when it next appears, as it does today: its `.task` runs each time the tab appears (checked on the simulator in Task 7, case (b)).
   - **Onboarding:** keeps its "Open Settings" sheet. `SettingsView(done:)` shows a **Done** button (`.confirmationAction`) that calls `done` when one is given, which only onboarding's sheet does; the Settings tab passes none. Done sets `showingSettings = false`, and the sheet's `onDismiss` reloads, as swiping it away does today. Nothing else in onboarding's key flow changes (#42).
   - **The Home Station picker:** its key errors offer "Back to Settings", which pops the picker (its `dismiss`, as after picking a station) back to Settings, where the "API Configuration" section sits above the Home Station row and shows the key's state from the shared `APIKeyCheck`. Settings' `.task` checks again when it reappears. "Open Settings" would read as if Settings weren't open already. The same holds inside onboarding's Settings sheet.
5. **The Home Station picker's error row, through a small model that onboarding shares.** `StationList` (`@Observable`) holds the stations, whether it is loading, and the `LoadFailure`, with `load(from:)` and `retry(from:)`. The picker shows, instead of an empty list, a row with the failure's message and its action. It covers the cases #19 made reachable: right after Remove Key, and after saving a key NS rejects, the store's list is dropped, and the picker's load fails with "No NS API key is set…" or "NS didn't accept your API key…" with Back to Settings. The console `print` goes; the API already logs each failed load once. Onboarding picks the home station from the same list with the same load, so it uses `StationList` too, in place of its five `@State` values and its `print`s; its search filter becomes a computed property over the list, like the picker's, so it also applies to a list that arrives after the user typed (on `main` a reload showed the whole list under a search). Reason: one tested load, retry and failure for both pickers, instead of two copies in views.
6. **Fail fast when offline.** The shared session sets `waitsForConnectivity = false`. Offline, a request then fails at once (`.offline(.notConnectedToInternet)`, "Can't reach NS…"). Every load in this app is user-started (a screen appearing, or a tap), so no load needs to wait for a network, and Retry is the way to try again once online. #20's rule stays: no-internet errors and timeouts aren't retried. The timeouts, which are the only bound left on a slow or stalled connection:
   - `timeoutIntervalForRequest` (`AppConfiguration.API.timeout`), the longest wait for the reply's first or next bytes: 30 s → **15 s**.
   - `timeoutIntervalForResource` (`AppConfiguration.API.resourceTimeout`), the longest one request may take in all, even while its reply is still arriving: **60 s**, as on `main`. (Changed in review: it was 30 s; see Review fixes.)

   Reason: failing at once offline comes from `waitsForConnectivity = false`, and a stalled connection is caught by the request timeout: a connection that sends nothing for 15 s, several times the round trips of a slow mobile network, has stalled, and waiting longer only keeps the loading screen up. A stalled load now shows "Can't reach NS" after 15 s instead of 30. The resource timeout stays at 60 s because it ends a download even while data is still arriving: a timeout isn't retried, and each Retry starts again from zero, so on a link too slow to finish within the limit every attempt would fail with "Check your internet connection." A shorter limit buys nothing this issue needs. The size of NS's reply, and whether NS compresses it, weren't measured, since that needs a real key. For scale only: the review stub's synthetic list, built in NS's v3 shape with 600 stations (400 Dutch), is 382,043 bytes, 37,948 gzipped (`gzip -6`); on EDGE (the Network Link Conditioner's "Edge" profile: 240 kbit/s down, 400 ms latency) that takes about 13 s uncompressed or 1.3 s gzipped, plus about 2 s of name lookup, TCP and TLS round trips. Both constants become `nonisolated`, like the retry constants beside them, since `BackendAPI.init`, which isn't on the main actor, reads them; that removes two warnings.
7. **Settings' Retry.** `APIKeyStatus.offersRetry` is true for `.cantCheck` only, which is exactly the errors whose action is `.retry`; the other states keep #19's controls. The key section shows a "Retry" row (the `arrow.clockwise` icon, styled like Save Key) under the caption, which calls `APIKeyCheck.retry(using:)`: `forgetStations(keyChanged: false)`, then a check as `refresh(using:)` runs it, under its rules for cancelled checks and key changes. The row reads "Checking…" and is disabled while its retry runs.
8. **One button for a failed load.** `RecoveryButton` draws "Retry" (`arrow.clockwise`) or the key-entry button ("Open Settings" by default, `gear`) with onboarding's current look (`.borderedProminent`, 16 pt by 8 pt padding, and a white label, so that its icon also shows in the picker's List row: review fix 2), so onboarding's Open Settings looks as on `main`, and Discover, onboarding and the picker offer the same button for the same action. Its layout and design are #31's.

## Review Focus

1. **A key error must never offer Retry, which would only repeat the refusal, and an error a key can't fix must never send the user to key entry.** Pinned by Task 1's `eachErrorHasItsRecoveryAction`, Task 3's `discoverOffersRetryOrKeyEntry`, and Task 6's `keyStatusOffersWhatTheRecoveryActionSays`.
2. **Retry must not start a second download while one is in flight, and must never resend a refused key.** Pinned by Task 3's `discoverRetryJoinsTheDownloadInFlight` and `discoverRetryAfterARejectedKeySendsNothing`, each also run against a mutant that forgets as for a key change.
3. **Right after Remove Key, or after saving a key NS rejects, the picker must show the key message with a way back to the key, never an empty list.** Pinned by Task 4's `pickerShowsTheKeyMessageRightAfterTheKeyIsRemoved` and `pickerShowsTheKeyMessageAfterASavedKeyIsRejected`, and checked on the simulator in Task 7, case (e).
4. **While a Retry runs the screen shows its loading state, and a failed Retry shows its new error, reported once.** Pinned by Task 3's `discoverRetryShowsTheLoadingStateThenTheStation` and `discoverFailedRetryShowsTheNewError`, Task 4's `pickerShowsTheStationsAfterASuccessfulRetry`, and checked on the simulator in Task 7, cases (a) and (f).
5. **Offline must fail at once, and Open Settings must switch only the window it was tapped in, to a Settings tab showing the key section; Discover must load again when it next appears.** The session's settings are pinned by Task 2's `sessionFailsFastWhenOffline`; the stub can't make the simulator offline, so case (g) says what it measures. The tab switch and the reload are checked on the simulator in case (b).

## Notes for other issues

- **#42:** onboarding keeps "Open Settings" for the four key errors, including a Keychain that can't be read and a 403, where another key may not help. After saving a key in the sheet, the user taps Done (or swipes) to see the list; closing on save, an "Enter API Key" label and a key step are #42's. Onboarding's sheet is the whole Settings screen, so its Home Station row can pick the home station from inside the sheet, which ends onboarding behind it.
- **#31:** Discover's "Connection Issue" title and Wi-Fi icon now sit above Open Settings for key errors and above Retry for a busy or failing NS; onboarding's title is "Error". The picker's error row is a plain list row; Settings' Retry is a row styled like Save Key; the buttons' labels ("Retry", "Open Settings", "Back to Settings") and icons.
- **#35:** a Keychain that can't be read reads "…Try again in a moment.", while every screen offers key entry and Settings offers the key field with no Retry; a passing failure clears when the screen loads again.
- **#22:** none beyond #42's.
- The Logbook's station count still fails silently and keeps the last count: it has no error state, so it gets no Retry.

---

### Task 1: One recovery action per error

**Files:**
- Modify: `InspiRail/NetworkEngine/NetworkError.swift` (`RecoveryAction`, `recoveryAction(for:)`, `LoadFailure`; `concernsTheKey` goes)
- Modify: `InspiRail/Pages/OnboardingView.swift:191` (the one caller of `concernsTheKey`)
- Modify: `InspiRailTests/NetworkErrorTests.swift:120-138`

**Interfaces:**
- Consumes: #20's `NetworkError` and `NetworkError.message(for:)`.
- Produces:
  - `nonisolated enum RecoveryAction: Equatable, Sendable { case retry, keyEntry }`.
  - `static func NetworkError.recoveryAction(for error: Error) -> RecoveryAction?`, as Decision 1.
  - `nonisolated struct LoadFailure: Equatable, Sendable` with `let message: String`, `let action: RecoveryAction`, the memberwise `init(message:action:)`, and `init?(_ error: Error)`, nil for a cancellation.

- [x] **Step 1: Write the failing tests** in `NetworkErrorTests.swift`, after `eachErrorHasItsMessage`:
  - `eachErrorHasItsRecoveryAction(error: any Error, action: RecoveryAction?)`, with arguments `.noKey`, `.keychainUnavailable`, `.keyRejected`, `.forbidden` → `.keyEntry`; `.tooManyRequests`, `.serviceUnavailable(status: 503)`, `.offline(.notConnectedToInternet)`, `.offline(.timedOut)`, `.unreadableData`, `.invalidURL`, `CocoaError(.fileNoSuchFile)` → `.retry`; `CancellationError()`, `URLError(.cancelled)` → `nil` (13 cases). Expects `NetworkError.recoveryAction(for: error) == action`.
  - `loadFailureHasTheMessageAndTheAction`: `LoadFailure(NetworkError.serviceUnavailable(status: 503)) == LoadFailure(message: "NS isn't available right now. Try again later.", action: .retry)`, `LoadFailure(NetworkError.noKey) == LoadFailure(message: "No NS API key is set. Add one in Settings.", action: .keyEntry)`, and nil for `CancellationError()` and `URLError(.cancelled)`.

  And drop `eachErrorHasItsMessage`'s last two lines (`keyCases`, `concernsTheKey`): the new test pins that set.
- [x] **Step 2: Run them to verify they fail.** Test command with `-only-testing:InspiRailTests/StationStoreTests`. Expected: a build failure, `cannot find type 'RecoveryAction' in scope` or similar.
- [x] **Step 3: Implement** as in Interfaces, with doc comments that say why key errors lead to key entry (#20's refusal pause). Onboarding's `isUnauthorized` becomes `NetworkError.recoveryAction(for: error) == .keyEntry` (Task 5 replaces the line).
- [x] **Step 4: Run them to verify they pass.** Expected: the suite passes, with 2 new tests, run as 14 cases. Then check that the test bites on the set onboarding already used: map `.keychainUnavailable` to `.retry`, see `eachErrorHasItsRecoveryAction` fail for that argument only, and restore the file.
- [x] **Step 5: Typecheck.** Expected: 0 errors, 7 warnings.
- [x] **Step 6: Commit** `fix: give every failed station load one recovery action, Retry or key entry (#21)`

### Task 2: Fail fast when offline

**Files:**
- Modify: `InspiRail/AppConfiguration.swift:39-40`
- Modify: `InspiRail/BackendAPI.swift:96-104` (`makeSession`)
- Modify: `InspiRailTests/StationStoreTests.swift:75-83` (a test beside `sessionKeepsNoURLCache`)

**Interfaces:**
- Consumes: nothing new.
- Produces: `nonisolated static let timeout: TimeInterval = 15` and `nonisolated static let resourceTimeout: TimeInterval = 30` in `AppConfiguration.API`, each with a doc comment saying what it bounds and why (Decision 6). The session's `waitsForConnectivity` is false.
  (Changed in review: `resourceTimeout` is back at 60 s, and the test expects 60; see Review fixes.)

- [x] **Step 1: Write the failing test** `sessionFailsFastWhenOffline`: start from `StubURLProtocol.configuration()` with `waitsForConnectivity = true`, so the test can't pass on the ephemeral default; build `BackendAPI(keyProvider: environmentKeyProvider(), sessionConfiguration: base)`; expect its `session.configuration` to have `waitsForConnectivity == false`, `timeoutIntervalForRequest == 15` and `timeoutIntervalForResource == 30`.
- [x] **Step 2: Run it to verify it fails.** Expected: 3 failed expectations (`true`, `30.0`, `60.0`).
- [x] **Step 3: Implement.** `config.waitsForConnectivity = false`, with a comment: loads are user-started and fail at once offline, and Retry tries again (#21). The two values as in Interfaces.
- [x] **Step 4: Run it to verify it passes.** Expected: the suite passes.
- [x] **Step 5: Typecheck.** Expected: 0 errors, 5 warnings (the two on `timeout` and `resourceTimeout` are gone).
- [x] **Step 6: Commit** `fix: fail at once when offline instead of waiting up to a minute for a connection (#21)`

### Task 3: Discover offers Retry, or Open Settings for a key error

**Files:**
- Create: `InspiRail/Pages/RecoveryButton.swift`
- Modify: `InspiRail/ViewModels/DiscoveryViewModel.swift:18,30-57`
- Modify: `InspiRail/Pages/DiscoveryView.swift:12-14,47-48,330-332`
- Modify: `InspiRail/ContentView.swift:10-43`
- Create: `InspiRailTests/LoadRecoveryTests.swift`

**Interfaces:**
- Consumes: Task 1's `LoadFailure` and `RecoveryAction`; #19's `forgetStations(keyChanged:)`.
- Produces:
  - `DiscoveryViewModel`: `@Published var failure: LoadFailure?`, which replaces `errorMessage`, and `func retry(from repository: StationsRepository) async`: sets `isLoading = true` and `failure = nil`, awaits `repository.forgetStations(keyChanged: false)`, then `loadStations(from:)`.
  - `struct RecoveryButton: View` with `let action: RecoveryAction`, `var keyEntryTitle: LocalizedStringKey = "Open Settings"`, `let retry: () -> Void` and `let enterKey: () -> Void` (Decision 8).
  - `DiscoveryView.init(openSettings: @escaping () -> Void)`. Its error panel becomes `ContentUnavailableView` with the same title, icon and message, and a `RecoveryButton` as its action: Retry runs `viewModel.retry(from:)` in a `Task`, with the store from the environment (`reportMissingStationStore(in: "Discover")` without one); key entry calls `openSettings`.
  - `MainTabView`: `private enum MainTab: Hashable { case discover, logbook, settings }`, `@State private var selectedTab = MainTab.discover`, `TabView(selection: $selectedTab)` with each tab `.tag`ged, and `DiscoveryView(openSettings: { selectedTab = .settings })`.

- [x] **Step 1: Write the failing tests** in `LoadRecoveryTests.swift`, as `extension StationStoreTests`, over `repository()`:
  - `discoverOffersRetryOrKeyEntry(status: Int, action: RecoveryAction)`, with arguments `(503, .retry)` and `(401, .keyEntry)`: after `loadStations`, `failure` has that action and the message of `.serviceUnavailable(status: 503)` or `.keyRejected`; `isLoading` and `isReady` are false, and no station is shown.
  - `discoverRetryShowsTheLoadingStateThenTheStation`: replies three 503s, then `.stations`. After the failed load (3 requests), hold, start `retry` in a `Task` and wait for request 4: `isLoading` is true and `failure` nil. Release: `failure` is nil, `isReady` true, the station is one of `dutchCodes`, 4 requests, and `failures.values == [.serviceUnavailable(status: 503)]`.
  - `discoverRetryJoinsTheDownloadInFlight`: replies `[.failure(.notConnectedToInternet), .stations]`. After the failed load, hold, start another caller's `dutchStations()` (another window), wait for request 2, start `retry`, wait 300 ms: 2 requests. Release: a station shows, still 2 requests.
  - `discoverRetryAfterARejectedKeySendsNothing`: replies `[.status(401), .stations]`. After the load and a `retry`: `failure == LoadFailure(message: "NS didn't accept your API key. Check it in Settings.", action: .keyEntry)`, 1 request, and `failures.values == [.keyRejected, .keyRejected]` (each load reported once).
  - `discoverFailedRetryShowsTheNewError`: replies `[.failure(.notConnectedToInternet), .status(503)]`. After the load and a `retry`: the 503's message with `.retry`, 4 requests, and `failures.values == [.offline(.notConnectedToInternet), .serviceUnavailable(status: 503)]`.
- [x] **Step 2: Run them to verify they fail.** Expected: a build failure, `value of type 'DiscoveryViewModel' has no member 'failure'` or similar.
- [x] **Step 3: Implement** the view model as in Interfaces; its `catch` sets `failure = LoadFailure(error)` where it set the message (a cancellation still returns early, #20).
- [x] **Step 4: Implement** `RecoveryButton`, Discover's panel and init, and `MainTabView`'s selection, as in Interfaces.
- [x] **Step 5: Run them to verify they pass.** Expected: the suite passes, with 5 new tests, run as 6 cases. Then check the two tests that pin the store's existing behaviour: a `retry` that calls `forgetStations(keyChanged: true)` fails `discoverRetryJoinsTheDownloadInFlight` and `discoverRetryAfterARejectedKeySendsNothing`. Restore the file.
- [x] **Step 6: Typecheck.** Expected: 0 errors, 5 warnings.
- [x] **Step 7: Commit** `fix: offer Retry on Discover's load errors, and Open Settings on its key errors (#21)`

### Task 4: The Home Station picker's error row

**Files:**
- Create: `InspiRail/ViewModels/StationList.swift`
- Modify: `InspiRail/Pages/SettingsView.swift:203-265` (`StationSelectorView`)
- Modify: `InspiRailTests/LoadRecoveryTests.swift`

**Interfaces:**
- Consumes: Task 1's `LoadFailure`; Task 3's `RecoveryButton`; #19's `APIKeyCheck.refresh(using:)` and `keyChanged(in:)`, and the suite's `keyCheckRepository(key:)` and `TestKeyStorage`.
- Produces: `@MainActor @Observable final class StationList` with `private(set) var stations: [Station] = []`, `private(set) var isLoading = true`, `private(set) var failure: LoadFailure?`, `func load(from repository: StationsRepository) async` (sets `isLoading` and clears `failure`, then keeps the Dutch stations or `LoadFailure(error)`; a cancellation leaves it loading, #20) and `func retry(from repository: StationsRepository) async` (the loading state first, then `forgetStations(keyChanged: false)` and `load(from:)`).

- [x] **Step 1: Write the failing tests** in `LoadRecoveryTests.swift`:
  - `pickerShowsTheErrorAndRetryOnAFailure`: a new list is loading; after `load` against `.status(503)`, it isn't, has no stations, and `failure == LoadFailure(message: "NS isn't available right now. Try again later.", action: .retry)`.
  - `pickerShowsTheKeyMessageRightAfterTheKeyIsRemoved`: over `keyCheckRepository()`, an `APIKeyCheck` refresh stores the list; `storage.removeKey()` and `keyChanged(in:)`, as Remove Key does. A list's `load` gives `LoadFailure(message: "No NS API key is set. Add one in Settings.", action: .keyEntry)` and no stations, with 1 request in all.
  - `pickerShowsTheKeyMessageAfterASavedKeyIsRejected`: replies `[.stations, .status(401)]`; a refresh, then `setKey("new-test-key")` and `keyChanged(in:)` (`.rejected`). A list's `load` gives `LoadFailure(message: "NS didn't accept your API key. Check it in Settings.", action: .keyEntry)`, with 2 requests in all.
  - `pickerShowsTheStationsAfterASuccessfulRetry`: replies `[.failure(.notConnectedToInternet), .stations]`. After the failed `load`, hold, start `retry` in a `Task`, wait for request 2: loading, no failure. Release: the stations are `dutchCodes`, no failure, not loading, 2 requests.
- [x] **Step 2: Run them to verify they fail.** Expected: a build failure, `cannot find 'StationList' in scope`.
- [x] **Step 3: Implement** `StationList` as in Interfaces, with a doc comment naming both pickers.
- [x] **Step 4: Implement the picker.** `@State private var stationList = StationList()` replaces `allStations` and `isLoading`, and `fetchStations()` goes. The `List` shows the spinner while loading; else, with a failure, one row: the failure's message, and a `RecoveryButton` whose key entry is "Back to Settings" and calls `dismiss()`, and whose Retry runs `stationList.retry(from:)` in a `Task`; else the stations as now. The `.task` loads only while the list has no stations, and reports a missing store as now.
- [x] **Step 5: Run them to verify they pass.** Expected: the suite passes, with 4 new tests.
  (No mutant was run: the tests pin `StationList`, which is new, and their red was a build failure. The store's drop on a key change they rely on is pinned, with mutants, by #19's tests.)
- [x] **Step 6: Typecheck.** Expected: 0 errors, 5 warnings. `git grep -n "print(" InspiRail/Pages/SettingsView.swift` finds nothing.
- [x] **Step 7: Commit** `fix: show the Home Station picker's load error with Retry or the way back to the key, not an empty list (#21)`

### Task 5: Onboarding offers Retry, and its Settings sheet a Done button

**Files:**
- Modify: `InspiRail/Pages/OnboardingView.swift:20-27,48-75,130-137,143-195`
- Modify: `InspiRail/Pages/SettingsView.swift:11-24,107-109` (`init(done:)`, the toolbar)

**Interfaces:**
- Consumes: Task 4's `StationList`; Task 3's `RecoveryButton`.
- Produces: `SettingsView.init(done: (() -> Void)? = nil)`: with `done`, a `ToolbarItem(placement: .confirmationAction)` with `Button("Done", action: done)`; without, no toolbar item.

- [x] **Step 1: Onboarding.** `@State private var stationList = StationList()` replaces `allStations`, `filteredStations`, `isLoading`, `errorMessage` and `isUnauthorized`; `filteredStations` becomes a computed property over `stationList.stations` with the same filter, and the `.onChange(of: searchText)` and `filterStations(with:)` go. The error panel keeps its `ContentUnavailableView("Error", …)` and puts a `RecoveryButton` under it in place of the Open Settings button: key entry sets `showingSettings = true`, Retry runs `stationList.retry(from:)` in a `Task`. `loadStations()` reports a missing store as now and calls `stationList.load(from:)`; the `print`s and `MainActor.run`s go. The sheet shows `SettingsView(done: { showingSettings = false })`; its `onDismiss` reload stays.
- [x] **Step 2: Settings' Done button**, as in Interfaces. The tab's `SettingsView()` is unchanged.
- [x] **Step 3: Typecheck.** Expected: 0 errors, 5 warnings.
- [x] **Step 4: Run the default test plan.** Expected: `** TEST SUCCEEDED **`, 112 test functions (100, and 2 + 1 + 5 + 4 new), run as 170 cases (145, and 14 + 1 + 6 + 4), 0 skipped. Onboarding's logic is `StationList`'s, tested in Task 4; its buttons are checked on the simulator in Task 7, cases (c) and (d).
- [x] **Step 5: Commit** `fix: offer Retry in onboarding, and a Done button on its Settings sheet (#21)`

### Task 6: Settings offers Retry when it can't check the key

**Files:**
- Modify: `InspiRail/ViewModels/APIKeyCheck.swift` (`offersRetry`, `retry(using:)`)
- Modify: `InspiRail/Pages/SettingsView.swift:17-20,41-64,158-185` (the Retry row, `retryInFlight`, `retryKeyCheck()`)
- Modify: `InspiRailTests/APIKeyCheckTests.swift:24-55`

**Interfaces:**
- Consumes: Task 1's `NetworkError.recoveryAction(for:)` (tests only); #19's `APIKeyCheck` and `APIKeyStatus`.
- Produces: `APIKeyStatus.offersRetry: Bool` (`.cantCheck` only) and `APIKeyCheck.retry(using repository: StationsRepository) async` (Decision 7).

- [x] **Step 1: Write the failing tests** in `APIKeyCheckTests.swift`:
  - `eachStatusSaysWhatItShows` gains a `retry` column: true for `.cantCheck(…)` only.
  - `keyStatusOffersWhatTheRecoveryActionSays`: for each error of Task 1's test, `APIKeyStatus(for:)` is nil exactly when `recoveryAction(for:)` is, and otherwise `offersRetry == (action == .retry)` and `offersKeyEntry == (action == .keyEntry)`.
  - `cantCheckOffersRetryAndRetryChecksAgain`: replies `[.failure(.notConnectedToInternet), .stations]`. After `refresh`, the status offers Retry and not key entry. After `retry(using:)`, it is `.working`, with 2 requests.
- [x] **Step 2: Run them to verify they fail.** Expected: a build failure, `value of type 'APIKeyStatus' has no member 'offersRetry'`.
- [x] **Step 3: Implement** as in Interfaces, and the row: when `keyStatus.offersRetry`, a button with `SettingsIcon(icon: "arrow.clockwise", color: .blue)` and `Text(retryInFlight ? "Checking…" : "Retry")`, disabled while `retryInFlight`. `retryKeyCheck()` reports a missing store or key check as `refreshKeyStatus()` does, sets `retryInFlight`, and runs `keyCheck.retry(using:)` in a `Task` that clears it.
- [x] **Step 4: Run them to verify they pass.** Expected: the suite passes, with 2 new tests.
  (Changed during execution: the whole default test plan ran here: 114 test functions, run as 172 cases.)
- [x] **Step 5: Typecheck.** Expected: 0 errors, 5 warnings.
- [x] **Step 6: Commit** `fix: offer Retry in Settings when it can't check the key (#21)`

### Task 7: Record the fix, and check each state on a simulator

**Files:**
- Modify: `CHANGELOG.md`, `[Unreleased]`
- Modify: `README.md:33-48` (the layout's `Pages/` and `ViewModels/` lines)
- Modify: this plan (Measurements)

- [x] **Step 1: `CHANGELOG.md`.** Under `### Fixed`, append:
  - When the station list can't be loaded, every screen offers a way forward: Retry where trying again can help (no connection, too many requests, NS unavailable, data the app can't read), and the way to Settings' key section where only a key can (no key, a key that can't be read, a key NS rejected or refused). Discover offers Retry, or Open Settings, which switches that window to the Settings tab. Onboarding adds Retry beside its Open Settings. The Home Station picker shows the error with Retry or Back to Settings instead of an empty list, also right after a key is removed or a rejected key is saved. Settings offers Retry when it can't check the key. Retry joins a download already running, and doesn't send a key NS refused again.
  - Onboarding's Settings sheet has a Done button; onboarding loads the stations again when it closes.
  - Offline, a load fails at once with "Can't reach NS. Check your internet connection." instead of waiting up to a minute for a connection and then reporting a timeout. A request that receives nothing for 15 seconds, or takes longer than 30 in all, fails (was 30 and 60).

  (Changed in review, fix 1: the last item's second sentence reads "A request that receives nothing for 15 seconds fails (was 30); one whose reply is still arriving has up to a minute in all, as before.")
- [x] **Step 2: `README.md`.** The `Pages/` line adds "and the button a failed load offers"; the `ViewModels/` line reads "View-models, the station list the home-station pickers load, and the station store and Settings' key check every window shares".
- [x] **Step 3: Run the default test plan.** Expected: `** TEST SUCCEEDED **`, 114 test functions (112, and Task 6's 2), run as 172 cases, 0 skipped.
- [x] **Step 4: Builds and stub.** A scratch copy of the offline review stub (`.superpowers/scratch/review/runtime/stub/`) outside the repo, from #19's copy: it answers only `gateway.apiportal.ns.nl` and never forwards a request, and reads `REVIEW_STUB_PAYLOAD`, `REVIEW_STUB_STATUS`, `REVIEW_STUB_STATUS_COUNT`, `REVIEW_STUB_FAIL`, `REVIEW_STUB_REJECT_KEY`, `REVIEW_STUB_DELAY` and `REVIEW_STUB_DELAY_FROM`, plus a new `REVIEW_STUB_FAIL_COUNT` (fail only the first n requests, then answer as usual). It logs each request, and whether it carried the key to reject, another key or none, never the key. Build it for the simulator with `xcrun --sdk iphonesimulator clang`. In scratch worktrees of `main` (40b8eb2) and of this branch, add a throwaway XCUITest driver to `InspiRailUITests/` and that target to the worktree's test plan, and build each with `build-for-testing` and its own `-derivedDataPath` outside the repo. The driver launches with the stub and dummy keys only, logs `UIDRIVER phase=…` markers, reads what a screen shows through the accessibility tree, and attaches screenshots. Each run uses `test-without-building -parallel-testing-enabled NO` on the throwaway iPhone 15, with nothing else booted, streaming `log stream --predicate 'subsystem == "annisu.inspirail" OR subsystem == "review.stub" OR subsystem == "review.uidriver"'`. Never a real key; "no connection" is the stub failing with `-1009`. Shut the simulator down between runs.
- [x] **Step 5: The cases.** Screenshots go to the session's scratch directory as `21-<case>.png`. Requests are the stub's lines between the driver's markers.
  - (a) Discover with a 503 for the first 3 requests, the 4th answered after 3 s: the error with Retry after 3 requests; Retry shows "Consulting the timetable...", then a station, with 1 more request.
  - (b) An erased simulator with no key, `-homeStationCode ASD`, and the stub rejecting `dummy-key-a`: Discover shows "No NS API key is set…" with Open Settings, which selects the Settings tab, showing the key section. `dummy-key-a` is saved there (1 request, 401). Back on Discover, which loads again (no request: the refusal holds): "NS didn't accept your API key…" with Open Settings, which switches to Settings showing "NS didn't accept this key.". `dummy-key-b` is saved (1 request, 200). Back on Discover, a station shows with no further request.
  - (c) An erased simulator (no home station), a dummy key, the first request failing with `-1009`: onboarding shows "Can't reach NS…" with Retry; Retry sends 1 request and the station list shows.
  - (d) An erased simulator with no key: onboarding shows "No NS API key is set…" with Open Settings; the sheet shows Done, which closes it, and onboarding loads again (no request). Open Settings again, save `dummy-key`, Done: the list shows.
  - (e) An erased simulator with no key, `-homeStationCode ASD`, the stub rejecting `dummy-key-a` and answering 503 to its first 7 requests. Settings: save `dummy-key-a` (401); the picker shows "NS didn't accept your API key…" with Back to Settings. Back in Settings, Remove Key; the picker shows "No NS API key is set…" with Back to Settings, which returns to Settings with "Not configured". Save `dummy-key-b`: its check gets 503s ("NS isn't available…" with Retry); the picker gets 503s too: its error row with Retry. Retry: the stations show.
  - (f) A dummy key and `-homeStationCode ASD`; a 503 for the first 6 requests, then answers 3 s late: Settings shows "NS isn't available…" with Retry; Retry reads "Checking…", sends 1 request, and the section goes away.
  - (g) "No connection" (every request `-1009`) on Discover: the time from launch to the message, on `main` and on the branch. The stub answers inside the app's URL loading, where `waitsForConnectivity` may never apply; if both are equally fast, say so, and Task 2's test is what pins the setting. Also every answer delayed 40 s: the time to "Can't reach NS…" on each, which shows whether the timeouts apply to the stub's requests.
  - No log line holds a dummy key, and no fault or assertion is logged.
  (Changed during execution: the stub is built for x86_64, this Mac's simulator architecture. The driver first waited for "Utrecht Centraal" to show the list, but the stub's sorted list starts with made-up names, so the row isn't on screen; it waits for the list's first row instead, and (c) was run again. In (g), the measured times are from the stub's request to the app's failure line, besides the driver's time from its launch call.)
- [x] **Step 6: Clean up.** Delete the worktrees, the derived data, the stub copy's build, any test clones (`xcrun simctl --set ~/Library/Developer/XCTestDevices list devices`), the simulator once the last run is done, and any crash reports the runs left in `~/Library/Logs/DiagnosticReports/`.
- [x] **Step 7: Commit** `docs: record the way out of every failed station load in the changelog, README and plan (#21)`

## Measurements

On a throwaway iPhone 15 simulator (iOS 26.3), with a scratch copy of the offline stub, dummy keys, and `-homeStationCode ASD` except in onboarding's cases, driven by a throwaway UI test outside the repo. Requests are the stub's `REVIEWSTUB received` lines, counted between the driver's markers; what a screen offers comes from the accessibility tree. The branch is 96207b2 (Task 6), with the session's timeouts at 15 s per request and 30 s per resource, before review fix 1 put the resource timeout back at 60 s; `main` is 40b8eb2, at 30 s and 60 s. Screenshots are in the session's scratch directory as `21-<case>.png`, and `21-g…-main.png` for `main`. Every run passed.

| Case | Requests | Seen |
|---|---|---|
| (a) Discover, 503 for 3 requests, the 4th answered 3 s late | 3 for the first load (two retries), then 1 for Retry | "NS isn't available right now. Try again later." with Retry and Randomize disabled; after Retry, "Consulting the timetable..." for the 3 s, then a station |
| (b) No key; the stub rejects `dummy-key-a` | 0 with no key; 1 for `dummy-key-a` (401); 0 when Discover appeared again (the refusal held); 1 for `dummy-key-b` (200); 0 when Discover appeared again | Discover: "No NS API key is set…" with Open Settings, which selected the Settings tab, showing "Not configured" with the key field. After `dummy-key-a`, Discover loaded again on appearing ("Failed to load stations" logged) and showed "NS didn't accept your API key…" with Open Settings, which selected Settings showing "NS didn't accept this key." with Remove Key. After `dummy-key-b`, the key section went away, and Discover, on appearing again, showed a station from the stored list |
| (c) Onboarding, the first request failing with `-1009` | 1, then 1 for Retry | "Can't reach NS. Check your internet connection." under "Error", with Retry; then the station list |
| (d) Onboarding with no key | 0 until the key was saved; 1 for the key; 0 after Done | "No NS API key is set…" with Open Settings; the sheet showed Done, which closed it, and onboarding loaded again (another `noKey` logged) and showed the same message; after `dummy-key` was saved in the sheet the key section went away, and Done showed the station list |
| (e) No key; the stub rejects `dummy-key-a` and answers 503 to its first 7 requests | 1 for `dummy-key-a` (401); 0 for the picker (the refusal held); 0 after Remove Key; 3 for `dummy-key-b`'s check (503s); 3 for the picker (503s); 1 for the picker's Retry (200) | After saving the rejected key, the picker: "NS didn't accept your API key. Check it in Settings." with Back to Settings, which returned to Settings. After Remove Key, the picker: "No NS API key is set. Add one in Settings." with Back to Settings, which returned to "Not configured". After `dummy-key-b`, Settings: "NS isn't available…" with Retry; the picker: the same message with Retry, then the stations |
| (f) Settings, 503 for 6 requests, the 7th answered 3 s late | 3 for Discover, 3 for Settings' check, 1 for Retry | "NS isn't available right now. Try again later." with Retry and no key field; during Retry, "Checking…", disabled; then no key section |
| (g) No connection, every request `-1009`, on Discover | 1 | The message 17 ms after the request on the branch (15 ms on `main`); 5.8 s from the driver's launch call on the branch, 4.6 s on `main`, almost all of it the app's launch. The stub answers inside the app's URL loading, on a simulator with a working network path, so `waitsForConnectivity` never applies to it and both are equally fast; Task 2's test is what pins the setting |
| (g) Every answer 40 s late, on Discover | 1 | Branch: the request timed out (`-1001`) 15.1 s after it was sent, and Discover showed "Can't reach NS…". `main`: no timeout; the stub answered at 40 s and Discover showed a station, so on `main` its 30 s request timeout didn't end this stalled request, and only the 60 s resource timeout bounded it |

No line in the runs' app and stub logs held a dummy key, and no fault or assertion was logged. The runtime checks left no crash reports; the unit-test runs' simulator clones left three (`UsageTrackingAgent`), which were deleted.

The default test plan passes 114 test functions, run as 172 cases, 0 skipped. The typecheck prints 0 errors and 5 warnings, all of kinds already on `main`.
