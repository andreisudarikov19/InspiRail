# NS API integration reference

This document covers autorization, request structure and relevant API endpoints and connection testing.


## Authorization

Access keys to NS API products are located on your [Profile](https://apiportal.ns.nl/profile) page under **Abonnementen**.

> To get access to NS API products, use [these instructions](../howto/access-ns-api-products.md).


## Request structure

The NS API uses a header-based authentication method. You must include your subscription key in a header as `Ocp-Apim-Subscription-Key`:

```sh
curl -X GET "ENDPOINT_URL" \
     -H "Ocp-Apim-Subscription-Key: YOUR_API_KEY"
```


## Relevant API endpoints

he app uses [NS-APP Stations API](https://apiportal.ns.nl/api-details#api=nsapp-stations-api&operation=getNearestStations):

```txt
https://gateway.apiportal.ns.nl/nsapp-stations/v2
```


## Connection testing

Use the following command to get a station code and a full name for Utrecht Centraal:

```sh
curl -s -H "Ocp-Apim-Subscription-Key: $NSAPI_KEY" \
     "https://gateway.apiportal.ns.nl/nsapp-stations/v3?includeNonPlannableStations=true&countryCodes=NL&limit=1" | \
     jq '.payload[] | select(.names.long == "Utrecht Centraal") | {station_code: .id.code, full_name: .names.long}'
```

In the command above:

* `curl -s`: The "silent" flag hides the progress meter.

`"https://gateway.api.ns.nl/nsapp-stations/v2/stations"`: base URL for the station list  the most relevant API set for the app.

* `jq '.payload[] | ...'`:

    * `.[]`: iterates through every station in the list.

    * `select(.names.long == "Utrecht Centraal")`: search filter to pick only Utrecht Centraal.

    * `{station_code: .id.code, full_name: .names.long}`: creates a custom JSON object showing only the information relevant to the app.
