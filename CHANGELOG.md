# Changelog

All notable changes to InspiRail are recorded here. The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Versioning

- `MARKETING_VERSION` — public-facing version in `MAJOR.MINOR.PATCH` form.
  - `MAJOR` — incompatible data-model or API changes that require user action.
  - `MINOR` — new user-visible features or significant UX changes.
  - `PATCH` — bug fixes, internal cleanups, build-only changes.
- `CURRENT_PROJECT_VERSION` — monotonic integer build number. Incremented for every TestFlight or App Store submission, never reused.

Both live in `InspiRail.xcodeproj/project.pbxproj` on the app target and flow through to `CFBundleShortVersionString` / `CFBundleVersion` in the built `Info.plist` via Xcode's auto-generated plist.

---

## [Unreleased]

### Changed
- One name everywhere: the home-screen name, the onboarding title ("Welcome to InspiRail") and the Xcode project, targets and folders all read InspiRail. The bundle identifier stays `annisu.rnsapp`, so installed data and the App Store Connect record carry over.
- The NS API key moves to a renamed Keychain service the first time the app needs it. A key saved by an earlier version is kept, and a key removed in Settings stays removed.
- The user agent sent to the NS API reads `InspiRail/<version>`.
- In Debug builds, an `NS_API_KEY` environment variable now takes precedence over a key stored in the Keychain. It is saved to the Keychain only when no key is stored yet, so it never replaces a key saved in Settings.
- Randomize never suggests a station that is already in the logbook. Once every station but the home station is visited, Discover says "You've visited all N stations." instead of suggesting one, with Randomize disabled, until a station is free again: after Reset Logbook, in any window, or a change of home station that frees one. A station marked visited stays on the card until the next Randomize.

### Removed
- The Info.plist key lookup and the Debug launch diagnostics (`APIKeySetupHelper`, `APIKeyDiagnostics`), which advised putting the key into Info.plist.
- `Secrets.xcconfig` as the project's base configuration, and `Secrets.xcconfig.template`.
- Xcode's template UI tests, which launched the app nine times per test run and checked nothing. The UI test target stays in the project, outside the default test plan.
- Code that never ran: the background refresh (`BackgroundRefreshManager`), which was never registered or scheduled, the network monitor (`NetworkMonitor`), which nothing created, and the deprecated `NetworkManager` shim.
- Event tracking (`AnalyticsManager`) and its unused feature flags. No analytics service was connected. Release builds only wrote the events to the log, and Debug builds dropped them.
- The disruption and route models, which nothing fetched.
- Unused members of `NetworkError`, `StationsRepository`, `KeychainManager`, `VisitedStation` and `DiscoveryViewModel`. `VisitedStation`'s stored fields stay, so the logbook's storage is unchanged.
- Six files listed in the Xcode workspace that don't exist.
- The unused SwiftData migration plan (`VisitedStationMigration`), which described schemas the store never had.
- The network session's response cache (10 MB in memory, 50 MB on disk), which was written and never read.
- The client-side limit of 30 requests a minute, which delayed loads during an outage and counted requests that were never sent.
- The backend health monitor (`BackendHealthMonitor`) and its network path monitor, which kept running once Settings had opened.

