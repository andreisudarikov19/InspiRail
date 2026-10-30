# Remove the dead key path (#14) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The NS API key comes from exactly two places, the Keychain and (in Debug builds) the `NS_API_KEY` environment variable; a fresh clone builds; and Debug launches stop running stale diagnostics.

**Architecture:** Key resolution moves out of `BackendAPI.getAPIKey()` into a small `nonisolated` `APIKeyProvider` that takes its Keychain and environment as parameters, so it can be tested against throwaway Keychain services, as `KeychainMigrationTests` already does. The launch check (`verifyBackendConnection`) and the two diagnostics actors are deleted. `Secrets.xcconfig` leaves the Xcode project entirely.

**Tech Stack:** Swift 5 language mode with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, SwiftUI, Swift Testing, Security framework, `xcodebuild`.

**Spec:** issue #14, https://github.com/andreisudarikov19/InspiRail/issues/14

## Global Constraints

- The key has two sources, in this order: in Debug builds a non-empty `NS_API_KEY` environment variable, then the Keychain (`KeychainManager.shared`). Release builds never read the environment.
- **Decision taken here (the issue left it open):** in Debug builds the environment variable wins over a stored key without replacing it, and is saved to the Keychain only when no key is stored (changed after review), so a single launch with the variable also primes later launches. A whitespace-only value counts as unset.
- No log line contains any character of the key.
- New types that actors use are declared `nonisolated`, so the build gains no concurrency warnings. The clean build had 41 `warning:` lines before this change; it must not have more after.
- Tests use Swift Testing, with a throwaway Keychain service per test and cleanup in `deinit`, like `InspiRailTests/KeychainMigrationTests.swift`.
- Commit subjects end with `(#14)`.

## Review Focus

1. A Release build run from Xcode with `NS_API_KEY` in the scheme's environment must ignore it. `BackendAPI` passes `allowsEnvironmentOverride` from `#if DEBUG`; Task 1 tests the provider with `false`, and the wiring is checked in review.
2. A blank or whitespace-only `NS_API_KEY` (an empty field in the scheme editor) must count as unset, not as a key. Covered by a test in Task 1.
3. A user upgrading from 1.4.1, whose key is still under the old Keychain service, must still be found. The existing `KeychainMigrationTests` must keep passing; Task 1 runs them.
4. A developer who still has a local `Secrets.xcconfig` must not be affected. Nothing reads the file, and `.gitignore` keeps ignoring it (Task 3 leaves that line).
5. A Keychain read error other than "not found" (for example, a locked device) keeps today's outcome, `NetworkError.unauthorized`, and never falls back to the environment in Release. Separate error cases come in #20. This is checked in review.

---

### Task 1: Resolve the key from the Debug environment and the Keychain only

**Files:**
- Create: `InspiRail/APIKeyProvider.swift`
- Modify: `InspiRail/BackendAPI.swift`: the key and logging block in `request(url:as:retryCount:)` (`:111-134`), the 401 message (`:166-172`), and `getAPIKey()` (`:286-344`)
- Modify: `InspiRailTests/KeychainMigrationTests.swift:118`: make `removeKeychainItems(service:)` internal (drop `private`) so both suites share it
- Test: create `InspiRailTests/APIKeyProviderTests.swift`

**Interfaces:**
- Consumes: `KeychainManager(service:legacyService:)`, `saveAPIKey(_:)`, `getAPIKey() throws -> String` (throws `KeychainError.notFound` when empty), `NetworkError.unauthorized`
- Produces:
  ```swift
  nonisolated struct APIKeyProvider: Sendable {
      init(keychain: KeychainManager, environment: [String: String], allowsEnvironmentOverride: Bool)
      /// The key to send with a request. Throws `NetworkError.unauthorized` when there is none.
      func currentKey() async throws -> String
  }
  ```

