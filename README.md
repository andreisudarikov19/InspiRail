# Inspirail

A SwiftUI iOS app that helps you discover and log Dutch railway stations, backed by the live NS Reisinformatie API.

## Status

Pre-1.0, under active development. Current release: [**1.3.1**](CHANGELOG.md#131--2026-06-05-build-5). The app is not yet ready for general distribution — see the [changelog](CHANGELOG.md) and the [wiki backend review](https://github.com/andreisudarikov19/InspiRail/wiki/BACKEND_REVIEW) for what's outstanding.

## Requirements

- Xcode 16 or newer (the project uses the iOS 26 SDK and Xcode's `PBXFileSystemSynchronizedRootGroup` folder-sync).
- An iOS 26+ simulator or device.
- A free NS API key from <https://apiportal.ns.nl>.

## Quick start

```bash
git clone https://github.com/andreisudarikov19/InspiRail.git
cd InspiRail
open Inspirail.xcodeproj
```

Press ⌘R to build and run. On first launch the app will prompt you to enter your NS API key — paste it in Settings and the rest of the app comes alive.

## API key handling

The NS API key lives in the iOS Keychain. There are two ways to get one there:

- **End-user path** — launch the app, follow the "Open Settings" button on the onboarding error screen, paste the key, save. The key never leaves the device.
- **Developer shortcut (Debug builds only)** — set `NS_API_KEY` as an environment variable on the `Inspirail` scheme, or launch via `SIMCTL_CHILD_NS_API_KEY=… xcrun simctl launch <device> annisu.rnsapp`. `BackendAPI` reads this in DEBUG and migrates it to the Keychain automatically.

`Secrets.xcconfig` is gitignored. It used to be bundled into the app at build time; that path was removed in 1.3.0 because anything inside the shipped binary is extractable from the `.ipa`.

## Project layout

```
inspirail/
├── Models/                    SwiftData & Codable data models
├── NetworkEngine/             HTTP plumbing, retry/cache, key diagnostics
├── Pages/                     SwiftUI screens (Discovery, Onboarding,
│                              Settings, VisitedList)
├── ViewModels/                @MainActor view-models and repositories
├── BackendAPI.swift           NS API client (actor)
├── KeychainManager.swift      API-key storage
├── BackendHealthMonitor.swift Connectivity + backend health
├── BackgroundRefreshManager.swift
├── NetworkMonitor.swift
├── AnalyticsManager.swift     Event tracking
├── AppConfiguration.swift     Centralised config (URLs, timeouts, flags)
└── rnsappApp.swift            App entry point
```

The `inspirail/` folder is an Xcode `PBXFileSystemSynchronizedRootGroup`, so any `.swift` file dropped inside it joins the build automatically — no manual `project.pbxproj` editing needed.

## Versioning & releases

The app follows [Semantic Versioning](https://semver.org). The `MARKETING_VERSION` build setting is the public `MAJOR.MINOR.PATCH` version; `CURRENT_PROJECT_VERSION` is a monotonic integer build number incremented for each TestFlight or App Store submission. See [`CHANGELOG.md`](CHANGELOG.md) for the full history and the versioning policy in detail.

## Documentation

- [NS API integration reference](docs/reference/ns-api.md): authentication, the stations endpoint, and how to test a key.
- [Access NS API products](docs/reference/ns-api-access.md): subscribing on the NS API portal to get a key.
- [Proof-of-concept design](docs/design/proof-of-concept.md): the original technical design, with notes on where the app differs from it today.

Architecture notes, design diagrams, the visited-stations migration write-up and the backend review live in the [project wiki](https://github.com/andreisudarikov19/InspiRail/wiki).
