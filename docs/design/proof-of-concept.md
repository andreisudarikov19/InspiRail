# Technical Design Document

* **Project**: OranjeRail (iOS)

* **Architecture**: MVVM (Model-View-ViewModel)

* **Data Persistence**: SwiftData

* **Language**: Swift 6.0 / SwiftUI


## System Architecture

The app will follow a unidirectional data flow.

* View Layer: SwiftUI Views that observe `ViewModels`.

* Business Layer: `ViewModels` handling UI logic and state.

* Service Layer: Modular managers for Networking and Persistence.


## Data Strategy

* Remote Data: Fetched from NS API: Stations v3 and Disruptions.

* Local Data: User's `homeStation` (String code) stored in `@AppStorage`.

* Database: `VisitedStation` entities stored in a SwiftData `ModelContainer`.


## Key Logic: The "Randomizer Pipeline"

1. Fetch full station list, filter by `countryCode == "NL"`.

1. Filter out the current `homeStation`.

1. Randomly select one station.

1. Perform a secondary API call to check for active disruptions between `homeStation` and `selectedStation`.

1. Update UI with station details and a status warning if disruptions exist.


## Data layer

The database has two models: Station and Disruption.


### Station

The NS API stations endpoint returns a large JSON object. We need to decode this into a Swift struct that conforms to `Codable` and `Identifiable`:

```swift
struct Station: Codable, Identifiable {
    let id: String // We can use the station 'code' as the ID
    let names: StationNames
    let stationType: String
    let countryCode: String
    let lat: Double
    let lng: Double
    
    enum CodingKeys: String, CodingKey {
        case id = "code"
        case names
        case stationType
        case countryCode
        case lat
        case lng
    }
}

struct StationNames: Codable {
    let long: String
    let medium: String
    let short: String
}
```


### Disruption

This model captures if the suggested station or route is currently affected:

```swift
struct Disruption: Codable, Identifiable {
    let id: String
    let title: String
    let isActive: Bool
    let type: String // e.g., "MAINTENANCE" or "DISRUPTION"
}
```


## Service classes

* **NetworkManager**: A generic class using `URLSession` to handle the headers ith NS API key and the JSON decoding.

* **StationService**: Specifically handles fetching the list of stations and picking a random one.

* **PersistenceManager**: Handles saving the Home Station and the Visited Stations list using `SwiftData`.