- [x] **Step 1: Write the failing tests** in `InspiRailTests/APIKeyProviderTests.swift`: `@Suite("API key sources") final class APIKeyProviderTests`, with a `KeychainManager(service: "test.\(UUID().uuidString).provider")` per instance, removed in `deinit` with `removeKeychainItems(service:)`.
  - `storedKeyIsUsed`: Keychain holds `"stored"`, empty environment → `currentKey() == "stored"`.
  - `debugEnvironmentWinsAndKeepsStoredKey` (changed after review): Keychain holds `"stored"`, environment `["NS_API_KEY": "fresh"]`, override allowed → `currentKey() == "fresh"`, and afterwards `keychain.getAPIKey()` still returns `"stored"`.
  - `environmentPrimesEmptyKeychain`: empty Keychain, environment `"fresh"`, override allowed → `"fresh"`, and the Keychain then holds `"fresh"`.
  - `releaseIgnoresEnvironment`: Keychain holds `"stored"`, environment `"fresh"`, override **not** allowed → `"stored"`, and the Keychain still holds `"stored"`.
  - `blankEnvironmentIsUnset`: Keychain holds `"stored"`, environment `"   "`, override allowed → `"stored"`.
  - `noKeyThrowsUnauthorized`: empty Keychain, empty environment → `let error = await #expect(throws: NetworkError.self) { try await provider.currentKey() }`, then `guard case .unauthorized? = error else { Issue.record("expected .unauthorized"); return }`.

- [x] **Step 2: Run the tests to verify they fail**

  Run: `xcodebuild test -project InspiRail.xcodeproj -scheme InspiRail -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:InspiRailTests`
  Expected: build failure, "cannot find 'APIKeyProvider' in scope".

- [x] **Step 3: Implement `APIKeyProvider` in `InspiRail/APIKeyProvider.swift`.** Trim the environment value with `.whitespacesAndNewlines` before the emptiness check. Save to the Keychain only when no key is stored (changed after review). If that save fails, log the failure without the key and still return the environment key. Any Keychain read error ends in `NetworkError.unauthorized` when the environment doesn't apply. Log which source was used ("Keychain" or "NS_API_KEY environment variable"), never the value. When there is no key, log one error line, "No API key: enter one in Settings", before throwing.

- [x] **Step 4: Wire it into `BackendAPI`**
  - Add `private let keyProvider: APIKeyProvider`, initialised in `init()` with `keychain: .shared`, `environment: ProcessInfo.processInfo.environment`, and `allowsEnvironmentOverride:` `true` under `#if DEBUG` and `false` otherwise.
  - Replace the `getAPIKey()` call with `try await keyProvider.currentKey()`, and delete `getAPIKey()`: the Info.plist step, its comments and the four "No API key found" lines, including the `API_SECURITY_SETUP.md` pointer.
  - Delete the `#if DEBUG` "API Key preview" block (`:127-133`), and keep the "Has API Key header" line.
  - Change the 401 hint to `"   - The API key is missing, invalid or expired: check it in Settings"`.

- [x] **Step 5: Run the tests to verify they pass**

  Run: the command from Step 2.
  Expected: `** TEST SUCCEEDED **`, with the 6 new tests and the 7 `KeychainMigrationTests` passing.

- [x] **Step 6: Check that no key logging is left**

  Run: `grep -rnE "prefix\(4\)|suffix\(4\)|API Key preview|Info.plist|API_SECURITY_SETUP" InspiRail/BackendAPI.swift InspiRail/APIKeyProvider.swift`
  Expected: no output.

- [x] **Step 7: Commit** `fix: read the API key from the Keychain and the Debug environment only (#14)`

### Task 2: Remove the Debug launch diagnostics

**Files:**
- Modify: `InspiRail/InspiRailApp.swift`: delete the `#if DEBUG … verifyBackendConnection() … #endif` call in `.task` (`:26-29`) and the whole `verifyBackendConnection()` function (`:116-209`, with its `#if DEBUG` wrapper)
- Delete: `InspiRail/NetworkEngine/APIKeySetupHelper.swift`, `InspiRail/NetworkEngine/APIKeyDiagnostics.swift`