### Fixed
- The unit and UI test targets now compile their test folders. Before, neither target contained any code, and the unit-test stub imported a module that doesn't exist.
- A fresh clone builds without first creating `Secrets.xcconfig`.
- A Debug launch downloads the station list once instead of twice.
- Debug builds no longer write part of the API key to the log.
- A test run no longer sends requests to the NS API or opens the simulator's stored visits: while hosting the unit tests, the app shows an empty screen.
- Without code signing (`CODE_SIGNING_ALLOWED=NO`), the Keychain tests are skipped with a reason instead of failing with -34018.
- The app no longer erases the logbook when it can't open it, and no longer carries on with a temporary logbook whose visits are lost when the app quits. It says the logbook couldn't be opened, offers Try Again and Start a New Logbook, and tries again by itself each time the app comes to the foreground. Starting a new logbook asks first, then moves the old one into a backup folder on the device instead of deleting it.
- On iPad, all windows share one logbook, so a visit marked in one window shows in the others.
- The station list is downloaded once and shared by every screen and window for an hour. Opening the Logbook or the Home Station picker no longer downloads it again, Discover no longer downloads it again right after onboarding, and screens that load at the same time share one download. All requests go through one network session, so they reuse its connections.
- When the station list can't be loaded, the message says why: no key stored, a stored key that can't be read right now, a key NS rejected, a key over its usage limit, too many requests, NS unavailable, no connection, or data this version can't read. Before, a Keychain problem and a usage limit both read as a missing key, and a failed name lookup read as an NS server error.
- A load or key check that is cut short, for example by leaving Settings while it checks the key, no longer counts as a failure.
- Retries follow NS's `Retry-After`, in seconds or as a date in any of the forms HTTP allows, up to three attempts. Without it, the waits are as before: 0.5 and then 1 second after a server error, 1 and then 2 seconds after too many requests. A wait longer than 10 seconds, or too long to read, fails at once instead of keeping the screen loading. Key, permission and data errors, and server errors another attempt can't fix (501, 505), aren't retried, and a failure is logged once instead of once per attempt.
- A network that wants you to sign in before it lets you online (511), such as a captive portal, reads as no connection instead of NS being unavailable, and isn't retried.
- After NS rejects or refuses an API key (401 or 403), the app doesn't send that key again for 15 minutes, or until a key is saved in Settings, even the same one.
- A station the app can't read is skipped and logged instead of failing the whole list. The fields no screen shows (the medium name, the UIC code and the tracks) may be missing or of another type. A list with no Dutch station the app can read fails as data it can't read, instead of leaving Discover with nothing to pick.
- Settings no longer calls a working API key broken when NS answers slowly, can't be reached, is busy (429) or failing (5xx), or sends data the app can't read, or after the connection dropped and came back. It shows the same message Discover shows, and offers Remove Key only when NS rejected the key (401). A rejected key reads "NS didn't accept this key." A key NS refused (403), which may only be over its usage limit, can be replaced there but isn't offered for removal.
- Settings checks the key against the station list the app shares instead of downloading the list on every visit, so within the hour after a successful load a visit sends nothing, and Settings and Discover agree on the same list.
- A key saved or removed in Settings is checked with that key: a list stored, a download still running or a refusal for the previous key no longer answers for it. Leaving Settings while it checks leaves its status as it was. On iPad, every window's Settings shows the same key status, so a window no longer offers to remove a key that another window replaced.
- When the station list can't be loaded, every screen offers a way forward: Retry where trying again can help (no connection, too many requests, NS unavailable, data the app can't read), and a way to enter a key where only a key can (no key, a key that can't be read, a key NS rejected or refused): Settings' key section, or onboarding's own key step. Discover offers Retry, or Open Settings, which switches that window to the Settings tab. Onboarding offers Retry for the errors that had no button. The Home Station picker shows the error with Retry or Back to Settings instead of an empty list, also right after a key is removed or a rejected key is saved. Settings offers Retry when it can't check the key. Retry joins a download already running, and doesn't send a key NS refused again.
- Offline, a load fails at once with "Can't reach NS. Check your internet connection." instead of waiting up to a minute for a connection and then reporting a timeout. A request that receives nothing for 15 seconds fails (was 30); one whose reply is still arriving has up to a minute in all, as before.
- When no API key is stored, or the stored one can't be used (it can't be read, or NS rejected or refused it), onboarding opens on a key step: it says InspiRail needs a free NS API key, links to apiportal.ns.nl, and takes the key there, instead of a station search over an error panel. After Save Key it loads the stations with the new key at once, with one request: the list, or why NS didn't accept the key, or Retry when NS couldn't be reached. The Settings sheet onboarding opened for the key is gone. On iPad, a key saved in one window's onboarding moves the other windows on too: to the station list when it works, to NS's answer when NS rejects or refuses it, or to Retry when NS couldn't be reached. No window shows an answer about a key another window has since replaced.
- Onboarding's search field appears once the stations have loaded.
- Tapping a station in onboarding selects it, with a checkmark, instead of ending onboarding; tapping another moves the selection. Start Exploring stores the home station and opens the tabs. Existing users, who already have a home station, go straight to the tabs as before.
- Discover never suggests the home station. Its first suggestion after loading could.
- The Logbook's percentage leaves the home station out: its total counts every Dutch station but the home station, so a logbook with every other station visited shows 100 %. The total follows a change of home station at once, also before the station list has loaded.
- Settings' Reset Logbook counts the visits the Logbook shows, so it leaves a visit to the home station out, and is disabled when the Logbook shows none. It still deletes every visit, the home station's included.

