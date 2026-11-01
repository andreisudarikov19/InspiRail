# Open the logbook safely (#17) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app never deletes the logbook. It opens one store for all its windows, and if the store can't be opened it says so and offers Try Again or Start a New Logbook, which moves the old store aside instead of deleting it.

**Architecture:** A small `LogbookStore` value type opens the store at a given URL and moves it aside on request. It never deletes anything, and Swift Testing tests it against temporary directories. An `@Observable` `Logbook`, created once by the App, holds the open container or the error, and runs Try Again and Start a New Logbook. Every window shows the tabs with that one container, or the error screen. The dead migration plan goes.

**Tech Stack:** Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, SwiftUI, SwiftData, Observation, Swift Testing, `xcodebuild`, `xcrun simctl`, `sqlite3`.

**Spec:** issue #17, https://github.com/andreisudarikov19/InspiRail/issues/17 (its line numbers refer to 8c02931), and the owner's direction for its open choices, recorded under Decisions below. Every item was checked against `main` at 9752135 (after #14, #15 and #16). The store code is now `InspiRail/InspiRailApp.swift:39-117` and the migration plan is unchanged in `InspiRail/NetworkEngine/VisitedStationMigration.swift`.

## Global Constraints

- The logbook is the user's only record of their visits. No code path deletes, truncates or overwrites a store file. The only file operations are creating the store's folder, opening the store, and moving the store's files into a new backup folder.
- Existing stores keep opening unchanged: same file (`Library/Application Support/default.store`), same schema (`Schema([VisitedStation.self])`), no migration plan, no change to `VisitedStation`'s stored fields (`stationCode`, `stationName`, `dateVisited`, `notes`, `rating`, `_isFavorite`).
- The only new thing a user can see is the error screen and its confirmation alert. Everything else the app does stays as it is.
- #15's test-host gate stays: `isHostingUnitTests`, the early return in `init()`, and the `Color.clear` scene with its in-memory store. While hosting the unit tests the app never opens or creates the real store.
- Tests never touch the app's real store location. Each test works in its own directory under `FileManager.default.temporaryDirectory`.
- Out of scope, and left as they are: the shared station store and session (#18), visit saving and the silent un-mark (#24), onboarding (#22, #42), the Logbook UI (#37), and Settings' Reset History.
- Typecheck after every task: `xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios26.2-simulator -swift-version 5 -default-isolation MainActor $(find InspiRail -name '*.swift')`. On `main` it prints 0 errors and 13 warnings (26 `warning:` lines, since each is echoed under its source line). No task may add a warning.
- Test command: `xcodebuild test -project InspiRail.xcodeproj -scheme InspiRail -destination 'platform=iOS Simulator,name=iPhone 17'`. On `main`: `** TEST SUCCEEDED **`, 17 tests passed.
- Commit subjects end with `(#17)`. Blank lines inside the app's code are indented to the enclosing level. Test files keep their empty blank lines.

## What the history shows about the stored schema

- Only two shapes of `VisitedStation` were ever stored, and only one model was ever in the schema.
  - **Three fields:** `stationCode` (unique), `stationName` and `dateVisited`. This is the Sprint 1 project in the archived predecessor repo (same bundle ID `annisu.rnsapp`, default store), the initial commit d565b4c, and the internal builds before 1.3.0.
  - **Six fields:** eeefb47 (1.3.0, build 4, 2026-06-04) added `notes: String?`, `rating: Int?` and `_isFavorite: Bool?`. Every release since, through 1.4.1 and `main`, has this shape. #16 removed only computed members.
- Adding optional attributes is a lightweight migration, which SwiftData infers and runs by itself when no migration plan is given. So any store a past build left behind opens with the live model, as it does today.
- The migration plan was never wired in. Its "V1" (`VisitedStationV1`, with `notes` and `rating`) and "V2" (`VisitedStationV2`, with a non-optional `isFavorite`) match neither stored shape, and their entity names aren't `VisitedStation`.

## Decisions

1. **One container, created once by the App.** `InspiRailApp` holds a `@State` `Logbook`, created in `init()`, and the `WindowGroup` content gives every window the same `ModelContainer` through `.modelContainer(container)` on its root view. Reason: one container means one main context, so a visit marked in one iPad window shows in the others. It is attached to each window's root view rather than with the scene-level `.modelContainer(_:)`, because that modifier needs a container even when the store fails to open, and a placeholder container there would be the in-memory fallback this fix removes. The instance is the same either way. The test-host path is unchanged and never creates the `Logbook`.
2. **Never delete the store, and no in-memory fallback.** If the store can't be opened, every window shows a full-screen error instead of the tabs. Reason: a deleted store loses every visit, and an in-memory fallback silently loses each visit added after it. The error screen has a plain explanation, the error's `localizedDescription`, **Try Again**, and **Start a New Logbook** behind a confirmation alert. (Changed after review: the `localizedDescription` is gone, and every window tries again when it becomes active. See Review fixes.) Copy:
   - Title: "Can't Open Your Logbook"
   - Text: "The logbook with your visits couldn't be opened. Nothing has been deleted."
   - Text once Start a New Logbook has moved the old store but a new one couldn't be opened (added after review): "Your old logbook was moved to a backup folder on this device, but a new one couldn't be opened."
   - Alert title "Start a New Logbook?", message "Your current logbook will be moved to a backup folder on this device, and you'll start with an empty logbook. The app won't show the visits in the backup.", buttons "Cancel" and "Start New Logbook" (destructive).
3. **Starting a new logbook moves the store aside.** `default.store`, `default.store-wal` and `default.store-shm`, whichever exist, move into `Application Support/Logbook Backups/<UTC time>/`, named `yyyy-MM-dd'T'HH-mm-ss'Z'` (no colons, sorts by time), and a fresh store opens. Reason: the old visits stay on the device for recovery. If a move fails part-way, the files already moved go back and the error is shown, so a store is never split from its WAL. An existing backup folder is never reused or overwritten.
4. **Delete the dead migration plan.** The history above shows no stored shape that needs one. A comment on `VisitedStation` records the one past change and says that the first change SwiftData can't migrate by itself must bring in versioned schemas, with the current shape as V1. A test opens a three-field store with the live model, to pin that the old shape still opens.
5. **Two small types, both tested.** `LogbookStore` (file operations, takes the store URL) and `Logbook` (the app-wide state behind the two buttons). Reason: the buttons' logic, including "never move a store that is open", is checked in unit tests, not only by driving the UI. `LogbookStore.defaultURL` is pinned in a test to the URL of SwiftData's default configuration, which the old code used.
6. **Start a New Logbook does nothing while the logbook is open, and Try Again keeps an open container.** Reason: on iPad two windows can show the error and the alert at once. After the first confirmation, the second must not move the store that is now open.
7. **Logging.** A failed open logs one error line, and a move logs the backup folder, under `AppConfiguration.subsystem`, category `database`, as before. Reason: the reason the store didn't open stays in the device log.

## Review Focus

1. **An existing store must open as before, with its visits and metadata unchanged.** Pinned by Task 1's `defaultLocationIsSwiftDataDefault` and `opensExistingStoreAndKeepsVisits`, and checked end to end in Task 5, Step 3: a `main` build's store, with a visit added by `sqlite3`, opened by this branch's build, with `Z_METADATA` unchanged.
2. **A store written before 1.3.0 (three fields) must still open, with its visits.** Pinned by Task 1's `opensThreeFieldStore`.
3. **A store that can't be opened must be left byte for byte as it was, its `-wal` too.** (Changed after review: a failed migration can rewrite the `-shm` header, which is harmless, since SQLite rebuilds the `-shm` from the store and its WAL.) Pinned by Task 1's `unreadableStoreIsLeftAlone` and Task 2's `failedOpenLeavesStoreAlone`, and checked in Task 5, Step 4 on a simulator.
4. **A second confirmation (two iPad windows) must not move a store that is open.** Pinned by Task 2's `startNewDoesNothingWhileOpen`.
5. **A move that fails part-way, or a backup folder that already exists, must not split a store from its WAL or overwrite an earlier backup.** Pinned by Task 1's `failedMovePutsFilesBack` and `neverReusesBackupFolder`.

---

### Task 1: `LogbookStore` opens the store at a URL and moves it aside, never deleting it

**Files:**
- Create: `InspiRail/Models/LogbookStore.swift`
- Test: `InspiRailTests/LogbookStoreTests.swift`

**Interfaces:**
- Consumes: `VisitedStation` (unchanged).
- Produces, all main-actor isolated by the target's default:
  - `struct LogbookStore { init(url: URL, fileManager: FileManager = .default) }`
  - `static let schema: Schema` = `Schema([VisitedStation.self])`
  - `static var defaultURL: URL` = `URL.applicationSupportDirectory.appending(path: "default.store")`
  - `let url: URL`
  - `var configuration: ModelConfiguration`, built with `ModelConfiguration(schema: Self.schema, url: url)`
  - `func open() throws -> ModelContainer`: creates the folder holding `url` if it's missing, then `ModelContainer(for: Self.schema, configurations: [configuration])`. It rethrows every error and touches no file on failure.
  - `var backupsFolder: URL` = `url.deletingLastPathComponent().appending(path: "Logbook Backups")`
  - `@discardableResult func moveAside(date: Date = .now) throws -> URL?`: moves whichever of `url`, `url-wal` and `url-shm` exist into a new folder `backupsFolder/<stamp>` (see Decision 3), and returns that folder. With none of the files there, it creates nothing and returns `nil`. It creates the dated folder with `withIntermediateDirectories: false` under an existing `backupsFolder`, so an existing folder throws before anything moves. If a move throws, it moves the files already moved back, then rethrows.

- [x] **Step 1: Write the failing tests.** A `@MainActor` suite `LogbookStoreTests` (a `final class`, so `deinit` removes its directory). `init()` makes `dir = temporaryDirectory/LogbookStoreTests-<UUID>` and `storeURL = dir/default.store`, and the fixture checks `!dir.path.hasPrefix(URL.applicationSupportDirectory.path)`. Helpers: `addVisit(code:name:to:)` inserts and saves through a container's `mainContext`, and `visits(in:)` fetches `[VisitedStation]` sorted by code. Tests:
  - `opensExistingStoreAndKeepsVisits`: open, add `UT`/"Utrecht Centraal" dated `Date(timeIntervalSince1970: 1_780_000_000)`, drop the container, open a new `LogbookStore(url: storeURL)`. Expect one visit with the same code, name and date.
  - `opensThreeFieldStore`: a test-only `enum ThreeFieldLogbook { @Model final class VisitedStation { @Attribute(.unique) var stationCode: String; var stationName: String; var dateVisited: Date } }` writes a store at `storeURL` with `ASD`/"Amsterdam Centraal". Then `LogbookStore(url: storeURL).open()`. Expect that visit, with `notes == nil` and `rating == nil`.
  - `unreadableStoreIsLeftAlone`: write 4096 bytes of `0x5A` to `storeURL` and `Data("wal".utf8)` to `default.store-wal`. Expect `open()` to throw, both files byte for byte unchanged, and the directory listing unchanged apart from the folder's own entries.
  - `moveAsideKeepsOldFilesAndOpensEmptyStore`: open, add a visit, drop the container. Record the bytes of each store file that exists (at least `default.store`). `moveAside(date: Date(timeIntervalSince1970: 1_793_536_532))`. Expect the returned folder `== dir/Logbook Backups/2026-11-01T12-35-32Z`, each recorded file in it with the same bytes, and none of the three names left in `dir`. Then `open()` has 0 visits, accepts a new visit and saves. `LogbookStore(url: backup/default.store).open()` still has the old visit.
  - `moveAsideWithNoStoreReturnsNil`: on an empty `dir`, expect `nil` and no `Logbook Backups` folder.
  - `neverReusesBackupFolder`: write garbage to `storeURL`, create `dir/Logbook Backups/2026-11-01T12-35-32Z/default.store` holding `Data("earlier".utf8)`, then call `moveAside` with that date. Expect it to throw, the earlier backup unchanged, and `storeURL` still holding the garbage.
  - `failedMovePutsFilesBack`: create all three files with distinct bytes. Use a `FileManager` subclass whose `moveItem(at:to:)` throws on its second call and otherwise calls `super`. Expect `moveAside` to throw, all three files back at their original paths with their bytes, and no store file in the backup folder.
  - `defaultLocationIsSwiftDataDefault`: `LogbookStore(url: LogbookStore.defaultURL).configuration.url == ModelConfiguration(schema: LogbookStore.schema, isStoredInMemoryOnly: false).url`, and `LogbookStore.defaultURL.lastPathComponent == "default.store"`. This opens nothing.

- [x] **Step 2: Run the tests to verify they fail.** Run the test command with `-only-testing:InspiRailTests/LogbookStoreTests`. Expected: a build failure, `cannot find 'LogbookStore' in scope`.
- [x] **Step 3: Implement `LogbookStore` in `InspiRail/Models/LogbookStore.swift`** as in Interfaces. The stamp uses a `DateFormatter` with `en_US_POSIX`, `TimeZone(identifier: "UTC")` and `yyyy-MM-dd'T'HH-mm-ss'Z'`. The header comment says it never deletes a file.
- [x] **Step 4: Run the tests to verify they pass.** Same command. Expected: 8 passed. (Added during execution: since these tests first failed only at compile time, a mutant `LogbookStore` that skips the put-back and deletes the store on a failed open was run against `failedMovePutsFilesBack()` and `unreadableStoreIsLeftAlone()`; both failed, then the file was restored.)
- [x] **Step 5: Typecheck.** Expected: 0 errors, 13 warnings.
- [x] **Step 6: Commit** `feat: add a logbook store type that opens or moves aside the store, never deleting it (#17)`

### Task 2: `Logbook` holds the open container or the error, behind Try Again and Start a New Logbook

**Files:**
- Create: `InspiRail/Models/Logbook.swift`
- Test: `InspiRailTests/LogbookTests.swift`

**Interfaces:**
- Consumes: `LogbookStore` from Task 1: `init(url:)`, `open()`, `moveAside(date:)`, `backupsFolder`.
- Produces:
  - `@Observable final class Logbook { init(store: LogbookStore) }`. `init` opens the store once.
  - `enum Status { case open(ModelContainer); case failed(any Error) }`, nested in `Logbook`
  - `private(set) var status: Status`
  - `func tryAgain()`: when `.failed`, opens again and sets `.open` or `.failed` with the new error. When `.open`, does nothing.
  - `func startNew(date: Date = .now)`: when `.failed`, `moveAside(date:)` then `open()`. Either error sets `.failed`. When `.open`, does nothing.

- [x] **Step 1: Write the failing tests.** A `@MainActor` suite `LogbookTests`, with a temporary-directory fixture like Task 1's. Tests:
  - `opensOnCreation`: an empty `dir`. Expect `.open`.
  - `failedOpenLeavesStoreAlone`: garbage at `storeURL`. Expect `.failed`, and the file unchanged.
  - `tryAgainOpensOnceTheStoreCanBeOpened`: garbage, then `tryAgain()`. Expect `.failed` and the garbage unchanged. Move the garbage file out of `dir` (standing in for the cause going away), then `tryAgain()`. Expect `.open`.
  - `startNewMovesAsideAndOpensEmptyLogbook`: garbage, then `startNew(date:)`. Expect `.open` with 0 visits, and the garbage bytes in `backupsFolder/<stamp>/default.store`.
  - `startNewDoesNothingWhileOpen`: open and add a visit. `startNew()`, then `tryAgain()`. Expect the same container instance (`===`), the visit still there, and no `backupsFolder`.

- [x] **Step 2: Run the tests to verify they fail.** `-only-testing:InspiRailTests/LogbookTests`. Expected: `cannot find 'Logbook' in scope`.
- [x] **Step 3: Implement `Logbook` in `InspiRail/Models/Logbook.swift`.** The store is a `let`, which Observation never tracks (changed during execution: it was to be `@ObservationIgnored`, which a `let` doesn't need). Logging is as in Decision 7: `Logger(subsystem: AppConfiguration.subsystem, category: "database")`, `.error` with the error on a failed open or move, and `.notice` with the backup folder's name after a move.
- [x] **Step 4: Run the tests to verify they pass.** Expected: 5 passed. (Added during execution: a mutant without `startNew`'s guard fails `startNewDoesNothingWhileOpen()`.)
- [x] **Step 5: Typecheck.** Expected: 0 errors, 13 warnings.
- [x] **Step 6: Commit** `feat: add the app-wide logbook state behind Try Again and Start a New Logbook (#17)`

### Task 3: Open the logbook once for every window, and show the error screen instead of erasing it

**Files:**
- Create: `InspiRail/Pages/LogbookUnavailableView.swift`
- Modify: `InspiRail/InspiRailApp.swift:26-117`: delete `createModelContainer()` and its `OSLog` import, and add the `Logbook` and a root view.

**Interfaces:**
- Consumes: `Logbook`, `Logbook.Status`, `tryAgain()`, `startNew(date:)` from Task 2. `LogbookStore(url:)` and `LogbookStore.defaultURL` from Task 1.
- Produces: `struct LogbookUnavailableView: View { let error: any Error; let tryAgain: () -> Void; let startNew: () -> Void }`

- [x] **Step 1: The error screen.** `LogbookUnavailableView` is a `ContentUnavailableView` with `Label("Can't Open Your Logbook", systemImage: "book.closed")`, and a description holding the text from Decision 2 and, below it, `error.localizedDescription` in `.footnote` and `.secondary`, selectable. Its actions are "Try Again" (`.borderedProminent`) and "Start a New Logbook" (destructive role), which presents the alert from Decision 2. The alert's destructive button calls `startNew`.
- [x] **Step 2: The App.** Add `@State private var logbook: Logbook?`. In `init()`, after the test-host guard and the configuration log, it is set to `Logbook(store: LogbookStore(url: LogbookStore.defaultURL))`. The doc comment says it is opened once so that every window shares one container (#17). The `WindowGroup` content is `if isHostingUnitTests { Color.clear … inMemory: true }` as now, `else if let logbook { LogbookRootView(logbook: logbook) }`. A `private struct LogbookRootView: View` in the same file switches on `logbook.status`: `.open(let container)` gives `MainTabView().modelContainer(container)`, and `.failed(let error)` gives `LogbookUnavailableView`, with `logbook.tryAgain` and `{ logbook.startNew() }`.
- [x] **Step 3: Check for leftovers.** Run `git grep -nE "createModelContainer|shouldAttemptReset|isMigrationError|removeItem|isStoredInMemoryOnly: true|try!" -- InspiRail`. Expected: no hits.
- [x] **Step 4: Typecheck.** Expected: 0 errors, 13 warnings.
- [x] **Step 5: Run the default test plan.** Expected: `** TEST SUCCEEDED **`, 30 tests passed (17 + 8 + 5), including the 3 `TestHostTests`.
- [x] **Step 6: Commit** `fix: open the logbook once for all windows and show an error instead of erasing it (#17)`

### Task 4: Delete the dead migration plan, and say on the model when versioned schemas are needed

**Files:**
- Delete: `InspiRail/NetworkEngine/VisitedStationMigration.swift`
- Modify: `InspiRail/Models/VisitedStation.swift:10-23`: a doc comment on the class with the history and the rule from Decision 4. The comment above `_isFavorite` says the three unused fields are stored, so removing them changes the schema.
- Modify: `README.md:36-37`: `Models/` reads "SwiftData & Codable data models, logbook store", and `NetworkEngine/` reads "Network error type".

**Interfaces:**
- Consumes: nothing. Nothing references `VisitedStationMigrationPlan`, `VisitedStationSchemaV1`, `VisitedStationSchemaV2` or `createWithMigration()`.
- Produces: nothing.

- [x] **Step 1: Delete the file, and make the two edits.**
- [x] **Step 2: Check the stored schema is unchanged.** Run the typecheck with `-Xfrontend -dump-macro-expansions`, then `grep -E 'PropertyMetadata\(name: .*\\VisitedStation\.' | sort -u`, on this branch and on `main`. Expected: the same 6 lines on both.
- [x] **Step 3: Check for leftovers.** Run `git grep -nE "VisitedStationMigration|VisitedStationSchemaV|createWithMigration|SchemaMigrationPlan" -- . ':!docs/archive' ':!docs/superpowers'`. Expected: only `CHANGELOG.md`'s 1.3.0 entry, and the new comment on `VisitedStation`, which names `SchemaMigrationPlan` (changed during execution: the pattern matches that comment too).
- [x] **Step 4: Typecheck, and run the default test plan.** Expected: 0 errors, 13 warnings. 30 tests passed.
- [x] **Step 5: Commit** `refactor: delete the unused migration plan, which matched no stored schema (#17)`

### Task 5: Record the fix in the changelog, and check it on a simulator

**Files:**
- Modify: `CHANGELOG.md`, `[Unreleased]`

- [x] **Step 1: `CHANGELOG.md`.** Under `### Fixed`, append:
  - The app no longer erases the logbook when it can't open it, and no longer carries on with a temporary logbook whose visits are lost when the app quits. It shows what went wrong, with Try Again and Start a New Logbook. Starting a new logbook asks first, then moves the old one into a backup folder on the device instead of deleting it.
  - On iPad, all windows share one logbook, so a visit marked in one window shows in the others.

  Under `### Removed`, append:
  - The unused SwiftData migration plan (`VisitedStationMigration`), which described schemas the store never had.

- [x] **Step 2: Builds.** Build a Debug app of `main` (9752135, in a scratch worktree) and of this branch, each with its own `-derivedDataPath` outside the repo, for `generic/platform=iOS Simulator`. Create a throwaway iPhone 17 simulator on iOS 26.3. All launches use the offline review stub and a dummy key, as in `docs/superpowers/plans/2026-10-28-remove-dead-key-path.md`, Task 2, Step 3: `SIMCTL_CHILD_NS_API_KEY=dummy-key`, `SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=<stub>/ReviewStub.dylib`, `SIMCTL_CHILD_REVIEW_STUB_PAYLOAD=<stub>/stations.json`. The stub is a local review tool outside the repo, so these steps run only where it is installed. Never use a real key.
- [x] **Step 3: Upgrade.** Install the `main` build and launch it once, so it creates `default.store`, then stop it. With the app stopped, add one visit with `sqlite3` (a `ZVISITEDSTATION` row, with `Z_PRIMARYKEY.Z_MAX` raised to match), and record a hash of `Z_METADATA`. Install this branch's build over it and launch it, streaming `subsystem == "annisu.inspirail" OR subsystem == "review.stub"`. Take a screenshot.
  Expected: the onboarding station list, no `database` error line, and, after stopping the app, the visit still in the store and the same `Z_METADATA` hash.
  (Added during execution: `lsof` on a relaunch shows the branch's app holding `default.store` open, and a throwaway UI test (Step 5's worktree) shows the visit in the Logbook tab. The simulator moves the app's data container on each install, so its path is looked up again after every install.)
- [x] **Step 4: Unreadable store.** With the app stopped, overwrite `default.store` with garbage bytes, and hash it with its `-wal` and `-shm`. Launch, and take a screenshot.
  Expected: the error screen, one `database` error line, and, after stopping the app, the same hashes.
- [x] **Step 5: Start a New Logbook.** In a scratch worktree of this branch, add a throwaway XCUITest that launches the app with `-homeStationCode UT` and the stub's environment, taps "Start a New Logbook" and then the alert's "Start New Logbook", and checks that the tabs appear and that the Logbook tab has no visits. Run only that test on the same simulator, with the garbage store from Step 4 in place.
  (Changed during execution: the home station is `ASD`, not `UT`, because the Logbook leaves out the home station's own visit, which would hide the visit from Step 3. The scratch worktree also adds the UI target to the scheme's testables and to the test plan, and the test taps Try Again once before Start a New Logbook.)
  Expected: the test passes. `Logbook Backups/<stamp>/` holds `default.store` with the garbage hash, and the `-wal` and `-shm` from Step 4. A new `default.store` exists and opens with 0 visits. If UI driving isn't practical, Task 2's `startNewMovesAsideAndOpensEmptyLogbook` stands in for it, and the report says so.
- [x] **Step 6: Clean up.** Delete the simulator, the scratch worktrees and the derived data.
- [x] **Step 7: Commit** `docs: record the safe store opening in the changelog (#17)`

## Review fixes

The review of the PR found the following. Each item gives the finding, the owner's ruling and the commit.

1. **A failed open at launch stuck (Important).** The App opens the logbook in `init()`, which can run during prewarming after a restart, before the first unlock, while the store can't be read. One failure there kept the error screen up and invited Start a New Logbook on a healthy logbook. Ruling: open again when a window becomes active. `LogbookRootView` calls `tryAgain()` from `.onChange(of: scenePhase, initial: true)` when the phase is `.active`. `tryAgain()` still does nothing while the logbook is open, so the one container stays, and the test-host path is unchanged. New test `tryAgainOpensTheStoreOnceItCanBeRead`: a store made unreadable with `chmod 000` fails to open, then opens with its visit once it is readable again. A `tryAgain` that does nothing fails it. 0ee1cd9
2. **The raw error text told the user nothing.** It read "SwiftData.SwiftDataError error 1" for every cause. Ruling: drop it, and the state that only fed it. `Logbook.Status.failed` no longer carries the error, and `LogbookUnavailableView` no longer takes it. The error SwiftData throws carries nothing more (empty `userInfo`, no underlying errors), so the log line stays as it was. fa921b5
3. **`neverReusesBackupFolder` didn't pin "never reuse".** Its folder held a `default.store`, so the move threw on that name even if the folder was reused. Ruling: use a folder with no store file in it. It now holds only an unrelated file, and the test expects a throw, the folder unchanged, and the store and its WAL in place. A mutant that creates the dated folder with `withIntermediateDirectories: true` fails it. 1719d0e
4. **A failed put-back was silent** (`try?`). Ruling: log it with the file name, and keep throwing the move's error. New test `failedPutBackThrowsTheMoveError`, and the log line was seen on a simulator. 123dd1f
5. **Wrong text once the move worked but a new store couldn't be opened.** The screen still said the logbook with the visits couldn't be opened, but the visits were now in the backup. Ruling: track that state and say so in plain words, with no new buttons. `Status.failed(movedAside:)`, which Try Again keeps, and the text in Decision 2. New test `startNewThatCantOpenANewStoreSaysTheOldOneIsInABackup`. b8018b7
6. **Docs.** `LogbookStore.open()` and Review Focus 3 now say a failed open leaves the store and its WAL as they are: a failed migration can rewrite the `-shm` header, which is harmless. The README's Pages list names the error screen. The changelog entry changed with items 1 and 2. 7ab2cc2

Not changed, by ruling:

- Try Again shows nothing new when it fails again. Left for a follow-up issue.
- The `-shm` header rewrite itself.

Checked after the fixes: the typecheck prints 0 errors and the same 13 warnings as `main`, and the default test plan passes 33 tests. On a throwaway simulator with the offline stub: a garbage store shows the error screen without the error text and is left byte for byte as it was, with its `-wal` and `-shm`, after three failed opens (launch, first activation, and a trip to Settings and back). With the app still running, a valid store with one visit put in place of the garbage opens when the app comes back from Settings, without Try Again, and the visit shows in the Logbook tab. A store written by 1.4.1 (96af344), with a visit added by `sqlite3`, opens in this branch's build with the visit in the Logbook tab and `Z_METADATA` unchanged.
