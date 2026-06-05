# Changelog

All notable changes to Inspirail are recorded here. The format is loosely based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Versioning

- `MARKETING_VERSION` — public-facing version in `MAJOR.MINOR.PATCH` form.
  - `MAJOR` — incompatible data-model or API changes that require user action.
  - `MINOR` — new user-visible features or significant UX changes.
  - `PATCH` — bug fixes, internal cleanups, build-only changes.
- `CURRENT_PROJECT_VERSION` — monotonic integer build number. Incremented for every TestFlight or App Store submission, never reused.

Both live in `Inspirail.xcodeproj/project.pbxproj` on the app target and flow through to `CFBundleShortVersionString` / `CFBundleVersion` in the built `Info.plist` via Xcode's auto-generated plist.

---

## [1.4.0] — 2026-06-05 (build 6)

### Changed
- Logbook page redesigned around a HIG-pure, collection-progress aesthetic. The old gradient progress ring and shadowed stats card are gone; the hero is now a compact "N of total" header with a slim system-blue progress bar and percentage readout. Rows show plain typography with the station code restored as a soft yellow badge for the collectible-tag feel.
- Visit dates now render with smart relative formatting — "Just now" / "Yesterday" / weekday name / "Jan 16" — so the most recent activity reads at a glance.
- The total Dutch station count is cached in `UserDefaults`, so the hero stats render instantly on subsequent launches instead of flickering from the previous hardcoded 397.

### Added
- Empty state for the visited timeline: when no stations have been logged yet, the timeline section shows a friendly "No visits yet" prompt directing the user to the Discover tab.

### Fixed
- The home station is now consistently excluded from both the timeline list and the progress percentage (previously it counted toward `%` but was filtered from the list).

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
- Long-form documentation moved to the [project wiki](https://github.com/andreisudarikov19/InspiRail/wiki).

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