---

## [1.4.1] — 2026-06-05 (build 7)

### Fixed
- The app icon no longer carries a white inset frame around the NS Sprinter artwork. The source image had a white frame plus soft fade-to-white gradients on all four edges (the original art's vanishing-point motion blur). Cropped to the perceptual content bounds — the train scene now extends to the icon edges so the iOS rounded mask hugs the artwork directly.

---

## [1.4.0] — 2026-06-05 (build 6)

### Changed
- Logbook page redesigned around a HIG-pure, collection-progress aesthetic. The old gradient progress ring and shadowed stats card are gone; the hero is now a compact "N of total" header with a slim system-blue progress bar and percentage readout. Rows show plain typography with the station code restored as a soft yellow badge for the collectible-tag feel.
- Visit dates now render with smart relative formatting — "Just now" / "Yesterday" / weekday name / "Jan 16" — so the most recent activity reads at a glance.
- The total Dutch station count is cached in `UserDefaults`, so the hero stats render instantly on subsequent launches instead of flickering from the previous hardcoded 397.

### Added
- Empty state for the visited timeline: when no stations have been logged yet, the timeline section shows a friendly "No visits yet" prompt directing the user to the Discover tab.

### Fixed
- The home station's visit is left out of the visited count, as it already was from the timeline list (before, it counted toward the visited count). The total still counted every Dutch station, the home station included, so the percentage couldn't reach 100 %.

---

## [1.3.1] — 2026-06-05 (build 5)

### Fixed
- End users can now recover from a missing or invalid NS API key. Settings exposes a Keychain-backed SecureField for entering it, and the onboarding error state offers an "Open Settings" button that sheet-presents the entry screen and retries the station load on dismiss.
- `Secrets.xcconfig.template` no longer ships inside the app bundle — Xcode's folder-sync was picking it up as an app resource.

### Changed
- The Settings screen uses progressive disclosure for the API-key section: it only appears when the Keychain is empty or `BackendHealthMonitor` reports the backend as unhealthy. Otherwise the screen stays clean.

---

## [1.3.0] — 2026-06-04 (build 4)

The first audited build. Most of the code that landed in the prior Beta drop (`08aa155`), cleaned up and organised into reviewable commits, plus repo-hygiene fixes.

### Added
- Backend layer: `BackendAPI` (NS API client), `KeychainManager`, `BackendHealthMonitor`, `BackgroundRefreshManager`, `NetworkMonitor`, `AnalyticsManager`, `AppConfiguration`.
- Persistence: `VisitedStationMigration` for the visited-stations schema bump.
- Developer tooling: `APIKeyDiagnostics`, `APIKeySetupHelper`.
- Repo hygiene: tracked `.gitignore`, repo-root `README.md`, `Secrets.xcconfig.template`, shared Xcode scheme, `Inspirail.xctestplan`.
- Long-form documentation moved to the project wiki (since retired, see #6; its pages are archived in [`docs/archive/wiki/`](docs/archive/wiki/README.md)).

### Changed
- Onboarding now drives off the new `StationsRepository`.
- Discovery, Visited list, and Settings rewired around the new backend layer.

### Security
- Removed a hardcoded NS API key fallback that was baked into release builds via `BackendAPI.swift`.
- Removed `Secrets.xcconfig` from the app's Resources build phase, so the file is no longer bundled into the shipped binary.
- Untracked `xcuserdata/` to stop user-specific Xcode state from leaking through git.

> ⚠️ The NS API key shipped in earlier TestFlight builds should be assumed exposed and **rotated at apiportal.ns.nl**.

---

## Pre-history

The initial project commit (`d565b4c`, around 2026-02) carried `MARKETING_VERSION = 1.0` / build 1 but had no structured release notes. Versions between 1.0 and 1.3 were internal builds that never landed on `main`.
