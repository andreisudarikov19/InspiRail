# Hermetic test runs (#15) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `xcodebuild test` makes no NS API requests and never opens the simulator's SwiftData store, the template UI tests are gone, and on an unsigned test host the Keychain tests are skipped with a reason instead of failing.

**Architecture:** The default test plan sets `INSPIRAIL_UNIT_TEST_HOST=1`. `AppConfiguration.isHostingUnitTests(environment:)` reads it, and `InspiRailApp` then skips its startup work and shows an empty scene backed by an in-memory store. The Keychain tests carry a Swift Testing condition trait, `.requiresKeychain`, that probes the Keychain once and skips only on `errSecMissingEntitlement`. The UI test target stays in the project, with one comment-only source file, but leaves the default test plan.

**Tech Stack:** Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (app target only; the test target is nonisolated by default), SwiftUI, SwiftData, Swift Testing, Security framework, `xcodebuild`, `xcrun simctl`.

**Spec:** issue #15, https://github.com/andreisudarikov19/InspiRail/issues/15 (its line numbers refer to 8c02931; #14 has since removed the Debug launch check from `InspiRailApp.swift`)

## Global Constraints

- A launch without `INSPIRAIL_UNIT_TEST_HOST=1` in its environment behaves exactly as today. Nothing changes for users.
- Out of scope, and left as they are: the store-wipe-on-error path in `createModelContainer()` (#17), which the test host simply stops calling; other dead code (#16); real UI flows and coverage (#34); CI (#32).
- Keychain tests keep running against the real Keychain wherever it works.
- New app code called from the test target is `nonisolated`. A clean build of `main` (7a9c0bf) with `build-for-testing` prints 34 `warning:` lines, 22 unique; the branch must not print more.
- Tests use Swift Testing. Commit subjects end with `(#15)`.

## Decisions taken here (the issue left them open)

1. **Test host detection: a test plan variable, `INSPIRAIL_UNIT_TEST_HOST=1`, not `XCTestConfigurationFilePath`.** Measured on Xcode 26.3: the unit-test host's environment has `XCTestConfigurationFilePath` set to an empty string (the configuration now travels through `XCTestSessionIdentifier`), so that variable is a leftover of XCTest's internals that only a presence check still detects. A variable in `InspiRail.xctestplan` reaches the unit-test host and does not reach the app a UI test launches, which gets only `XCODE_SCHEME_NAME` and `XCODE_TEST_PLAN_NAME`. The plan variable is named for what it means and lives in the repo. A test in the unit-test target fails if a plan ever runs the tests without it.
2. **The test host shows `Color.clear` with an in-memory `VisitedStation` store** and runs no startup work: no `logConfiguration()`, no analytics launch event, no `createModelContainer()`, no `MainTabView` (whose Onboarding or Discover `.task` loads the station list). The check isn't wrapped in `#if DEBUG`: an iOS app's environment can't be set outside Xcode, `simctl` or a test runner, and the test action may run any configuration.
3. **UI tests: delete both template files, take the target out of the default test plan, keep the target with one comment-only Swift file.** Measured: the target still builds with no folder at all, but git can't keep an empty folder, so a fresh clone's project would point at a folder that doesn't exist; a `.gitkeep` would be copied into the test bundle as a resource. A comment-only `InspiRailUITests.swift` keeps the folder, builds a valid empty bundle, and says why the target has no tests (#34). The target's `TestableReference` also leaves the shared scheme: measured, `build-for-testing` builds whatever the scheme's `<Testables>` lists, so with the target only out of the plan every test run would still build it. When #34 adds real flows, the target goes back into both.
4. **Unsigned Keychain tests: skip with `.requiresKeychain`.** Measured on the iOS 26.3 simulator: with `CODE_SIGNING_ALLOWED=NO`, `SecItemCopyMatching`, `SecItemAdd` and `SecItemDelete` all return `errSecMissingEntitlement` (-34018), and 12 of the 14 unit tests fail; signed, a lookup of a missing item returns `errSecItemNotFound` (-25300). So one read-only lookup decides, and only -34018 skips. `noKeyThrowsUnauthorized` needs the trait too: unsigned it passes only through the read-error path, not the empty-Keychain path it names. `reportsEnvironmentKeyInUse` never touches the Keychain and keeps running.

## Review Focus

1. A normal launch (Xcode Run, `simctl launch`, TestFlight) must never show the empty scene. Only the exact value `1` triggers it; Task 1 tests an empty environment and the environment a UI-test launch gets, and checks that a plain `simctl launch` still logs its configuration and makes its station request.
2. The app a UI test launches must stay the full app, so #34 tests the real thing. The plan variable doesn't reach it (measured above). #34 must not copy the runner's whole environment into `launchEnvironment`. Checked in review.
3. A Keychain error other than a missing entitlement (for example `errSecInteractionNotAllowed`) must still fail the Keychain tests, not skip them. The trait compares with `errSecMissingEntitlement` only. Checked in review.
4. A signed run must still run every Keychain test. Task 2, Step 5 expects 0 skipped.
5. The developer's own visits on the simulator: the unit-test host must not open `default.store`. Task 4, Step 3 deletes the store before a test run and expects it still absent after.

---

### Task 1: Show an empty scene when the app hosts the unit tests

**Files:**
- Modify: `InspiRail/AppConfiguration.swift`: a new `// MARK: - Test host` section after `// MARK: - App Info`
- Modify: `InspiRail/InspiRailApp.swift:13-30`: the stored flag, `init()` and `body`
- Modify: `InspiRail.xctestplan`: `defaultOptions.environmentVariableEntries`
- Test: create `InspiRailTests/TestHostTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum AppConfiguration {   // added to the existing enum
      /// Set to "1" by InspiRail.xctestplan for the process that hosts the unit tests.
      nonisolated static let unitTestHostVariable = "INSPIRAIL_UNIT_TEST_HOST"
      nonisolated static func isHostingUnitTests(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool
  }
  ```

- [x] **Step 1: Write the failing tests** in `InspiRailTests/TestHostTests.swift`, `@Suite("Unit-test host") struct TestHostTests`:
  - `currentProcessIsTheTestHost`, "This test run's host knows it is hosting the unit tests": `#expect(AppConfiguration.isHostingUnitTests())`.
  - `normalLaunchIsNotTheTestHost`, "A normal launch, or the app a UI test launches, is not the test host": `#expect(!AppConfiguration.isHostingUnitTests(environment: [:]))` and `#expect(!AppConfiguration.isHostingUnitTests(environment: ["XCODE_SCHEME_NAME": "InspiRail", "XCODE_TEST_PLAN_NAME": "InspiRail"]))`.
  - `onlyOneMarksTheTestHost`, "Only the value 1 marks the test host": `["INSPIRAIL_UNIT_TEST_HOST": "1"]` → `true`; `"0"` and `""` → `false`.

- [x] **Step 2: Run the tests to verify they fail**

  Run: `xcodebuild test -project InspiRail.xcodeproj -scheme InspiRail -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:InspiRailTests`
  Expected: build failure, "type 'AppConfiguration' has no member 'isHostingUnitTests'".

- [x] **Step 3: Implement `isHostingUnitTests(environment:)`** (true only when the variable equals `"1"`), and add `{ "key" : "INSPIRAIL_UNIT_TEST_HOST", "value" : "1" }` to `defaultOptions.environmentVariableEntries` in `InspiRail.xctestplan`.

- [x] **Step 4: Run the tests to verify they pass**

  Run: the command from Step 2.
  Expected: `** TEST SUCCEEDED **`, 17 tests (the 3 new ones, 7 `APIKeyProviderTests`, 7 `KeychainMigrationTests`).

- [x] **Step 5: Wire it into `InspiRailApp`**
  - `private let isHostingUnitTests = AppConfiguration.isHostingUnitTests()`, with a doc comment saying why.
  - `init()` returns before `AppConfiguration.logConfiguration()` when it is set.
  - In `WindowGroup`, when it is set: `Color.clear.modelContainer(for: VisitedStation.self, inMemory: true)`. Otherwise the current `MainTabView()` chain, unchanged. `createModelContainer()` is not touched (#17).

- [x] **Step 6: Check both launches in the app log.** On a throwaway iPhone 17 simulator whose Keychain holds a dummy key (launch once with `SIMCTL_CHILD_NS_API_KEY=dummy-key`; never a real key), stream `log stream --level debug --style compact --predicate 'subsystem == "annisu.inspirail"'` while running:
  - the command from Step 2 with `-destination id=<udid> -parallel-testing-enabled NO` (parallel testing clones the simulator, out of reach of `log stream`). Expected: no `App Configuration:` line and no `🌐 Request:` line.
  - `xcrun simctl launch <udid> annisu.rnsapp`. Expected: one `App Configuration:` line and one `🌐 Request: /nsapp-stations/v3`.

- [x] **Step 7: Commit** `fix: show an empty scene with no network work when the app hosts the unit tests (#15)`

### Task 2: Skip the Keychain tests when the test host isn't signed

**Files:**
- Create: `InspiRailTests/KeychainAvailability.swift`
- Modify: `InspiRailTests/KeychainMigrationTests.swift:14`: the suite trait
- Modify: `InspiRailTests/APIKeyProviderTests.swift`: the trait on `storedKeyIsUsed`, `debugEnvironmentWinsAndKeepsStoredKey`, `environmentPrimesEmptyKeychain`, `releaseIgnoresEnvironment`, `blankEnvironmentIsUnset` and `noKeyThrowsUnauthorized`; not on `reportsEnvironmentKeyInUse`

**Interfaces:**
- Produces:
  ```swift
  enum TestKeychain {
      /// False only when a lookup fails with errSecMissingEntitlement (-34018).
      static let isAvailable: Bool
  }
  extension Trait where Self == ConditionTrait {
      static var requiresKeychain: Self
  }
  ```

- [x] **Step 1: Run the unit tests unsigned to see them fail**

  Run: `xcodebuild test -project InspiRail.xcodeproj -scheme InspiRail -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:InspiRailTests -derivedDataPath <scratch>/dd-unsigned CODE_SIGNING_ALLOWED=NO` (a separate derived-data folder keeps the signed build intact).
  Expected: `** TEST FAILED **`, 12 tests failing with `saveFailed(-34018)` or `retrievalFailed(-34018)`.

- [x] **Step 2: Implement `TestKeychain` and `.requiresKeychain`** in `InspiRailTests/KeychainAvailability.swift`. The probe is one `SecItemCopyMatching` for a generic password under `"test.\(UUID().uuidString).probe"`, run once. The trait is `.enabled(if: TestKeychain.isAvailable, "The Keychain is unavailable: the test host isn't signed (errSecMissingEntitlement, -34018)")`.

- [x] **Step 3: Apply the trait** to the `KeychainMigrationTests` suite and to the six `APIKeyProviderTests` listed above. Update each suite's doc comment to say the tests are skipped on an unsigned host.

- [x] **Step 4: Run the unsigned command from Step 1 again**

  Expected: `** TEST SUCCEEDED **`, 13 tests skipped with the reason above, 4 passing (`reportsEnvironmentKeyInUse` and the 3 `TestHostTests`).

- [x] **Step 5: Run signed**

  Run: the command from Task 1, Step 2.
  Expected: `** TEST SUCCEEDED **`, 17 passing, 0 skipped.

- [x] **Step 6: Commit** `test: skip the Keychain tests when the test host isn't signed (#15)`

### Task 3: Remove the template UI tests and take the UI target out of the default test plan

**Files:**
- Delete: `InspiRailUITests/InspiRailUITestsLaunchTests.swift`
- Modify: `InspiRailUITests/InspiRailUITests.swift`: replace the template with a header comment saying the target is kept for real flows (#34) and isn't in `InspiRail.xctestplan`, followed by `import XCTest` and no test case
- Modify: `InspiRail.xctestplan`: remove the `InspiRailUITests` entry from `testTargets`
- Modify: `InspiRail.xcodeproj/xcshareddata/xcschemes/InspiRail.xcscheme`: remove the `InspiRailUITests` `TestableReference` from `<Testables>`

- [x] **Step 1: Make the four changes.** The target and its folder stay in the project.

- [x] **Step 2: Run the default test plan**

  Run: `xcodebuild test -project InspiRail.xcodeproj -scheme InspiRail -destination 'platform=iOS Simulator,name=iPhone 17'`
  Expected: `** TEST SUCCEEDED **`, 17 unit tests, and no `InspiRailUITests` in the output (it is neither built nor run).

- [x] **Step 3: Check that the UI target still builds**

  Run: `xcodebuild -project InspiRail.xcodeproj -target InspiRailUITests -sdk iphonesimulator -configuration Debug SYMROOT=<scratch>/sym build`
  Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 4: Commit** `test: remove the template UI tests and take the UI target out of the default test plan (#15)`

### Task 4: Document test runs, and confirm a run makes no requests

**Files:**
- Modify: `README.md`: the sentence on test folders under "Project layout", and a new "Tests" section after it
- Modify: `CHANGELOG.md`, `[Unreleased]`

- [x] **Step 1: README "Tests" section.**
  - Run the tests with ⌘U or the `xcodebuild test` command from Task 3, Step 2.
  - The unit tests run inside the app. `InspiRail.xctestplan` sets `INSPIRAIL_UNIT_TEST_HOST=1`, so the app shows an empty screen, makes no requests and doesn't open the stored visits.
  - The Keychain tests need a signed test host. With `CODE_SIGNING_ALLOWED=NO` they are skipped, and the test report, not the console, says why (changed after review).
  - `InspiRailUITests/` holds no tests yet and isn't in the test plan.

- [x] **Step 2: `CHANGELOG.md` `[Unreleased]`.**
  - Removed: the template UI tests, which launched the app nine times per test run and checked nothing. The UI test target stays, outside the default test plan.
  - Fixed: a test run no longer sends requests to the NS API or opens the simulator's stored visits.
  - Fixed: without code signing, the Keychain tests are skipped with a reason instead of failing with -34018.

- [x] **Step 3: Count request attempts during a full test run, before and after.** On the primed throwaway simulator from Task 1, Step 6: delete `Library/Application Support/default.store` (and `-wal`, `-shm`) from `xcrun simctl get_app_container <udid> annisu.rnsapp data`; stream the log as in Task 1, Step 6; run `xcodebuild test-without-building` for the whole default plan with `-destination id=<udid> -parallel-testing-enabled NO`; count `🌐 Request:` lines. Do this once on `main` and once on this branch, then delete the simulator.
  Expected: this branch makes 0 requests and logs no `App Configuration:` line, and `default.store` is still absent after the run (changed during execution: the Keychain tests log from the test host, so the check is no startup configuration line rather than no line at all). Measured while planning, `main` launched the app 10 times (1 unit-test host, 9 UI) and made 10 requests, one per launch since #14 removed the second, and re-created `default.store`.

- [x] **Step 4: Commit** `docs: describe hermetic test runs in the README and changelog (#15)`
