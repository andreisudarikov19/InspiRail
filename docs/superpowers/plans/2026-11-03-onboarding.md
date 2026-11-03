# An onboarding that asks for the key first and ends on Start Exploring (#22, #42) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Onboarding has two steps in one screen. The key step asks for a free NS API key whenever only a key can help, takes it there and loads the stations with it at once. The station step lists the stations, shows the search field once they have loaded, and lets the user pick a home station with a checkmark. Only "Start Exploring" stores the home station and ends onboarding.

**Architecture:** A small `@Observable` model, `Onboarding`, wraps the `StationList` that onboarding already loads (#21). It works out the step from the load's failure through #21's `NetworkError.recoveryAction(for:)`, and holds the key field, the save and the selected station. A key is saved through one path that Settings shares, `APIKeyCheck.saveKey(_:to:in:written:)`: trim it, write it, then `keyChanged(in:)`, which now returns the store's answer for the new key, so onboarding shows that answer without a second download. `MainTabView` keeps gating on `homeStationCode`; `hasCompletedOnboarding`, onboarding's Settings sheet and `SettingsView(done:)` go.

**Tech Stack:** Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, SwiftUI (`ScrollView`, `SecureField`, `Link`, `@AppStorage`, `.onChange`, alerts) with Observation (`@Observable`), Swift concurrency, `UserDefaults`, Swift Testing, `xcodebuild`, `xcrun simctl`, XCUITest (a throwaway driver for the runtime checks, never committed).

**Spec:** issues #22 (https://github.com/andreisudarikov19/InspiRail/issues/22, line numbers at 8c02931) and #42 (https://github.com/andreisudarikov19/InspiRail/issues/42, at 378233e), with #42's "From #20" and "From #21" sections, and the owner's direction for the open choices, recorded under Decisions below. Every item was checked against `main` at 9131266 (after #21). The code is now at:
- `InspiRail/ContentView.swift:15-24`: the gate and `hasCompletedOnboarding` (#22's `:11-16`).
- `InspiRail/Pages/OnboardingView.swift`:
  - `:38-60`: the header and the search field (#42's `:36-54`).
  - `:62-108`: the list, its checkmark at `:97-100`, and the error panel with `RecoveryButton` at `:66-72` (#42's `:57-73`; #22's `:98-123`).
  - `:110-124`: Start Exploring (#22's `:98-123`).
  - `:130-134`: the Settings sheet (#42's `:131-135`).
  - `:140-144`: `selectStation(_:)`, which writes `homeStationCode` (#22's `:141-145`).
  - #42's `:189-191`, `concernsTheKey`, went in #21; key errors reach the sheet through `RecoveryButton`.
- `InspiRail/Pages/SettingsView.swift`:
  - `:24-32` and `:133-139`: `init(done:)` and the Done button.
  - `:37-96`: the key section (#42's `:123-140`).
  - `:154-171`: `saveAPIKey()`.
- `InspiRail/APIKeyProvider.swift:75-77`: no key throws `NetworkError.noKey` before any request (#42's `:65-70`).

#21's plan, `docs/superpowers/plans/2026-11-03-load-recovery.md`, describes `RecoveryAction`, `LoadFailure`, `StationList` and `RecoveryButton` as they are now; #19's, `docs/superpowers/plans/2026-11-03-settings-key-check.md`, describes `APIKeyCheck`.

## Global Constraints

- What changes for a user: onboarding's key step and saving a key there; onboarding's Settings sheet goes; the search field waits for the list; tapping a station selects it without ending onboarding, and "Start Exploring" ends it. Nothing else a user can do changes. A fix that would change more is stopped and reported, not built.
- Out of scope, and left as they are: the UI test target and a stubbed-backend UI test (#34); visual design (#31); Keychain storage (#35); Release builds without a key (#39); and #23, #24, #25 (search rules, synonyms, sorting), #26, #27, #29, #36 and #37. A state that needs one of them to make full sense is noted for that issue under Notes for other issues.
- `InspiRailApp.init` stays the only place that creates a `StationsRepository`, a `BackendAPI` or an `APIKeyCheck`. #15's test-host gate stays: while hosting the unit tests the app shows an empty scene, builds no store and does no network work.
- Tests never reach the network: every request goes through `StubURLProtocol`, with the suite's clock, sleep and failure report (`StationStoreTests.api(keyProvider:sleep:)`). Tests never write the app's `UserDefaults` or its Keychain item: each builds `Onboarding(defaults:)` over a scratch suite, and keys live in `TestKeyStorage`.
- No key, and no part of a key, is ever logged, kept or shown. The public repo, the PR and the docs never say that a key was leaked, exposed or rotated.
- Typecheck after every task: `xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios26.2-simulator -swift-version 5 -default-isolation MainActor $(find InspiRail -name '*.swift')`. On `main` it prints 0 errors and 5 warnings (`baseURL`, `enableNetworkLogging`, `enableDetailedLogging`, `userAgent` in `BackendAPI.swift` and `cacheLifetime` in `StationsRepository.swift`, each echoed under its source line). No task may add a warning.
- Test command, one `xcodebuild` at a time: `xcodebuild test -project InspiRail.xcodeproj -scheme InspiRail -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath <scratch>`, on the throwaway iPhone 15 simulator (iOS 26.3) created for this branch, `InspiRail-22`, with nothing else of ours booted. On `main`: `** TEST SUCCEEDED **`, 117 test functions, run as 175 cases (each argument of a parameterized test counted), 0 skipped.
- Commit subjects use a conventional prefix and end with `(#22)`, `(#42)` or `(#22, #42)`. Blank lines inside the app's code are indented to the enclosing level. Test files keep their empty blank lines.

## Every onboarding state

The window shows onboarding while `homeStationCode` is empty (Decision 6). The header, as on `main`, is the train icon and "Welcome to InspiRail"; each step adds its own text under it. Messages are `NetworkError.message(for:)`'s, as #20 set them. The step comes from the load's failure through `NetworkError.recoveryAction(for:)` (#21): key entry shows the key step, anything else the station step (Decision 1).

| State | Step | Title and text | Controls |
|---|---|---|---|
| First load running | Station | "To get started, please select your **Home Station**." | "Loading stations..." spinner. No search field. Start Exploring disabled |
| No key stored (`.noKey`; no request sent) | Key | Title "API key needed". Text "InspiRail loads Dutch stations from the NS API, which needs a free API key. Get one from the NS API portal, then paste it here." | Link "Get a free key at apiportal.ns.nl" (↗) to https://apiportal.ns.nl; a secure field "Paste your NS API key"; "Save Key", disabled while the field holds only spaces |
| Keychain can't be read (`.keychainUnavailable`; no request) | Key | The title and text as above, then, above the field: "Your NS API key can't be read right now. Try again in a moment." | As above |
| NS rejected the key (401, or held back), also right after saving a key NS rejects | Key | The title and text, then above the field: "NS didn't accept your API key. Check it in Settings." | As above |
| NS refused the key (403, or held back) | Key | The title and text, then above the field: "NS refused your API key. It may be over its usage limit. Try again later." | As above |
| Saving a key: writing it and loading the stations with it | Key | The title and text, no message | The field disabled; the button reads "Saving…" beside a spinner, disabled |
| The key couldn't be written to the Keychain | Key, as before the save | As before the save | Alert "API Key Error" with the error's description (as Settings shows it), and OK. The field keeps the key; nothing is sent |
| No connection, 429, 5xx, unreadable data, or any other error, also right after saving a key | Station | The station step's text, then the panel "Error" (warning icon) with the message | Retry. No search field. Start Exploring disabled |
| Retry running | Station | The station step's text | "Loading stations..." spinner |
| Stations loaded, none selected | Station | The station step's text | Search field "Search (e.g. Amsterdam)"; the list; Start Exploring disabled |
| A station selected | Station | The station step's text | The list with a checkmark on that row only, which VoiceOver reads as selected; Start Exploring enabled |
| Start Exploring tapped | None | | The tabs |
| A load cancelled | Unchanged | Unchanged | Unchanged |

On `main`: every load error showed the station step's search field above a panel titled "Error"; key errors offered "Open Settings", the whole Settings screen as a sheet, which needed Done (or a swipe) after saving and whose Home Station row could end onboarding behind it; the first tap on a station ended onboarding, so the checkmark never showed and "Start Exploring" never ran.

## Decisions

1. **Two steps in one screen, chosen by the load's result.** `Onboarding.step` is `.key` when the station list's failure has the `.keyEntry` action, and `.station` otherwise: while loading, after a success, and for every error whose action is Retry. With no key stored the load fails at once with no request (`APIKeyProvider.currentKey()`), so a fresh install opens on the key step after the first frame, which may show the station step's spinner for as long as a Keychain read takes. The rule is the same for all four key-entry errors: no key, Keychain unavailable, 401 and 403. This is a deliberate departure from #42's "From #20" line, which asks for key entry only for no key and a 401: #21 settled the mapping app-wide, a refused key is held back for 15 minutes so a Retry would only repeat the refusal, and saving a key is the only way forward the app has. Reason: onboarding offers what every other screen offers for the same error, from the same mapping.
2. **The logic lives in `Onboarding`, which wraps `StationList`.** `Onboarding` (`InspiRail/ViewModels/Onboarding.swift`, `@MainActor @Observable`) owns one `StationList` and forwards `load(from:)` and `retry(from:)` to it, so the picker and onboarding keep one load, one failure and one Retry. It adds the step, the key step's message, whether the search field shows, the key field, the save, and the selection. `StationList` gains `show(_:)`, which shows an answer that came from elsewhere as a load's end shows its own; `load(from:)` ends through it. Reason: every state in the table is a property a test can read, and the view only draws them.
3. **The key step replaces the Settings sheet.** It shows a plain explanation, a link to apiportal.ns.nl, the key field and Save Key, with the copy in the table. Its title is "API key needed" in every key state; after any key-entry error but no key, that error's message from `message(for:)` shows above the field, including after saving a key NS then rejects. #42's "Enter API Key" label isn't needed: the field is on the step itself. The message is hidden while a save runs, so the old key's message doesn't read as the new key's. The step is a `ScrollView` whose explanation sits directly above the field, so with the keyboard up the system scrolls the field into view and the explanation stays above it; checked on the simulator, case (a). The return key saves too. Save Key and the field take the look of Start Exploring and the search field; the rest is #31's. Onboarding's sheet goes, and with it the sheet's Home Station row and its Done button. Nothing else passes `done`, so `SettingsView(done:)`, its stored property and its toolbar go too.
4. **One save path, `APIKeyCheck.saveKey(_:to:in:written:)`.** It trims the input (spaces and line breaks), saves nothing for a blank one, writes the key to the storage it is given (`KeychainManager.shared` in the app, `TestKeyStorage` in tests), calls `written`, then `keyChanged(in:)`, so every window's Settings shows the new key's status (#19). A failed write throws, and nothing is checked. Settings' `saveAPIKey()` calls it and keeps its behaviour: the field clears once the key is written (through `written`), "Saving…" shows until the check ends, and a failed write shows the "API Key Error" alert. Remove Key stays in Settings. It lives on `APIKeyCheck` because the check is the app's one object for the key, every window shares it, and `keyChanged(in:)` already lives there.
5. **After a save, onboarding shows the check's own answer.** `refresh(using:)` and `keyChanged(in:)` return the store's answer, `Result<[Station], Error>`, besides setting the status as now, and `saveKey` passes it on. Onboarding shows it through `StationList.show(_:)`, so a save sends one request, with the new key, whatever the answer: a success shows the station step with the list; a key-entry error stays on the key step with the new message; a Retry error (offline, 5xx) shows the station step with its message and Retry, the key saved but unchecked, and a later 401 for it brings the key step back. Loading again after the check would send a second download for every answer the store doesn't keep, and three more requests after a 503. A download already in flight for the old key doesn't count: `keyChanged(in:)` makes the store let go of it before the check asks, so the check starts a download of its own with the new key (#19). While the save runs, `isSavingKey` shows the key step's loading state. The station list isn't touched until the answer arrives, so the step stays on the key step throughout.
6. **#22: the selection stays in onboarding until "Start Exploring".** `Onboarding.select(_:)` keeps the tapped station in the model; the row shows the checkmark, and tapping another moves it. Nothing is written to `UserDefaults` until `startExploring()`, enabled once a station is selected, which writes `homeStationName` and then `homeStationCode` to the model's defaults (`.standard` in the app), so the name is there when the tabs appear. `hasCompletedOnboarding` is deleted, and `MainTabView` keeps gating on `homeStationCode`, through `Onboarding.isDone(homeStationCode:)`. This is a deliberate departure from #22's second Fix line, which gates on the flag:
   - once nothing in onboarding writes `homeStationCode` before "Start Exploring", the home station already means "onboarding is done";
   - existing users, who have a home station but no flag, need no migration;
   - a flag migrated from the home station would wrongly persist from runtime checks launched with `-homeStationCode ASD`, which sets the code only in the arguments domain.

   A `hasCompletedOnboarding` already in users' defaults is left there; no code cleans it up. Task 5 checks that no path writes `homeStationCode` during onboarding: the removed sheet's picker was the other one.
7. **The search field is hidden until the stations have loaded**, not disabled. It shows only when the list is neither loading nor failed (`Onboarding.offersSearch`). Reasons: on the station step's error state, a disabled field above the panel is the dead control #42 describes; with no list there is nothing to search; and a field that only exists with the list can't take a query typed before the list arrives, which is #25's lost query. The cost is that the list moves down once, when the field appears.
8. **iPad: a key that works, saved in one window, moves the other windows on.** `OnboardingView` watches the app-wide `APIKeyCheck.status` (`.onChange`). When it becomes `.working` and this window is on the key step and isn't saving a key itself, `Onboarding.keyStatusChanged(to:in:)` loads the stations, which the store just kept, so no request is sent and the window shows the list. Any other status leaves the window as it is: a key NS rejected or couldn't check in another window leaves this one on its own key step, where saving a key gives this window the current answer. Reason: one `.onChange` and one guarded load, with no request.
9. **#25's lost query.** #21 made onboarding's filter a computed property over the list, so a query typed before the list arrives applies once it does. With Decision 7 the field doesn't exist before the list, so onboarding can't lose a query; any query applies to the list as it is. Checked on the simulator in case (g), on `main` (typing while the list loads) and on the branch (typing as soon as the field appears). The search rules, synonyms and sorting are #25's and don't change.

## Review Focus

1. **A save must send one request, with the new key, and show that request's answer; a Retry error after saving must not send a second download.** Pinned by Task 3's `savingAKeyLoadsTheStationsWithIt` and `savingAKeyWhileOfflineShowsTheStationStepWithRetry` (1 request, not 2), and counted on the simulator in cases (a) to (d).
2. **A download in flight for the old key must never show as the new key's answer.** Pinned by Task 3's `savingAKeyDoesntCountAnOldKeysDownload`, also run against a mutant whose `keyChanged(in:)` forgets as for an unchanged key.
3. **Nothing may write `homeStationCode` before "Start Exploring", and a user with a home station but no flag must see the tabs at once.** Pinned by Task 4's `tappingAStationSelectsItAndWritesNothing`, `startExploringStoresTheHomeStation` and `aHomeStationEndsOnboarding`; Task 5's grep; and the simulator's cases (e) and (f).
4. **Every key-entry error must show the key step, every Retry error the station step with Retry, and a cancellation must change nothing.** Pinned by Task 2's `keyErrorsShowTheKeyStep`, `retryErrorsShowTheStationStepWithRetry` and `aCancellationChangesNothing`, with a mutant that maps `.forbidden` to Retry.
5. **With the keyboard up, the key step's explanation must stay visible, and a failed Keychain write must leave everything as it was.** The keyboard is checked on the simulator in case (a); the write failure is pinned by Task 1's `aKeyThatCantBeWrittenIsNotChecked` and Task 3's `aKeyThatCantBeWrittenShowsItsError`.

## Notes for other issues

- **#25:** onboarding's search field shows only once the list has loaded, so it can't lose a query typed before the list; the result of case (g) is recorded under Measurements. The Home Station picker's `.searchable` field still shows while it loads; its filter is computed too.
- **#31:** the key step's layout and copy (title, explanation, link, the orange message above the field); Save Key copies Start Exploring's look and the field the search field's; the station step's panel is still titled "Error".
- **#34:** the UI test #42's last Fix line asks for: a fresh install with no key reaches the station list after a key is entered on the key step, with no sheet, and "Start Exploring" opens the tabs. The flow is covered here by unit tests and the simulator checks.
- **#35:** after a Keychain read failure the key step says "Try again in a moment", but offers no Retry: only saving a key, which replaces the item, or a relaunch helps.
- **#39:** the key step is now the way an end user enters a key; whether Release builds ask end users for one is #39's.
- **Wording (to file):** on the key step, a 401 reads "NS didn't accept your API key. Check it in Settings.", as the direction asks, but onboarding has no Settings. Settings' own caption, "NS didn't accept this key.", avoids that. The 403's "Try again later" has the same limit: onboarding retries a refused key only after a relaunch once the 15 minutes have passed, or when a key is saved.

---

### Task 1: One save path for a key, which Settings uses

**Files:**
- Modify: `InspiRail/ViewModels/APIKeyCheck.swift:116-192` (`refresh`, `keyChanged`, new `saveKey`)
- Modify: `InspiRail/Pages/SettingsView.swift:154-171` (`saveAPIKey()`)
- Modify: `InspiRailTests/NetworkErrorTests.swift:579-607` (`TestKeyStorage`)
- Modify: `InspiRailTests/APIKeyCheckTests.swift` (the "A saved or removed key" section)

**Interfaces:**
- Consumes: #19's `APIKeyCheck`, `APIKeyStorage` and `KeychainManager.shared`.
- Produces:
  - `@discardableResult func refresh(using repository: StationsRepository) async -> Result<[Station], Error>` and `@discardableResult func keyChanged(in repository: StationsRepository) async -> Result<[Station], Error>`: the store's answer, whether or not it counted for the status, which they set as now.
  - `@discardableResult func saveKey(_ input: String, to storage: any APIKeyStorage, in repository: StationsRepository, written: () -> Void = {}) async throws -> Result<[Station], Error>?` (Decision 4): nil, with nothing written or called, when `input` trimmed of `.whitespacesAndNewlines` is empty; throws the storage's error when the write fails, with `written` not called and nothing checked.
  - `TestKeyStorage.init(key: String? = nil, failure: KeychainError? = nil, saveFailure: KeychainError? = nil)`: `saveAPIKey` throws `saveFailure` when set. `var storedKey: String?` reads the key held, whatever `failure` says.

- [x] **Step 1: Write the failing tests** in `APIKeyCheckTests.swift`, after `removedKeyIsNotConfigured`, over `keyCheckRepository()`-style stores built from a `TestKeyStorage()` with no key:
  - `savingAKeyTrimsItWritesItAndChecksIt`: hold the stub; start `keyCheck.saveKey("  new-test-key \n", to: storage, in: repository, written: { written.append(true) })` in a `Task`, with `written` a `Recorder<Bool>`; wait for request 1. Then `storage.storedKey == "new-test-key"`, `written.values == [true]` (written before the check answers), and `keyCheck.isCheckingNewKey`. Release: the answer's stations are `dutchCodes`, `keyCheck.status == .working`, `sentKeys == ["new-test-key"]`.
  - `savingABlankKeySavesNothing`: `saveKey(" \n\t", …)` returns nil; `storedKey` is nil, `written` never ran, no request, `status` nil.
  - `aKeyThatCantBeWrittenIsNotChecked`: `TestKeyStorage(saveFailure: .saveFailed(errSecInteractionNotAllowed))`. `saveKey("new-test-key", …)` throws a `KeychainError` whose `localizedDescription` is "Failed to save to Keychain (status: -25308)"; `written` never ran, no request, `status` nil, `isCheckingNewKey` false.
- [x] **Step 2: Run them to verify they fail.** Test command with `-only-testing:InspiRailTests/StationStoreTests`. Expected: a build failure, `value of type 'APIKeyCheck' has no member 'saveKey'` or similar.
- [x] **Step 3: Implement** `TestKeyStorage`'s additions, the two return values and `saveKey`, as in Interfaces, with doc comments that say Settings and onboarding both save through it (#42). `refresh` keeps its rule for when an answer counts.
- [x] **Step 4: Settings.** `saveAPIKey()` reports a missing store or key check as `keyChanged()` does, sets `keyOperationInFlight`, and in a `Task` calls `keyCheck.saveKey(apiKeyInput, to: KeychainManager.shared, in: stationsRepository, written: { apiKeyInput = "" })`; a thrown error sets `keyOperationError` to its `localizedDescription`; then `keyOperationInFlight = false`. The `MainActor.run` wrappers go. `removeAPIKey()` and `keyChanged()` stay.
- [x] **Step 5: Run them to verify they pass.** Expected: the suite passes, with 3 new tests, and every existing `APIKeyCheck` test passes unchanged. Then run the mutants of what Settings did before the move, each once, and restore the file: without the trim, `savingAKeyTrimsItWritesItAndChecksIt` fails; with `written` called after `keyChanged(in:)`, its `written.values == [true]` fails.
- [x] **Step 6: Typecheck.** Expected: 0 errors, 5 warnings.
- [x] **Step 7: Commit** `refactor: save a key through one path that Settings and onboarding share (#42)`

### Task 2: Onboarding's step, from the station load

**Files:**
- Create: `InspiRail/ViewModels/Onboarding.swift`
- Modify: `InspiRail/ViewModels/StationList.swift:26-39` (`show(_:)`; `load(from:)` ends through it)
- Create: `InspiRailTests/OnboardingTests.swift`

**Interfaces:**
- Consumes: #21's `StationList`, `LoadFailure` and `RecoveryAction`.
- Produces:
  - `StationList.show(_ answer: Result<[Station], Error>)`: a success sets the stations, clears the failure and ends loading; a failure sets `LoadFailure(error)` and ends loading; a cancellation changes nothing.
  - `@MainActor @Observable final class Onboarding` with `enum Step: Equatable, Sendable { case key, station }`, `let stationList = StationList()`, `init(defaults: UserDefaults = .standard)` (stored for Task 4), `var step: Step` (Decision 1), `var keyProblem: String?` (the failure's message when the step is `.key` and the failure isn't `LoadFailure(NetworkError.noKey)`; nil otherwise, and, from Task 3, while saving), `var offersSearch: Bool` (not loading and no failure), `func load(from repository: StationsRepository) async` and `func retry(from repository: StationsRepository) async`, which forward to the list.

- [x] **Step 1: Write the failing tests** in `OnboardingTests.swift`, as `extension StationStoreTests`, each `Onboarding` built over a scratch defaults suite (`UserDefaults(suiteName: "test.<UUID>.onboarding")`, removed in a `defer`):
  - `firstLoadShowsTheStationStepThenTheList`: a new onboarding is on `.station`, loading, with no search and no `keyProblem`. After `load`: `.station`, `offersSearch`, the stations are `dutchCodes`, 1 request.
  - `keyErrorsShowTheKeyStep(_ cause: KeyEntryCause, message: String?, requests: Int)`, with a test-file `enum KeyEntryCause { case noKey, unreadable, rejected, refused }` and arguments `(.noKey, nil, 0)`; `(.unreadable, "Your NS API key can't be read right now. Try again in a moment.", 0)` over `TestKeyStorage(failure: .retrievalFailed(errSecInteractionNotAllowed))`; `(.rejected, "NS didn't accept your API key. Check it in Settings.", 1)` with a 401; `(.refused, "NS refused your API key. It may be over its usage limit. Try again later.", 1)` with a 403. After `load`: `step == .key`, `keyProblem == message`, the failure's action is `.keyEntry`, no search, that many requests.
  - `retryErrorsShowTheStationStepWithRetry(reply: StubURLProtocol.Reply, message: String)`, with arguments `.failure(.notConnectedToInternet)` → "Can't reach NS. Check your internet connection.", `.status(429)` → "NS is getting too many requests. Try again in a minute.", `.status(503)` → "NS isn't available right now. Try again later.", `.body("{}")` → "NS sent data this version of InspiRail can't read. Try again later.". After `load`: `step == .station`, `failure == LoadFailure(message: message, action: .retry)`, no `keyProblem`, no search.
  - `aCancellationChangesNothing`: on the key step (no key) and on the station step (offline), `stationList.show(.failure(CancellationError()))` and `show(.failure(URLError(.cancelled)))` leave the step, the failure and `keyProblem` as they were; on a new onboarding, still loading.
- [x] **Step 2: Run them to verify they fail.** Test command with `-only-testing:InspiRailTests/StationStoreTests`. Expected: a build failure, `cannot find 'Onboarding' in scope`.
- [x] **Step 3: Implement** `show(_:)` and `Onboarding` as in Interfaces, with doc comments naming #42 and the mapping.
- [x] **Step 4: Run them to verify they pass.** Expected: the suite passes, with 4 new tests, run as 10 cases. Then the mutant of the mapping onboarding relies on (#21): `recoveryAction(for:)` giving `.forbidden` Retry fails `keyErrorsShowTheKeyStep` for `.refused` only. Restore the file.
- [x] **Step 5: Typecheck.** Expected: 0 errors, 5 warnings.
- [x] **Step 6: Commit** `fix: work out onboarding's step from the station load, the key step for every error only a key can fix (#42)`

### Task 3: Saving a key from onboarding

**Files:**
- Modify: `InspiRail/ViewModels/Onboarding.swift`
- Modify: `InspiRailTests/OnboardingTests.swift`

**Interfaces:**
- Consumes: Task 1's `APIKeyCheck.saveKey(_:to:in:written:)`; Task 2's `Onboarding` and `StationList.show(_:)`.
- Produces, on `Onboarding`:
  - `var keyInput = ""`, `var keySaveError: String?` (the alert's text; the view clears it), `private(set) var isSavingKey = false`, `var canSaveKey: Bool` (not saving, and `keyInput` not blank).
  - `func saveKey(to storage: any APIKeyStorage, checkingWith keyCheck: APIKeyCheck, in repository: StationsRepository) async` (Decision 5): returns at once while a save runs; otherwise sets `isSavingKey`, calls `keyCheck.saveKey(keyInput, to:in:written:)` with `written` clearing `keyInput`, shows a non-nil answer through `stationList.show(_:)`, and on a thrown error sets `keySaveError` to its `localizedDescription`; `isSavingKey` ends either way.
  - `func keyStatusChanged(to status: APIKeyStatus?, in repository: StationsRepository) async` (Decision 8): loads the stations only when `status == .working`, `step == .key` and no save runs.
  - `keyProblem` is nil while `isSavingKey`.

- [x] **Step 1: Write the failing tests** in `OnboardingTests.swift`, over a `TestKeyStorage()` with no key, `StationsRepository(backend: api(keyProvider: provider(storage)))` and one `APIKeyCheck`, the onboarding loaded first onto the key step:
  - `savingAKeyLoadsTheStationsWithIt`: `keyInput = "  new-test-key \n"`, `canSaveKey`. Hold; start `saveKey` in a `Task`; wait for request 1: `isSavingKey`, `!canSaveKey`, `step == .key`, no `keyProblem`, `keyInput == ""`, `keyCheck.isCheckingNewKey`. Release: `.station`, `offersSearch`, the stations are `dutchCodes`, `keyCheck.status == .working`, `storage.storedKey == "new-test-key"`, `sentKeys == ["new-test-key"]`, `!isSavingKey`.
  - `savingAKeyNSRejectsStaysOnTheKeyStep`: replies `[.status(401), .stations]`. Saving "first-test-key": `.key`, `keyProblem == "NS didn't accept your API key. Check it in Settings."`, `keyCheck.status == .rejected`, 1 request. Saving "second-test-key": `.station` with the stations, `sentKeys == ["first-test-key", "second-test-key"]`.
  - `savingAKeyWhileOfflineShowsTheStationStepWithRetry`: replies `[.failure(.notConnectedToInternet), .stations]`. After the save: `.station`, `failure == LoadFailure(message: "Can't reach NS. Check your internet connection.", action: .retry)`, 1 request, `storedKey == "new-test-key"`, `keyCheck.status == .cantCheck("Can't reach NS. Check your internet connection.")`. After `retry`: the stations, 2 requests, `sentKeys == ["new-test-key", "new-test-key"]`.
  - `aRejectionAfterAnUncheckedSaveBringsTheKeyStepBack`: replies `[.failure(.notConnectedToInternet), .status(401)]`. After the save and a `retry`: `.key`, `keyProblem == "NS didn't accept your API key. Check it in Settings."`, 2 requests.
  - `savingAKeyDoesntCountAnOldKeysDownload`: storage holds "old-test-key"; replies `[.status(401), .status(401), .stations]`. Window A's onboarding loads: `.key` after the 401 (request 1). The suite's clock moves on by `AppConfiguration.API.refusedKeyPause`; hold; window B's onboarding starts its load in a `Task`, which sends the old key (request 2, held). `stopHolding`; A saves "new-test-key": request 3 answers with the stations, and A shows `.station` with them. Release: B's load ends on `.key` with the old key's rejection, while A stays on `.station`; `keyCheck.status == .working`; `sentKeys == ["old-test-key", "old-test-key", "new-test-key"]`. Then `B.keyStatusChanged(to: keyCheck.status, in:)` moves B to `.station`, with no request.
  - `aKeyThatCantBeWrittenShowsItsError`: `TestKeyStorage(saveFailure: .saveFailed(errSecInteractionNotAllowed))`. After saving "new-test-key": `keySaveError == "Failed to save to Keychain (status: -25308)"`, `keyInput == "new-test-key"`, `.key`, no `keyProblem`, `!isSavingKey`, no request, `keyCheck.status` nil.
  - `aKeyThatWorksInAnotherWindowMovesThisOneOn`: windows A and B on the key step; A saves "new-test-key" (1 request). `B.keyStatusChanged(to: keyCheck.status, in:)`: B is on `.station` with the stations, still 1 request.
  - `aKeyRejectedInAnotherWindowLeavesThisOneAsItWas`: replies `[.status(401)]`. After A's save, `B.keyStatusChanged(to: .rejected, in:)` leaves B on `.key` with no `keyProblem`; 1 request.
- [x] **Step 2: Run them to verify they fail.** Expected: a build failure, `value of type 'Onboarding' has no member 'keyInput'` or similar.
- [x] **Step 3: Implement** as in Interfaces.
- [x] **Step 4: Run them to verify they pass.** Expected: the suite passes, with 8 new tests. Then the mutant of the store's handling of a key change (#19) that the old-download test relies on: `keyChanged(in:)` calling `forgetStations(keyChanged: false)` fails `savingAKeyDoesntCountAnOldKeysDownload`. Restore the file.
- [x] **Step 5: Typecheck.** Expected: 0 errors, 5 warnings.
- [x] **Step 6: Commit** `fix: save a key in onboarding and load the stations with it at once, with one request (#42)`

### Task 4: Selecting the home station, and Start Exploring

**Files:**
- Modify: `InspiRail/ViewModels/Onboarding.swift`
- Modify: `InspiRailTests/OnboardingTests.swift`

**Interfaces:**
- Consumes: Task 2's `Onboarding` and its stored defaults.
- Produces, on `Onboarding` (Decision 6): `private(set) var selection: Station?`, `func select(_ station: Station)`, `var canStartExploring: Bool` (a station is selected), `func startExploring()` (does nothing with no selection; otherwise writes `homeStationName`, then `homeStationCode`, to the defaults) and `static func isDone(homeStationCode: String) -> Bool` (the code isn't empty).

- [ ] **Step 1: Write the failing tests** in `OnboardingTests.swift`, over the scratch suite, with the stations loaded:
  - `tappingAStationSelectsItAndWritesNothing`: `!canStartExploring`; `startExploring()` with no selection writes nothing. `select` the station "ASD": `selection?.identifiers.code == "ASD"`, `canStartExploring`; `select` "UT": `"UT"`. Throughout, the suite has no `homeStationCode`, `homeStationName` or `hasCompletedOnboarding`, and `isDone(homeStationCode: defaults.string(forKey: "homeStationCode") ?? "")` is false.
  - `startExploringStoresTheHomeStation`: `select` "UT", `startExploring()`: the suite's `homeStationCode == "UT"`, `homeStationName == "Utrecht Centraal"`, `isDone` of the stored code is true, and no `hasCompletedOnboarding` is written.
  - `aHomeStationEndsOnboarding`: `isDone(homeStationCode: "")` is false and `isDone(homeStationCode: "ASD")` is true: a user with a home station and no flag sees the tabs.
- [ ] **Step 2: Run them to verify they fail.** Expected: a build failure, `value of type 'Onboarding' has no member 'select'`.
- [ ] **Step 3: Implement** as in Interfaces.
- [ ] **Step 4: Run them to verify they pass.** Expected: the suite passes, with 3 new tests.
- [ ] **Step 5: Typecheck.** Expected: 0 errors, 5 warnings.
- [ ] **Step 6: Commit** `fix: keep onboarding's station choice until Start Exploring, which stores the home station (#22)`

### Task 5: The screen: the key step, the station step, and the gate

**Files:**
- Modify: `InspiRail/Pages/OnboardingView.swift` (whole file)
- Modify: `InspiRail/ContentView.swift:15-24`
- Modify: `InspiRail/Pages/SettingsView.swift:24-32,133-139` (`done`, `init(done:)`, the toolbar)
- Modify: `InspiRail/Pages/RecoveryButton.swift:10-14`, `InspiRail/InspiRailApp.swift:29-33`, `InspiRail/ViewModels/StationList.swift:11-14`, `InspiRail/ViewModels/APIKeyCheck.swift:116-119` (doc comments that name the sheet or only Settings)

**Interfaces:**
- Consumes: Tasks 2 to 4's `Onboarding`; #21's `RecoveryButton`; the environment's `stationsRepository` and `apiKeyCheck`.
- Produces: `OnboardingView()`, with no parameters. `MainTabView` shows it while `!Onboarding.isDone(homeStationCode: homeStationCode)`.

- [ ] **Step 1: Onboarding's view.** `@State private var onboarding = Onboarding()` replaces `stationList`, `showingSettings`, both `@AppStorage`s and the binding; `searchText` stays, and `filteredStations` filters `onboarding.stationList.stations` as now. The body switches on `onboarding.step` inside the `NavigationStack`, keeping `.navigationBarHidden(true)` and the `.task` load; it adds the "API Key Error" alert over `keySaveError`, and `.onChange(of: keyCheck?.status)`, which runs `keyStatusChanged(to:in:)` in a `Task`. A shared header draws the icon, "Welcome to InspiRail" and the step's text.
  - **The key step**, a `ScrollView` with `.scrollDismissesKeyboard(.interactively)`: the header; "API key needed" (`.title3`, bold); the explanation (secondary, centred); the `Link`; `keyProblem` in orange (`.callout`) when set; the `SecureField` on `$onboarding.keyInput` (no autocapitalisation or autocorrection, disabled while saving, `.onSubmit` saving when `canSaveKey`), styled as the search field; Save Key, styled as Start Exploring, blue when `canSaveKey`, reading "Saving…" beside a white `ProgressView` while saving. Save reports a missing store or key check (`reportMissingStationStore(in: "Onboarding")`, `reportMissingKeyCheck(in: "Onboarding")`) and runs `onboarding.saveKey(to: KeychainManager.shared, checkingWith:in:)` in a `Task`, so that leaving doesn't cut it short.
  - **The station step**, as on `main`, except: the search field only when `offersSearch`; the error panel's `RecoveryButton` gets `action: failure.action` and an empty `enterKey`, since key errors show the key step; each row's checkmark and `.accessibilityAddTraits(.isSelected)` follow `onboarding.selection`, and a tap calls `select`; Start Exploring is blue and enabled by `canStartExploring` and calls `startExploring()`. `selectStation(_:)` goes. The sheet goes.
- [ ] **Step 2: The gate.** `MainTabView` drops `hasCompletedOnboarding` and shows `OnboardingView()` while `!Onboarding.isDone(homeStationCode: homeStationCode)`, with a comment on why the home station, not a flag, ends onboarding (#22).
- [ ] **Step 3: Settings and the doc comments.** `SettingsView` loses `done`, `init(done:)` and the toolbar; the Settings tab's `SettingsView()` is unchanged. The doc comments listed under Files stop naming onboarding's Settings sheet: `RecoveryButton` says onboarding shows it for Retry only, its key errors showing the key step; `APIKeyCheck`'s says onboarding saves a key through it too.
- [ ] **Step 4: Check the writers.** `git grep -nE 'hasCompletedOnboarding|SettingsView\(done' -- InspiRail` finds nothing. `git grep -nE 'homeStationCode *=|"homeStationCode"\)|\$homeStationCode' -- InspiRail` finds only `Onboarding.startExploring()` and the Settings tab's Home Station picker.
- [ ] **Step 5: Typecheck.** Expected: 0 errors, 5 warnings.
- [ ] **Step 6: Run the default test plan.** Expected: `** TEST SUCCEEDED **`, 135 test functions (117, and 3 + 4 + 8 + 3 new), run as 199 cases (175, and 3 + 10 + 8 + 3), 0 skipped.
- [ ] **Step 7: Commit** `fix: ask for the key in onboarding's own key step, and end onboarding on Start Exploring, not the first tap (#22, #42)`

### Task 6: Record the fix, and check each state on a simulator

**Files:**
- Modify: `CHANGELOG.md`, `[Unreleased]`
- Modify: `README.md:24`, `:30`, `:44-47` (the quick start, end users' key entry, the `ViewModels/` line)
- Modify: this plan (Measurements)

- [ ] **Step 1: `CHANGELOG.md`.** Under `### Fixed`, append:
  - When no API key is stored, or the stored one can't be used (it can't be read, or NS rejected or refused it), onboarding opens on a key step: it says InspiRail needs a free NS API key, links to apiportal.ns.nl, and takes the key there, instead of a station search over an error panel. After Save Key it loads the stations with the new key at once, with one request: the list, or why NS didn't accept the key, or Retry when NS couldn't be reached. The Settings sheet onboarding opened for the key is gone. On iPad, a key that works, saved in one window's onboarding, moves the other windows on to the station list.
  - Onboarding's search field appears once the stations have loaded.
  - Tapping a station in onboarding selects it, with a checkmark, instead of ending onboarding; tapping another moves the selection. Start Exploring stores the home station and opens the tabs. Existing users, who already have a home station, go straight to the tabs as before.

  And edit #21's lines, which describe a sheet that never shipped: "Onboarding offers Retry for the errors that had no button, and keeps Open Settings for key errors." becomes "Onboarding offers Retry for the errors that had no button."; "Onboarding's Settings sheet has a Done button; onboarding loads the stations again when it closes." goes.
- [ ] **Step 2: `README.md`.** The quick start says onboarding asks for the key on first launch, then for the home station. End users paste the key into onboarding's key step and tap Save Key, and can change it later in Settings. The `ViewModels/` line adds "onboarding's steps".
- [ ] **Step 3: Run the default test plan.** Expected: as Task 5, Step 6.
- [ ] **Step 4: Builds and stub.**
  - **Stub.** A scratch copy of the offline review stub (`.superpowers/scratch/review/runtime/stub/`) in the session's scratch directory. It answers only `gateway.apiportal.ns.nl` and never forwards a request. It reads:
    - `REVIEW_STUB_PAYLOAD`: the station list.
    - `REVIEW_STUB_KEY_STATUS`: `key:status` pairs, so a listed dummy key gets its status and any other key the list.
    - `REVIEW_STUB_FAIL_COUNT`: the first n requests fail with `-1009`.
    - `REVIEW_STUB_DELAY`: seconds before each answer.

    It logs each request with its number, its answer, and whether it carried a listed key (by its position in the list), another key or none, never a key. Build it for the simulator's architecture with `xcrun --sdk iphonesimulator clang`.
  - **Builds.** Scratch worktrees of `main` (9131266) and of this branch, outside the repo. Add a throwaway XCUITest driver to each worktree's `InspiRailUITests/`, and that target to the worktree's test plan, and build each with `build-for-testing` and its own `-derivedDataPath` in the scratch directory.
  - **Driver.** It launches the app with the stub and dummy keys only (`dummy-key-ok`, `dummy-key-reject`, `dummy-key-refuse`), never with `NS_API_KEY`, and logs `UIDRIVER phase=…` markers. It reads what a screen shows through the accessibility tree, and saves screenshots.
  - **Runs.** Each run uses `test-without-building -only-testing:… -parallel-testing-enabled NO` on `InspiRail-22`, erased first unless the case says otherwise, with nothing else booted, streaming `log stream --predicate 'subsystem == "annisu.inspirail" OR subsystem == "review.stub" OR subsystem == "review.uidriver"'`. Never a real key; "no connection" is the stub failing with `-1009`. Shut the simulator down between runs.
- [ ] **Step 5: The cases.** Screenshots go to the session's scratch directory as `22-<case>-….png`. Requests are the stub's lines between the driver's markers.
  - (a) No key: the key step with its explanation, link and field, and no search field. Tap the field: with the keyboard up, the explanation is still on screen, above the keyboard. Save `dummy-key-ok`: the list shows at once, with no sheet. 0 requests before the save, 1 for it.
  - (b) The stub rejects `dummy-key-reject` (401). Save it: the key step stays, with "NS didn't accept your API key. Check it in Settings." (1 request). Save `dummy-key-ok`: the list shows (1 request).
  - (c) The first request fails with `-1009`. Save `dummy-key-ok`: the station step shows "Can't reach NS. Check your internet connection." with Retry (1 request). Retry: the list shows (1 request).
  - (d) The stub refuses `dummy-key-refuse` (403). Save it: the key step with "NS refused your API key. It may be over its usage limit. Try again later." (1 request).
  - (e) #22: with the list shown, tap "Amsterdam Centraal": onboarding stays, with its checkmark (the row reads as selected) and Start Exploring enabled. Tap "Utrecht Centraal": the checkmark moves. Start Exploring: the tabs show, and Settings' Home Station row reads "Utrecht Centraal".
  - (f) Upgrade: install `main`'s build, and pick a home station there (key through its sheet, Done, a tap). Then install the branch's build over it with `simctl install`, and launch it with the stub and no launch arguments: the tabs show at once, with no onboarding.
  - (g) The search field before and after the list loads. Every answer 3 s late and the first request failing: save `dummy-key-ok` ("Saving…" on the key step for the 3 s), then Retry: during the load, no search field; once the list shows, the field, and "Utrecht" typed as soon as it appears leaves only Utrecht Centraal. On `main`, also with answers 3 s late: after saving the key in the sheet and Done, "Utrecht" typed while the list loads; once it arrives, whether the list is filtered (#25).
  - No log line holds a dummy key, and no fault or assertion is logged.
- [ ] **Step 6: Clean up.** Delete the worktrees, the derived data, the stub's build, any test clones (`xcrun simctl --set ~/Library/Developer/XCTestDevices list devices`), the simulator once the last run is done, and any crash reports the runs left in `~/Library/Logs/DiagnosticReports/`.
- [ ] **Step 7: Commit** `docs: record onboarding's key step and Start Exploring in the changelog, README and plan (#22, #42)`

## Measurements

To be filled in by Task 6.