**Interfaces:**
- Consumes: nothing new. The `.task` keeps only `await AnalyticsManager.shared.track(.appLaunched)` (analytics is removed in #16).
- Produces: nothing. No other file uses the deleted types. `BackendHealthMonitor.DiagnosticReport` is a separate nested type.

- [x] **Step 1: Delete the call, the function and the two files.**
- [x] **Step 2: Build and run the unit tests**

  Run: the test command from Task 1, Step 2.
  Expected: `** TEST SUCCEEDED **`. In the build log, the `warning:` count is lower than 41.

- [x] **Step 3: Launch check with the offline review stub** (it answers the NS gateway with a synthetic station list and never reaches the network). The stub is a local review tool kept outside the repo: `.superpowers/` is excluded from git, so this step runs only where the tool is installed.

  Run, on a booted "iPhone 17" simulator after installing the Debug build:
  `SIMCTL_CHILD_NS_API_KEY=dummy-key SIMCTL_CHILD_DYLD_INSERT_LIBRARIES=$PWD/.superpowers/scratch/review/runtime/stub/ReviewStub.dylib xcrun simctl launch --console-pty booted annisu.rnsapp`, and stream `log stream --predicate 'subsystem == "annisu.inspirail" OR subsystem == "review.stub"'` for 20 s.
  Expected: exactly one `REVIEWSTUB request` at launch (before this change there were two); no line containing `Info.plist`, `Secrets.xcconfig` or `preview`; one line naming the environment variable as the key source.

- [x] **Step 4: Commit** `fix: stop running key diagnostics and a second station download at Debug launch (#14)`

### Task 3: Take Secrets.xcconfig out of the project, and update the docs

**Files:**
- Modify: `InspiRail.xcodeproj/project.pbxproj`: delete the 8 `baseConfigurationReference = EB85ECF72F2F5866003C9DB9 /* Secrets.xcconfig */;` lines, the `PBXFileReference` line for `Secrets.xcconfig` (`:32`) and its entry in the root group's `children` (`:82`)
- Delete: `Secrets.xcconfig.template`
- Modify: `README.md`, the "API key handling" section (`:26-32`) and the `NetworkEngine/` line of the layout
- Modify: `CHANGELOG.md`, `[Unreleased]`

- [x] **Step 1: Edit the project file and delete the template.** Keep the `Secrets.xcconfig` line in `.gitignore`.

- [x] **Step 2: Check that a fresh clone builds**

  Run: `git worktree add --detach "$TMP/wt" HEAD && xcodebuild -project "$TMP/wt/InspiRail.xcodeproj" -scheme InspiRail -destination 'generic/platform=iOS Simulator' -derivedDataPath "$TMP/dd" build CODE_SIGNING_ALLOWED=NO`, with `TMP` in the scratch directory, then remove the worktree.
  Expected: `** BUILD SUCCEEDED **`, and no "base configuration" message. Before this change the same command fails with exit 65.

- [x] **Step 3: Rewrite the README's "API key handling".** The key lives only in the Keychain.
  - **End users:** paste the key in Settings.
  - **Developers (Debug builds only):** set `NS_API_KEY` either by launching with `SIMCTL_CHILD_NS_API_KEY=… xcrun simctl launch <device> annisu.rnsapp`, or on a *duplicate* of the scheme with "Shared" unticked, so the value stays in the untracked `xcuserdata`. In Debug builds the variable wins over a stored key, and is saved to the Keychain only when no key is stored (changed after review).
  - No key is ever compiled into the app, and the project has no `Secrets.xcconfig`; a leftover local copy is ignored.
  - In the layout, `NetworkEngine/` becomes "HTTP plumbing and errors".

- [x] **Step 4: Add to `CHANGELOG.md` `[Unreleased]`**
  - Changed: in Debug builds, `NS_API_KEY` from the environment now takes precedence over a key stored in the Keychain.
  - Removed: the Info.plist key lookup, the Debug launch diagnostics (`APIKeySetupHelper`, `APIKeyDiagnostics`), `Secrets.xcconfig` as the project's base configuration, and `Secrets.xcconfig.template`.
  - Fixed: a fresh clone builds without creating `Secrets.xcconfig`; Debug launches download the station list once instead of twice; Debug builds no longer log part of the API key.

- [x] **Step 5: Check that nothing outside the archive still points at the old path**

  Run: `git grep -nE "Secrets\.xcconfig|APIKeySetupHelper|APIKeyDiagnostics|verifyBackendConnection|API_SECURITY_SETUP" -- . ':!docs/archive' ':!CHANGELOG.md' ':!docs/superpowers'`
  Expected: only `.gitignore` and the README's sentence saying the project has no `Secrets.xcconfig`.

- [x] **Step 6: Commit** `build: remove Secrets.xcconfig from the project so a fresh clone builds (#14)`

After the merge, the owner deletes the local `Secrets.xcconfig`.
