# InspiRail

A SwiftUI iOS app that helps you discover and log Dutch railway stations, backed by the live NS Reisinformatie API.

## Status

Pre-release, under active development. Current version: [**1.4.1**](CHANGELOG.md#141--2026-06-05-build-7). The app isn't ready for general distribution yet; open work is tracked in [GitHub Issues](https://github.com/andreisudarikov19/InspiRail/issues), and the [changelog](CHANGELOG.md) records what has shipped.

## Requirements

- Xcode 16 or newer (the project uses the iOS 26 SDK and Xcode's `PBXFileSystemSynchronizedRootGroup` folder-sync).
- An iOS 26+ simulator or device.
- A free NS API key from <https://apiportal.ns.nl>.

## Quick start

```bash
git clone https://github.com/andreisudarikov19/InspiRail.git
cd InspiRail
open InspiRail.xcodeproj
```

Press ⌘R to build and run. On first launch the app will prompt you to enter your NS API key — paste it in Settings and the rest of the app comes alive.

## API key handling

The NS API key lives only in the iOS Keychain. Nothing is compiled into the app, and the project has no `Secrets.xcconfig`; a leftover local copy is ignored.

- **End users** — launch the app, follow the "Open Settings" button on the onboarding error screen, paste the key, save. The key never leaves the device.
- **Developers (Debug builds only)** — set `NS_API_KEY` in the app's environment, either by launching with `SIMCTL_CHILD_NS_API_KEY=… xcrun simctl launch <device> annisu.rnsapp`, or on a duplicate of the `InspiRail` scheme with "Shared" unticked, so the value stays in the untracked `xcuserdata`. Don't set it on the shared scheme: that file is tracked. In Debug builds the variable wins over a stored key. When no key is stored yet, it is saved to the Keychain, so later launches work without it; it never replaces a key saved in Settings. Release builds never read it.

## Project layout

```
InspiRail/
├── Models/                    SwiftData & Codable data models
├── NetworkEngine/             HTTP plumbing and errors
├── Pages/                     SwiftUI screens (Discovery, Onboarding,
│                              Settings, VisitedList)
├── ViewModels/                @MainActor view-models and repositories
├── BackendAPI.swift           NS API client (actor)
├── KeychainManager.swift      API-key storage
├── APIKeyProvider.swift       Picks the API key (Keychain, Debug env)
├── BackendHealthMonitor.swift Connectivity + backend health
├── BackgroundRefreshManager.swift
├── NetworkMonitor.swift
├── AnalyticsManager.swift     Event tracking
├── AppConfiguration.swift     Centralised config (URLs, timeouts, flags)
└── InspiRailApp.swift         App entry point
```

The `InspiRail/` folder is an Xcode `PBXFileSystemSynchronizedRootGroup`, so any `.swift` file dropped inside it joins the build automatically — no manual `project.pbxproj` editing needed. The test folders work the same way: `InspiRailTests/` (unit tests, Swift Testing) and `InspiRailUITests/` (UI tests, none yet).

## Tests

Press ⌘U, or run:

```bash
xcodebuild test -project InspiRail.xcodeproj -scheme InspiRail -destination 'platform=iOS Simulator,name=iPhone 17'
```

- The unit tests run inside the app. `InspiRail.xctestplan` sets `INSPIRAIL_UNIT_TEST_HOST=1`, so while hosting them the app shows an empty screen, sends no requests to the NS API and doesn't open the stored visits.
- The Keychain tests need a signed test host. In a build with `CODE_SIGNING_ALLOWED=NO` they are skipped, and the test log says why.
- `InspiRailUITests/` holds no tests yet, and the target isn't in the test plan.

## Versioning & releases

The app follows [Semantic Versioning](https://semver.org). The `MARKETING_VERSION` build setting is the public `MAJOR.MINOR.PATCH` version; `CURRENT_PROJECT_VERSION` is a monotonic integer build number incremented for each TestFlight or App Store submission. See [`CHANGELOG.md`](CHANGELOG.md) for the full history and the versioning policy in detail.

## Documentation

All documentation lives in [`docs/`](docs/README.md):

- [NS API integration reference](docs/reference/ns-api.md): authentication, the stations endpoint, and how to test a key.
- [Access NS API products](docs/reference/ns-api-access.md): subscribing on the NS API portal to get a key.
- [Proof-of-concept design](docs/design/proof-of-concept.md): the original technical design, with notes on where the app differs from it today.
- [Wiki archive](docs/archive/wiki/README.md): the retired GitHub wiki, kept as input for planning. It doesn't describe the current code.
