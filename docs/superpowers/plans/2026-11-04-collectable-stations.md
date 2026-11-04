# One rule for the stations that count, and a Randomize that skips visited ones (#23, #29) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every screen counts the same stations: the Dutch stations minus the home station, with a visit to the home station not counting. Discover never picks the home station or a station already in the logbook, on any pick, and says so when none is left. The Logbook's total is the collectable count, so it can reach 100 %. Settings' Reset Logbook counts what the Logbook counts.

**Architecture:** A small pure type, `StationCollection` (`InspiRail/Models/StationCollection.swift`), holds the home station's code and is the one place that says which stations and which visits count. `DiscoveryViewModel` picks through it, reading the home station from its injected `UserDefaults` and the visits from the window's `ModelContext` at every pick, and adds an "all visited" state. The Logbook works its total out through it from the store's list, or from the cached Dutch count before the list arrives; Settings counts visits through it.

**Tech Stack:** Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, SwiftUI (`@AppStorage`, `@Query`, `.onChange`, `ContentUnavailableView`), SwiftData (`ModelContext.fetch`, in-memory `ModelContainer` in tests), Swift Testing, `xcodebuild`, `xcrun simctl`, XCUITest (a throwaway driver for the runtime checks, never committed).

**Spec:** issues #23 (https://github.com/andreisudarikov19/InspiRail/issues/23, line numbers at 8c02931) and #29 (https://github.com/andreisudarikov19/InspiRail/issues/29) with its decision comment (option A, "for now"), and the owner's direction for the open choices, recorded under Decisions below. Every item was checked against `main` at e363e54 (after #22 and #42). The code is now at:
- `InspiRail/ViewModels/DiscoveryViewModel.swift`:
  - `:44-46`: the first pick after loading, `randomize()` with no home code (#23's `:52-55`).
  - `:71-99`: `randomize(excludeHomeStation:)`, which filters only the recent and home stations (#23's `:71`, #29's `:71-99`).
- `InspiRail/Pages/DiscoveryView.swift`: `:17` the `@Query` of visits, `:20` `homeStationCode`, `:306-322` the Randomize button, which passes only the home code (#29's `:16`, `:292-295`).
- `InspiRail/Pages/VisitedListView.swift`: `:18-33` the visited count without the home station and the progress over `cachedTotalStations`; `:118-135` `refreshTotalStationCount()`, from `dutchStationCount()` (#23's `:22-31`, `:118-125`).
- `InspiRail/Pages/SettingsView.swift`: `:104-113` Reset Logbook, `.disabled(visitedStations.isEmpty)` and its footer's `visitedStations.count` (#23's `:93-97`); `:224-229` `resetHistory()`, which deletes every record.
- `CHANGELOG.md:84`: 1.4.0's line on the home station.

#18's plan, `docs/superpowers/plans/2026-11-01-shared-station-store.md`, describes `StationsRepository`; #21's, `docs/superpowers/plans/2026-11-03-load-recovery.md`, Discover's load, error and Retry.

## Global Constraints

- What changes for a user: which stations Randomize can pick (never the home station, never a station in the logbook), the "all visited" state, the Logbook's total and percentage, and Settings' count and when Reset Logbook is enabled. Nothing else a user can do changes. A fix that would change more is stopped and reported, not built.
- Out of scope, and left as they are: #24 (the card's Visited toggle and its silent un-mark, the store's delete and change-date operations), #25, #26, #27, #28, #30, #31 (visual design, and whether visited stations can be suggested again), #36, #37 (the Logbook rebuild). A state that needs one of them to make full sense is noted for that issue under Notes for other issues.
- `InspiRailApp.init` stays the only place that creates a `StationsRepository`. #15's test-host gate stays: while hosting the unit tests the app shows an empty scene, builds no store and does no network work.
- Tests never reach the network: every request goes through `StubURLProtocol` (`StationStoreTests.api(keyProvider:sleep:)`). Tests never write the app's `UserDefaults` or SwiftData store: each `DiscoveryViewModel` reads a scratch defaults suite (`scratchDefaults()`, from `OnboardingTests.swift`), and visits live in an in-memory `ModelContainer`. Picks are deterministic: the view model's random choice is injected, and tests record the pool each pick chose from.
- Typecheck after every task: `xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios26.2-simulator -swift-version 5 -default-isolation MainActor $(find InspiRail -name '*.swift')`. On `main` it prints 0 errors and 5 warnings (`baseURL`, `enableNetworkLogging`, `enableDetailedLogging`, `userAgent` in `BackendAPI.swift` and `cacheLifetime` in `StationsRepository.swift`). No task may add a warning.
- Test command, one `xcodebuild` at a time: `xcodebuild test -project InspiRail.xcodeproj -scheme InspiRail -destination 'platform=iOS Simulator,id=<udid>' -derivedDataPath <scratch>`, on the throwaway iPhone 15 simulator (iOS 26.3) created for this branch, `InspiRail-23`. On `main`: `** TEST SUCCEEDED **`, 139 test functions, run as 204 cases, 0 skipped.
- Commit subjects use a conventional prefix and end with `(#23)`, `(#29)` or `(#23, #29)`. Blank lines inside the app's code are indented to the enclosing level. Test files keep their empty blank lines.

## Every Discover state

Discover's body checks, in this order: loading, a pick, all visited, an error, then the old empty state. "All visited" comes before the error, as a pick does: it needs no network, and the store keeps its list for an hour while `.task` loads again each time the tab appears, so a reload that fails an hour later, offline or with no usable key, leaves the state showing instead of replacing it with "Connection Issue" (review fix 1). Randomize is enabled only by `DiscoveryViewModel.canRandomize`: once a load has succeeded and while not all visited; it is dimmed (opacity 0.6) when disabled, as now.

| State | When | Shows | Title and text | Randomize |
|---|---|---|---|---|
| Loading | The first load, or a Retry, before any load has succeeded | Spinner | "Consulting the timetable..." | Disabled |
| Error | A load failed, and neither a station nor "all visited" is shown | `ContentUnavailableView`, `wifi.slash` | "Connection Issue"; the failure's message, such as "Can't reach NS. Check your internet connection."; Retry or Open Settings (#21) | Disabled |
| A pick | A collectable station that isn't visited was picked, or the picked one has been marked since | The station card | The station's name, type and first synonym; the map; Distance, Travel Time, Amenities, Assist; "Mark as Visited", or "Visited" once marked | Enabled |
| All visited | No collectable station is left unvisited, at the first pick after loading or at a Randomize; a failed reload keeps it | `ContentUnavailableView`, `checkmark.seal` | "All Stations Visited"; "You've visited all 399 stations." (the collectable count) | Disabled |

The old empty state ("Where to next?") stays as the last branch. No path reaches it: every pick sets a station or the "all visited" state, and the store never returns an empty list (#20). On `main` it showed only for a list holding nothing but the home station, which is now "all visited", with 0.

## Decisions

1. **The rule lives in a small pure type, `StationCollection`, not in the store.** `struct StationCollection { let homeStationCode: String }` in `InspiRail/Models/StationCollection.swift`, beside `Station` and `VisitedStation`, whose codes it compares. It says whether a visit counts (any station but the home one; with no home station, every one), which stations are collectable (the Dutch ones minus the home station), which collectable stations aren't visited, which visits count, and the Logbook's header numbers. Reason: Settings' count needs no station list at all, and the Logbook's cached total must render before the store answers, so a rule inside the store's actor would be async where its callers are synchronous; a value type is tested without a stub and called the same way from the view model and the views. The issue's "in the shared store" is met by applying the rule to the store's one list everywhere.
2. **The view model reads the home station and the visits itself, at every pick.** `DiscoveryViewModel(defaults:choose:)` keeps the `UserDefaults` it is given (`.standard` in the app, the same domain `@AppStorage` reads) and reads `homeStationCode` from it at each pick. Every method that can pick takes the window's `ModelContext` as a required `logbook:` parameter and fetches the visits from it at that pick; `FetchDescriptor` includes changes not yet saved, so a station just marked on the card counts. All windows share one container and its main context (#17), so a home station changed in Settings, a visit marked in another window and Reset Logbook are seen at the next pick with nothing to keep in sync. `randomize(excludeHomeStation:)` goes; all three picks (after loading, after Retry, Randomize) go through one private `pick(logbook:)`. Reasons: an optional parameter is how #23 happened, and inputs the view keeps in sync would bring it back with a forgotten `.onChange`; a required parameter can't be left out; the context can't be given at init, since `@StateObject` builds the view model before the environment exists. Tests pass a scratch suite and an in-memory container.
3. **The random choice is injected.** `choose: ([Station]) -> Station?`, `{ $0.randomElement() }` by default, picks from the pool the rules left. Tests pass one that records each pool's codes and returns the first, so they assert the exact pool of every pick.
4. **The recently-shown history stays, inside the pool.** The pool is the collectable stations with no visit; the last 10 shown are taken out of it; when that leaves nothing, the history is cleared and the pick is from the whole pool, as on `main`.
5. **"All visited" is a state of the view model.** `@Published private(set) var allVisitedCount: Int?` is nil, except when a pick finds the pool empty: then `station` becomes nil and `allVisitedCount` is the collectable count. `canRandomize` is `isReady && allVisitedCount == nil`. Discover shows the state with the copy in the table. Marking the card's station visited doesn't pick again: the card stays, showing "Visited", until the next Randomize, which shows the state after the last station. #24's toggle is unchanged.
6. **The state leaves by itself.** `visitsOrHomeChanged(logbook:)` picks again while `allVisitedCount` is set, or when the station on the card is now the home station (below); then the pick shows a station if one is collectable and unvisited, or the state again with the current count. `DiscoveryView` calls it from `.onChange` of its `@Query`'s codes and of `homeStationCode`, so Reset Logbook in any window, or a home-station change that frees a station, leaves the state. Discover's `.task` already loads again each time the tab appears, which picks again while no station shows, so a Reset in the same window's Settings tab is also seen on the way back. At launch, the first pick shows the state when everything is already visited. A home station changed to the station on the card picks again, since Discover never suggests the home station: another collectable, unvisited station, or "all visited" when none is left. A home station changed to any other station leaves the card, and so does marking the card's station visited (Decision 5) (review fix 2).
7. **The Logbook's total is the collectable count, and its cache holds the Dutch count.** `cachedTotalStations` keeps its key and its meaning, the number of Dutch stations, so existing caches stay right. The header works the total out on every render: from the store's list once the Logbook has it (`StationCollection.stations(among:)`, exact), and before that from the cached count less the home station (`total(dutchStationCount:)`), which is exact whenever the home station is in NS's list, as it is when it was chosen from that list. Reason: a home-station change can't make the cache wrong, since the cache doesn't depend on it, so the header follows a change at once, in every window, before and after the list loads; the list then corrects a home station NS has since dropped. The Logbook now loads `dutchStations()` instead of `dutchStationCount()`; nothing else calls `dutchStationCount()`, so it goes, and the three store tests that used it ask for `dutchStations().count`.
8. **The visited count stays "visits minus the home station's".** `countedVisits(_:)` drops only the home station's visit. A visit whose code is no longer in NS's list still counts, so the Logbook could show more visited than its total (the bar stops at 100 %); noted for #37, not fixed.
9. **Settings counts what the Logbook counts, and Reset Logbook deletes everything.** The footer and the button's enabled state use `countedVisits(visitedStations).count`; Reset Logbook stays enabled only when it is above 0. `resetHistory()` is unchanged: it deletes every record in the unfiltered `@Query`, the home station's hidden visit included, so a later home-station change doesn't bring a reset visit back.
10. **The CHANGELOG.** 1.4.0's line becomes what 1.4.0 did. Its commit (1fcbf77) made the visited count leave the home station's visit out, as the list already did, while the total kept counting every Dutch station; so the line says the home station was left out of the list and the visited count, not the percentage. (The brief's wording was "the list only"; the code shows the count changed in 1.4.0 too.) `[Unreleased]` gains the percentage, Discover never picking the home station or a visited station, the "all visited" state and Settings' count. The README describes neither Randomize nor the Logbook's count; its `Models/` line gains "the stations that count".

## Review Focus

1. **No pick may be the home station or a visited station, on any path: the first after loading, after Retry, Randomize, after a home change in Settings, after a visit marked or deleted.** Pinned by Task 2's tests, which assert each pick's whole pool, and counted on the simulator in cases (a) and (b).
2. **Marking the card's station must not pick again; only the next Randomize shows "all visited".** Pinned by Task 3's `markingTheLastStationKeepsTheCardUntilTheNextRandomize`; case (c).
3. **"All visited" must leave by itself on Reset Logbook, in any window, and on a home change that frees a station, and must show at launch.** The view model's side is pinned by Task 3's tests; the `.onChange` wiring isn't unit-testable and is checked on the simulator in case (c), for one window only (an iPhone has one).
4. **The Logbook must reach 100 % with every station but the home one visited, and its total must follow a home change before the list loads.** Pinned by Task 1's `everyStationButTheHomeOneIsOneHundredPercent` and `theTotalFollowsAHomeStationChangeBeforeAndAfterTheListLoads`; case (d).
5. **Settings' count must match the Logbook's, Reset Logbook must be disabled when only the home station's visit is recorded, and Reset must still delete that visit.** The count is pinned by Task 1's `onlyTheHomeStationsVisitLeavesNothingToReset`; `resetHistory()` is unchanged and read in review; case (e) checks the screen.

## Notes for other issues

- **#24:** with visited stations never suggested, the card's "Visited" button shows only right after marking, until the next Randomize; its silent un-mark is unchanged.
- **#31:** the "all visited" state's look and copy ("All Stations Visited", "You've visited all N stations."), which offers no way on: whether visited stations can come back, or Reset Logbook is offered there, is #31's question (#29's "for now").
- **#37:** a visit whose code is no longer in NS's list still counts in the Logbook (and in Settings), so the count can pass the total; the bar stops at 100 %. The Logbook rebuild should decide whether such visits count.

---

### Task 1: The rule, and the Logbook's and Settings' counts

**Files:**
- Create: `InspiRail/Models/StationCollection.swift`
- Modify: `InspiRail/Pages/VisitedListView.swift:15-33,73-82,116-185` (the counts, the refresh, `StatsHeader`)
- Modify: `InspiRail/Pages/SettingsView.swift:104-113` (Reset Logbook's footer and enabled state)
- Modify: `InspiRail/ViewModels/StationsRepository.swift:64-67` (`dutchStationCount()` goes)
- Modify: `InspiRailTests/StationStoreTests.swift:115-137,211-218` (`dutchStations().count` for `dutchStationCount()`)
- Create: `InspiRailTests/StationCollectionTests.swift`

**Interfaces:**
- Produces, in `StationCollection.swift`:
  - `struct StationCollection: Equatable` with `let homeStationCode: String` (empty when none is set) and `init(homeStationCode: String)`.
  - `func counts(_ stationCode: String) -> Bool`: any code but the home station's.
  - `func stations(among dutchStations: [Station]) -> [Station]`: the collectable ones, in their order.
  - `func unvisited(among dutchStations: [Station], visitedCodes: Set<String>) -> [Station]`: the collectable ones with no visit.
  - `func countedVisits(_ visits: [VisitedStation]) -> [VisitedStation]`: the visits that count, in their order.
  - `func total(dutchStationCount: Int) -> Int`: the count less one when a home station is set, never below 0.
  - `struct Progress: Equatable { let visited: Int; let total: Int }` (total 0 while unknown) with `var fraction: Double` (`min(1, visited / total)`, 0 when the total is 0) and `var percentage: Int` (`fraction × 100`, rounded), and `func progress(of visits: [VisitedStation], dutchStations: [Station]?, cachedDutchStationCount: Int) -> Progress`: visited is `countedVisits(visits).count`; total is `stations(among:).count` of the list when given, else `total(dutchStationCount:)` of the cache.
- Produces, in the tests: `dutchFixtureStations() throws -> [Station]` (the fixture decoded, Dutch only, sorted by name: HT, ASD, UT, ZL) and `inMemoryLogbook(visits codes: [String]) throws -> ModelContainer` (a container over `LogbookStore.schema` stored in memory only, under a configuration name of its own, with one saved `VisitedStation` per code), free functions in `StationCollectionTests.swift` that Tasks 2 and 3 use.

- [x] **Step 1: Write the failing tests** in `StationCollectionTests.swift`, `@Suite("The stations that count") @MainActor struct StationCollectionTests`, over `dutchFixtureStations()` and `inMemoryLogbook(visits:)`:
  - `theHomeStationIsNotCollectable`: home "UT": `stations(among:)` codes `["HT", "ASD", "ZL"]`, `total(dutchStationCount: 4) == 3`, `!counts("UT")`, `counts("ASD")`.
  - `withNoHomeStationEveryDutchStationIsCollectable`: home "": codes `["HT", "ASD", "UT", "ZL"]`, `total(dutchStationCount: 4) == 4`, `counts("UT")`.
  - `aVisitToTheHomeStationDoesntCount`: visits UT, ASD, ZL with home "UT": `countedVisits` codes are ASD and ZL (as a set); with home "": all three.
  - `unvisitedLeavesOutTheHomeStationAndEveryVisitedStation`: home "UT", visited `["ASD", "UT"]`: `["HT", "ZL"]`; visited `["HT", "ASD", "ZL"]`: empty.
  - `everyStationButTheHomeOneIsOneHundredPercent`: visits HT, ASD, ZL; home "UT"; with the list: `Progress(visited: 3, total: 3)`, `percentage == 100`. With the home station's visit added too: the same.
  - `theTotalFollowsAHomeStationChangeBeforeAndAfterTheListLoads`: visits HT, ASD, ZL. Home "UT", list nil, cache 4: `Progress(visited: 3, total: 3)`. Home "ASD": with the list and with only the cache, `Progress(visited: 2, total: 3)`, `percentage == 67`.
  - `beforeAnyListTheTotalIsUnknown`: list nil, cache 0, home "UT", visits ASD: `Progress(visited: 1, total: 0)`, `fraction == 0`.
  - `aHomeStationNotInTheListLeavesEveryDutchStation`: home "XX" with the list: total 4.
  - `aVisitNoLongerInTheListStillCounts` (the edge noted for #37): visits HT, ASD, ZL and "OLD", home "UT", with the list: `Progress(visited: 4, total: 3)`, `fraction == 1`, `percentage == 100`.
  - `onlyTheHomeStationsVisitLeavesNothingToReset`: visits UT, home "UT": `countedVisits` is empty, so Settings' footer counts 0 and Reset Logbook is disabled, as the Logbook shows 0; with home "ASD", 1.
- [x] **Step 2: Run them to verify they fail.** Test command with `-only-testing:InspiRailTests/StationCollectionTests`. Expected: a build failure, `cannot find 'StationCollection' in scope`.
- [x] **Step 3: Implement** `StationCollection` as in Interfaces, with doc comments naming #23 and #29.
- [x] **Step 4: The Logbook.** `VisitedListView`: `visitedExcludingHome` becomes `collection.countedVisits(visitedStations)`; `visitedCount` and `progress` go, replaced by `collection.progress(of: visitedStations, dutchStations: dutchStations, cachedDutchStationCount: cachedTotalStations)`, with `@State private var dutchStations: [Station]?`; `StatsHeader` takes `let progress: StationCollection.Progress` and reads `visited`, `total`, `fraction` and `percentage` from it, its look unchanged. `refreshTotalStationCount()` becomes `refreshStations()`: `dutchStations()` from the store, kept in `dutchStations`, its count written to `cachedTotalStations`; a failure keeps what is shown, as now. The cache's doc comment says it holds the Dutch count, which doesn't depend on the home station (Decision 7).
- [x] **Step 5: Settings.** Reset Logbook's `.disabled` and footer use `StationCollection(homeStationCode: homeStationCode).countedVisits(visitedStations).count`, with a comment that Reset still deletes every record (Decision 9). `resetHistory()` is unchanged.
- [x] **Step 6: The store.** Delete `dutchStationCount()`; the three store tests that called it use `dutchStations().count`, their expectations unchanged.
- [x] **Step 7: Run them to verify they pass.** Expected: the suite passes, with 10 new tests. Then the mutants of what the Logbook did before, each once, restoring the file after: `counts` returning true fails `aVisitToTheHomeStationDoesntCount`, `everyStationButTheHomeOneIsOneHundredPercent`, and `onlyTheHomeStationsVisitLeavesNothingToReset`; `fraction` without `min(1, …)` fails `aVisitNoLongerInTheListStillCounts`; `progress` ignoring the cache fails `theTotalFollowsAHomeStationChangeBeforeAndAfterTheListLoads`.
  (Changed during execution: the first green run crashed in the tests, reading visits whose in-memory container had already been released, so the suite is a `final class` that keeps every logbook it opens until the test ends, through `logbookVisits(_:)`. The first mutant is `countedVisits` returning every visit, which is what Settings counted on `main`, rather than `counts` returning true, which would also break the collectable stations: it fails `aVisitToTheHomeStationDoesntCount`, `everyStationButTheHomeOneIsOneHundredPercent`, `onlyTheHomeStationsVisitLeavesNothingToReset` and `theTotalFollowsAHomeStationChangeBeforeAndAfterTheListLoads`. The other two failed exactly the test named. The store suite and this one: 116 test functions, 181 cases, all passing. `VisitedListView.swift`'s 39 and `SettingsView.swift`'s 3 empty blank lines inside code are indented to the enclosing level, as the app's other files are.)
- [x] **Step 8: Typecheck.** Expected: 0 errors, 5 warnings.
- [x] **Step 9: Commit** `fix: count the same stations on every screen: the Dutch stations but the home one (#23)`

### Task 2: Discover's pick skips the home station and every visited station

**Files:**
- Modify: `InspiRail/ViewModels/DiscoveryViewModel.swift` (init, `loadStations`, `retry`, `randomize`, a private `pick`)
- Modify: `InspiRail/Pages/DiscoveryView.swift:66-72,306-322,350-358` (the load, Randomize, Retry)
- Modify: `InspiRailTests/LoadRecoveryTests.swift:16-140` (the Discover tests' set-up only)
- Create: `InspiRailTests/DiscoverPickTests.swift`

**Interfaces:**
- Consumes: Task 1's `StationCollection.unvisited(among:visitedCodes:)`, `dutchFixtureStations()` and `inMemoryLogbook(visits:)`; `scratchDefaults()` from `OnboardingTests.swift`.
- Produces, on `DiscoveryViewModel`:
  - `init(defaults: UserDefaults = .standard, choose: @escaping ([Station]) -> Station? = { $0.randomElement() })` (Decisions 2, 3).
  - `func loadStations(from repository: StationsRepository, logbook: ModelContext) async`, `func retry(from repository: StationsRepository, logbook: ModelContext) async` and `func randomize(logbook: ModelContext)`: each pick reads `homeStationCode` from the defaults and the visits' codes from `logbook`, and chooses from `unvisited(among:visitedCodes:)` less the recently shown (Decision 4). A failed fetch is logged and treated as no visits. With an empty pool this task picks nothing (Task 3 adds the state).
  - `randomize(excludeHomeStation:)` is gone.
- Produces, in the tests: `pickRecorder() -> (choose: ([Station]) -> Station?, pools: Recorder<[String]>)`, which records each pool's codes and returns its first station.

- [x] **Step 1: Write the failing tests** in `DiscoverPickTests.swift`, as `extension StationStoreTests`, each view model over a scratch suite with `homeStationCode` set, an in-memory logbook and `pickRecorder()`:
  - `theFirstPickSkipsTheHomeStationAndVisitedStations`: home "UT", visits ASD. After `loadStations`: `pools.values == [["HT", "ZL"]]`, the station is HT.
  - `thePickAfterRetrySkipsThemToo`: replies `[.status(503), .status(503), .status(503), .stations]`; the load fails with no pool; after `retry`: `[["HT", "ZL"]]`, HT.
  - `randomizeSkipsThem`: home "UT", visits ASD, after the load: `randomize` chooses from `["ZL"]` (HT was just shown).
  - `aHomeStationChangedBetweenPicksCountsAtTheNextPick`: home "UT", no visits: the load's pool `["HT", "ASD", "ZL"]`; the suite's home set to "ZL": `randomize`'s pool `["ASD", "UT"]`.
  - `aVisitBetweenPicksCountsAtTheNextPick`: home "UT", no visits, after the load (HT): a visit to ASD inserted and not saved, as the card's toggle leaves it: `randomize`'s pool `["ZL"]`; with that visit deleted and saved, as Reset Logbook does: the next pool `["ASD"]` (HT and ZL recent).
  - `recentlyShownStationsComeBackOnlyWhenTheyAreAllThatIsLeft`: home "UT", visits ASD: the load and two Randomizes choose from `[["HT", "ZL"], ["ZL"], ["HT", "ZL"]]` and show HT, ZL, HT.
- [x] **Step 2: Run them to verify they fail.** Test command with `-only-testing:InspiRailTests/StationStoreTests`. Expected: a build failure, `extra arguments` or `argument passed to call that takes no arguments` for `DiscoveryViewModel(defaults:choose:)`.
- [x] **Step 3: Implement** as in Interfaces, with doc comments naming #23 and #29. `LoadRecoveryTests`' six Discover tests build their view model over a scratch suite and pass an empty in-memory logbook; their expectations don't change.
- [x] **Step 4: Discover.** `.task` calls `loadStations(from: stationsRepository, logbook: modelContext)`; Retry, `retry(from:logbook:)`; Randomize, `randomize(logbook: modelContext)`.
- [x] **Step 5: Run them to verify they pass.** Expected: the suite passes, with 6 new tests, and the six Discover tests in `LoadRecoveryTests` pass unchanged. Then the mutant of the history kept from `main`: without its filter, `recentlyShownStationsComeBackOnlyWhenTheyAreAllThatIsLeft` fails. Restore the file.
  (Changed during execution: the tests build their view model and logbook through a helper, `discover(home:visits:in:)`, which `LoadRecoveryTests` uses too, with no home station; that file now imports SwiftData. Without the history's filter, `recentlyShownStationsComeBackOnlyWhenTheyAreAllThatIsLeft` fails, and so do `randomizeSkipsThem`, `aHomeStationChangedBetweenPicksCountsAtTheNextPick` and `aVisitBetweenPicksCountsAtTheNextPick`, whose exact pools leave out the station just shown. The store suite: 112 test functions, 177 cases, all passing. `DiscoveryView.swift`'s 4 empty blank lines inside code are indented, and the Randomize button's two lines lose their trailing spaces.)
- [x] **Step 6: Typecheck.** Expected: 0 errors, 5 warnings.
- [x] **Step 7: Commit** `fix: never pick the home station or a visited station on Discover, on any pick (#23, #29)`

### Task 3: The "all visited" state

**Files:**
- Modify: `InspiRail/ViewModels/DiscoveryViewModel.swift`
- Modify: `InspiRail/Pages/DiscoveryView.swift` (the body, Randomize, a new `allVisitedView(count:)`)
- Modify: `InspiRailTests/DiscoverPickTests.swift`

**Interfaces:**
- Consumes: Task 2's `pick(logbook:)` and Task 1's `StationCollection.stations(among:)`.
- Produces, on `DiscoveryViewModel` (Decisions 5, 6): `@Published private(set) var allVisitedCount: Int?`; `var canRandomize: Bool`; `func visitsOrHomeChanged(logbook: ModelContext)`. A pick with an empty pool sets `station` to nil and `allVisitedCount` to the collectable count, without calling `choose`; any other pick clears it.

- [x] **Step 1: Write the failing tests** in `DiscoverPickTests.swift`:
  - `withEveryStationVisitedLoadingShowsAllVisited`: home "UT", visits HT, ASD, UT, ZL. After the load: `station == nil`, `allVisitedCount == 3`, `!canRandomize`, `isReady`, `!isLoading`, `failure == nil`, no pool.
  - `markingTheLastStationKeepsTheCardUntilTheNextRandomize`: home "UT", visits ASD, ZL; the load shows HT and `canRandomize`. A visit to HT inserted, then `visitsOrHomeChanged`: still HT, `allVisitedCount == nil`, `canRandomize`. `randomize`: `station == nil`, `allVisitedCount == 3`, `!canRandomize`.
  - `resetLogbookLeavesAllVisited`: from the state above, every visit deleted and saved, then `visitsOrHomeChanged`: a station from `["HT", "ASD", "ZL"]`, `allVisitedCount == nil`, `canRandomize`.
  - `aHomeStationThatFreesAStationLeavesAllVisited`: home "UT", visits HT, ASD, ZL, all visited after the load; the suite's home set to "ZL", then `visitsOrHomeChanged`: the pool `["UT"]`, the station UT, `allVisitedCount == nil`.
- [x] **Step 2: Run them to verify they fail.** Expected: a build failure, `value of type 'DiscoveryViewModel' has no member 'allVisitedCount'`.
- [x] **Step 3: Implement** as in Interfaces.
- [x] **Step 4: Discover.** After the error branch, `else if let count = viewModel.allVisitedCount { allVisitedView(count: count) }`: a `ContentUnavailableView` with `Label("All Stations Visited", systemImage: "checkmark.seal")` and `Text("You've visited all \(count) stations.")`, with no actions. Randomize is disabled and dimmed by `!viewModel.canRandomize`. On the `VStack` beside `.task`: `.onChange(of: visitedStations.map(\.stationCode))` and `.onChange(of: homeStationCode)`, each calling `viewModel.visitsOrHomeChanged(logbook: modelContext)`, with a comment naming Reset Logbook in any window and a freeing home change (#29). (Changed in review: the branch is now above the error branch; see Review fixes.)
- [x] **Step 5: Run them to verify they pass.** Expected: the suite passes, with 4 new tests.
  (Changed during execution: `resetLogbookLeavesAllVisited` starts from a load with HT, ASD and ZL visited rather than from the previous test's state, and its pick is HT, the first of `["HT", "ASD", "ZL"]`. The store suite: 116 test functions, 181 cases, all passing.)
- [x] **Step 6: Typecheck.** Expected: 0 errors, 5 warnings.
- [x] **Step 7: Run the default test plan.** Expected: `** TEST SUCCEEDED **`, 159 test functions (139, and 10 + 6 + 4 new), run as 224 cases, 0 skipped.
- [x] **Step 8: Commit** `feat: show "all visited" on Discover once every station but the home one is in the logbook (#29)`

### Task 4: Record the fix, and check each state on a simulator

**Files:**
- Modify: `CHANGELOG.md` (`[Unreleased]`, and 1.4.0's `### Fixed`)
- Modify: `README.md:36` (the `Models/` line)
- Modify: this plan (Measurements)

- [x] **Step 1: `CHANGELOG.md`.** 1.4.0's line becomes: "The home station's visit is left out of the visited count, as it already was from the timeline list (before, it counted toward the visited count). The total still counted every Dutch station, the home station included, so the percentage couldn't reach 100 %." Under `[Unreleased]`:
  - `### Changed`: "Randomize never suggests a station that is already in the logbook. Once every station but the home station is visited, Discover says "You've visited all N stations." instead of suggesting one, with Randomize disabled, until a station is free again: after Reset Logbook, in any window, or a change of home station that frees one. A station marked visited stays on the card until the next Randomize."
  - `### Fixed`: "Discover never suggests the home station. Its first suggestion after loading could." / "The Logbook's percentage leaves the home station out: its total counts every Dutch station but the home station, so a logbook with every other station visited shows 100 %. The total follows a change of home station at once, also before the station list has loaded." / "Settings' Reset Logbook counts the visits the Logbook shows, so it leaves a visit to the home station out, and is disabled when the Logbook shows none. It still deletes every visit, the home station's included."
- [x] **Step 2: `README.md`.** The `Models/` line reads "SwiftData & Codable data models, logbook store, and the stations that count".
- [x] **Step 3: Builds and stub.**
  - **Stub.** A scratch copy of the offline review stub (`.superpowers/scratch/review/runtime/stub/`) in the session's scratch directory, which answers only `gateway.apiportal.ns.nl` with `REVIEW_STUB_PAYLOAD` and never forwards a request. Its payload is a short list in NS's shape: six Dutch stations (Amsterdam Centraal ASD, Delft DT, Groningen GN, Leiden Centraal LEDN, Utrecht Centraal UT, Zwolle ZL) and one German one (Berlin Hbf BHF).
  - **Build.** A scratch worktree of this branch outside the repo, with a throwaway XCUITest driver in its `InspiRailUITests/` and that target added to the worktree's test plan, built with `build-for-testing` and its own `-derivedDataPath`. The driver launches the app with the stub and the dummy key `dummy-key` in `NS_API_KEY` (Debug), never a real key, reads the screen through the accessibility tree, prints `UIDRIVER` markers, and saves screenshots. The home station is chosen through onboarding (Start Exploring), not a launch argument, which would mask Settings' change.
  - **Runs.** `test-without-building -only-testing:… -parallel-testing-enabled NO` on `InspiRail-23`, erased first, the only simulator of ours booted, with `log stream` on the app's and the stub's subsystems; shut down after.
- [x] **Step 4: The cases.** Screenshots go to the session's scratch directory as `23-<case>-….png`.
  - (a) Home station: onboarding picks Utrecht Centraal; 20 loads (the first after Start Exploring, then 19 relaunches), each recording the card's station. None is Utrecht Centraal.
  - (b) Visited: Randomize and Mark as Visited three times, then 20 Randomizes: each shows one of the two stations left.
  - (c) All visited: mark the remaining stations; after the last, the card stays with "Visited"; Randomize shows "All Stations Visited" and "You've visited all 5 stations.", with Randomize disabled. Reset Logbook in Settings (Delete All); back on Discover, a pick, Randomize enabled.
  - (d) Logbook: with every station but Utrecht Centraal visited, "5 of 5" and 100 %. Settings' Home Station set to Amsterdam Centraal: "4 of 5", 80 %.
  - (e) Settings: Reset Logbook; mark one station visited and make it the home station: the Logbook shows "0 of 5", Settings' footer "This will remove all 0 stations from your history." and Reset Logbook disabled.
  - No log line holds the dummy key, and no fault or assertion is logged.
  (Changed during execution: the stub's copy needed no change, only the short payload, written by a script kept apart from it. The README's `Models/` line wraps onto a second line, as the layout's other long entries do. The simulator was erased once, before (a); the cases ran in order, each relaunching the app and carrying on from the state the previous one left, so (b) to (e) never set the home station by a launch argument. (d) also checked Discover after the home change, and (e)'s station happened to be Utrecht Centraal, which (d) had freed. Each case's numbers are under Measurements.)
- [x] **Step 5: Clean up.** Delete the worktree, the derived data, the stub copy, any test clones (`xcrun simctl --set ~/Library/Developer/XCTestDevices list devices`), the simulator once the last run is done, and any crash reports the runs left in `~/Library/Logs/DiagnosticReports/`.
- [x] **Step 6: Commit** `docs: record the stations that count and Discover's "all visited" in the changelog, README and plan (#23, #29)`

## Measurements

On the throwaway iPhone 15 simulator (iOS 26.3), `InspiRail-23`, erased once before (a), with a scratch copy of the offline stub serving the short list (six Dutch stations, one German), the dummy key `dummy-key` in `NS_API_KEY` and no real key, driven by a throwaway UI test outside the repo. The branch is c147141 (Task 3). Screenshots are in the session's scratch directory as `23-<case>-….png`. Every case passed.

| Case | What was done | Seen |
|---|---|---|
| (a) Home station | Onboarding chose Utrecht Centraal and Start Exploring; then 19 relaunches: 20 loads | The 20 first picks: Amsterdam Centraal 4, Delft 5, Groningen 4, Leiden Centraal 4, Zwolle 3; Utrecht Centraal 0 times (`23-a-load-01.png`, `23-a-load-20.png`) |
| (b) Visited | Three cards marked visited (Leiden Centraal, Amsterdam Centraal, Zwolle), each new; then 20 Randomizes | Every one of the 20 rolls was Delft or Groningen, the two stations left; 0 outside them (`23-b-roll-20.png`) |
| (c) All visited | Groningen marked; Randomize showed Delft, the last, marked too; Randomize; then Settings, Reset Logbook, Delete All, and back to Discover | After the last mark the card stayed on Delft, reading "Visited" (`23-c-last-marked.png`). Randomize showed "All Stations Visited" and "You've visited all 5 stations.", no card, Randomize disabled and dimmed (`23-c-all-visited.png`). After Reset Logbook, Discover showed a pick, Zwolle, with Randomize enabled (`23-c-after-reset.png`) |
| (d) Logbook | All five stations but Utrecht Centraal marked; then Settings' Home Station set to Amsterdam Centraal | The Logbook read "5 of 5", 100 % (VoiceOver: "5 of 5 stations visited, 100 percent", `23-d-logbook-100.png`). After the home change, "4 of 5", 80 % (`23-d-logbook-home-changed.png`): the total stays 5, one fewer than the six Dutch stations, since both home stations are in the list, and Amsterdam Centraal's visit no longer counts. Discover left "all visited" by itself and showed Utrecht Centraal, the station the change freed (`23-d-discover-freed.png`) |
| (e) Settings | Reset Logbook; the card's station (Utrecht Centraal) marked visited and made the home station | The Logbook read "0 of 5", 0 % (`23-e-logbook.png`); Settings' footer read "This will remove all 0 stations from your history." and Reset Logbook was disabled (`23-e-settings.png`) |

The 24 launches sent 24 requests, one each, all answered by the stub. No log line held the dummy key, and no fault or assertion was logged. On iPad, a Reset Logbook in another window reaches Discover through its `.onChange`; an iPhone has one window, so that path is covered by the view model's tests only.

The default test plan passes 159 test functions, run as 224 cases, 0 skipped (139 and 204 on `main`). The typecheck prints 0 errors and 5 warnings, the same as on `main`.

The first unit-test run of Task 1, which crashed in the test, left two InspiRail crash reports from its test clone, and the runs left three more from their clones (`UsageTrackingAgent`, `chronod`), each written within 4 s of one of those runs ending; all five were deleted. `gamed` reports from an Apple TV simulator this branch didn't create were left alone.
