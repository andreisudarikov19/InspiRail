# NS API integration reference

How InspiRail authenticates with the NS API, which endpoint it calls, and how to test a key from the command line.


## Authorization

Access keys for NS API products are on your [Profile](https://apiportal.ns.nl/profile) page, under **Abonnementen** (subscriptions).

> To get access to NS API products, follow [Access NS API products](ns-api-access.md).


## Request structure

The NS API authenticates with a subscription key, sent in the `Ocp-Apim-Subscription-Key` header:

```sh
curl -X GET "ENDPOINT_URL" \
     -H "Ocp-Apim-Subscription-Key: YOUR_API_KEY"
```

In the app, `BackendAPI` reads the key from the Keychain and adds this header to every request.


## Endpoints the app uses

The app calls one endpoint of the [NS-App Stations API](https://apiportal.ns.nl/api-details#api=nsapp-stations-api), the full station list:

```txt
GET https://gateway.apiportal.ns.nl/nsapp-stations/v3?includeNonPlannableStations=false
```

The response is an object whose `payload` array holds one entry per station. These are the fields the app decodes (`Models/Station.swift`):

| Field | Meaning |
|---|---|
| `id.code` | Station code, the app's station identifier |
| `id.uicCode` | UIC code |
| `names.long`, `names.medium`, `names.short` | Display names |
| `names.synonyms` | Alternative names |
| `stationType` | Station category, as an upper-case enum value |
| `location.lat`, `location.lng` | Coordinates |
| `country` | Country code |
| `tracks`, `hasKnownFacilities`, `hasTravelAssistance` | Optional details |

The list includes stations outside the Netherlands. The app keeps only those with `country` equal to `NL`, filtering after decoding.


## Connection testing

To check a key, fetch the station list and pick out Utrecht Centraal:

```sh
curl -s -H "Ocp-Apim-Subscription-Key: $NSAPI_KEY" \
     "https://gateway.apiportal.ns.nl/nsapp-stations/v3?includeNonPlannableStations=false" | \
     jq '.payload[] | select(.names.long == "Utrecht Centraal") | {station_code: .id.code, full_name: .names.long}'
```

In the command above:

* `curl -s`: the silent flag hides the progress meter.

* `jq '.payload[] | ...'`:

    * `.payload[]`: iterates over every station in the list.

    * `select(.names.long == "Utrecht Centraal")`: keeps only Utrecht Centraal.

    * `{station_code: .id.code, full_name: .names.long}`: prints only the station code and the full name.

With a valid key, the command prints one object holding Utrecht Centraal's code and full name. Without a valid key, the API answers with an error and no `payload`, so `jq` prints only an error of its own.
