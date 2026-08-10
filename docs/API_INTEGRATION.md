# AgriLink — API Integration Documentation

**Project:** AgriLink Mobile (Flutter)
**Feature:** Live weather for harvest planning and delivery safety
**Date:** August 2026

---

## 1. API Name

**Open-Meteo** — a free, open-source weather API (https://open-meteo.com).

It was chosen over alternatives such as OpenWeatherMap for three reasons:

- **No API key and no account.** Nothing secret has to be committed to the
  repository, and the project can be run straight from source by anyone
  reviewing it.
- **Free for non-commercial use**, with no request quota that a classroom demo
  could exhaust.
- **It has a geocoding endpoint on the same service**, so town search and the
  forecast come from one provider instead of two.

Open-Meteo requires attribution, which the app displays on the forecast page:
*"Weather data by Open-Meteo.com"*.

---

## 2. API Endpoints Used

Two endpoints are integrated.

### 2.1 Forecast endpoint

```
GET https://api.open-meteo.com/v1/forecast
```

| Parameter | Value sent | Purpose |
| --- | --- | --- |
| `latitude`, `longitude` | From the account's pinned location | Where to report on |
| `current` | `temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m` | Conditions right now |
| `daily` | `weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum` | 7-day outlook |
| `timezone` | `auto` | Return local Philippine times |
| `forecast_days` | `7` | Length of the outlook |

Full example request:

```
https://api.open-meteo.com/v1/forecast?latitude=15.4865&longitude=120.9734
  &current=temperature_2m,relative_humidity_2m,apparent_temperature,precipitation,weather_code,wind_speed_10m
  &daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum
  &timezone=auto&forecast_days=7
```

### 2.2 Geocoding endpoint

```
GET https://geocoding-api.open-meteo.com/v1/search
```

| Parameter | Value sent | Purpose |
| --- | --- | --- |
| `name` | The user's search text | Town being looked up |
| `count` | `8` | Maximum results |
| `language` | `en` | Result language |
| `format` | `json` | Response format |

Full example request:

```
https://geocoding-api.open-meteo.com/v1/search?name=Cabanatuan&count=8&language=en&format=json
```

---

## 3. Sample JSON Responses

### 3.1 Forecast response (actual response, Cabanatuan, 10 August 2026)

```json
{
  "latitude": 15.500878,
  "longitude": 120.95864,
  "generationtime_ms": 2.3987293243408203,
  "utc_offset_seconds": 28800,
  "timezone": "Asia/Manila",
  "timezone_abbreviation": "GMT+8",
  "elevation": 33.0,
  "current_units": {
    "time": "iso8601",
    "temperature_2m": "°C",
    "relative_humidity_2m": "%",
    "apparent_temperature": "°C",
    "precipitation": "mm",
    "weather_code": "wmo code",
    "wind_speed_10m": "km/h"
  },
  "current": {
    "time": "2026-08-10T23:30",
    "interval": 900,
    "temperature_2m": 25.2,
    "relative_humidity_2m": 95,
    "apparent_temperature": 29.2,
    "precipitation": 0.00,
    "weather_code": 3,
    "wind_speed_10m": 15.2
  },
  "daily_units": {
    "time": "iso8601",
    "weather_code": "wmo code",
    "temperature_2m_max": "°C",
    "temperature_2m_min": "°C",
    "precipitation_probability_max": "%",
    "precipitation_sum": "mm"
  },
  "daily": {
    "time": ["2026-08-10", "2026-08-11", "2026-08-12"],
    "weather_code": [95, 95, 95],
    "temperature_2m_max": [28.9, 30.6, 29.6],
    "temperature_2m_min": [24.3, 24.7, 24.8],
    "precipitation_probability_max": [100, 100, 100],
    "precipitation_sum": [14.20, 10.70, 17.60]
  }
}
```

Note that `daily` is **column-oriented**: every field is a parallel array, and
index `i` of each array describes the same day. The parser walks `daily.time`
by index and reads the matching position out of every other array.

### 3.2 Geocoding response (actual response)

```json
{
  "results": [
    {
      "id": 1721906,
      "name": "Cabanatuan City",
      "latitude": 15.48586,
      "longitude": 120.96648,
      "elevation": 36.0,
      "feature_code": "PPL",
      "country_code": "PH",
      "timezone": "Asia/Manila",
      "population": 343672,
      "country": "Philippines",
      "admin1": "Central Luzon",
      "admin2": "Province of Nueva Ecija",
      "admin3": "Cabanatuan City"
    }
  ],
  "generationtime_ms": 0.28407574
}
```

When nothing matches, Open-Meteo **omits the `results` key entirely** rather
than returning an empty array — the parser defaults to an empty list so this
does not throw.

---

## 4. Explanation of the Integration

### 4.1 Files added

| File | Role |
| --- | --- |
| `lib/services/weather_service.dart` | HTTP GET requests, timeouts, error mapping |
| `lib/models/weather.dart` | JSON → `FarmWeather`, `DailyForecast`, `GeoPlace`; advisory logic |
| `lib/widgets/weather_card.dart` | The dashboard card and its loading/error states |
| `lib/screens/weather_screens.dart` | 7-day outlook page with town search |
| `test/weather_service_test.dart` | 12 automated tests over parsing and failures |

### 4.2 Data flow

```
Account's pinned coordinates (saved at signup, in Firestore)
        │
        ▼
WeatherService.loadForecast()  ──HTTP GET──▶  api.open-meteo.com/v1/forecast
        │
        ▼
jsonDecode()  →  FarmWeather.fromJson()   (typed Dart objects)
        │
        ▼
WeatherPanel (LiveBuilder: auto-refresh every 10 min + pull-to-refresh)
        │
        ▼
WeatherCard on the Farmer and Rider dashboards
```

The coordinates are **not hardcoded**. They come from the location the user
pinned on the map during registration, which is already stored in the
`mobileUsers` Firestore collection. This is what makes the integration part of
the system rather than a bolt-on: the forecast is for *that farmer's actual
farm*. If an account has no pin, the app falls back to Cabanatuan, Nueva Ecija.

### 4.3 HTTP GET implementation

`WeatherService._getJson()` is the single request path used by both endpoints:

```dart
final response = await _client.get(uri).timeout(_timeout);
...
final decoded = jsonDecode(response.body);
```

The URL is assembled with `Uri.https(host, path, queryParameters)` so all
parameters are correctly percent-encoded, and a 12-second timeout stops the UI
from hanging on a dead network.

### 4.4 JSON data processing

Raw JSON is never passed to the UI. It is converted into typed Dart objects
first, which keeps the parsing in one testable place:

- `FarmWeather.fromJson()` reads the `current` object and walks the
  column-oriented `daily` arrays by index.
- `_toDouble` / `_toInt` helpers coerce values defensively, because Open-Meteo
  returns `0.00` as a double and `weather_code` as an integer, and a missing
  field must not crash the dashboard.
- `WeatherCondition.fromCode()` maps the numeric **WMO weather code** to a
  human label and emoji (e.g. `95` → "Thunderstorm ⛈️"), keeping only the
  outcomes relevant to the Philippines.

### 4.5 Display in the user interface

The retrieved data appears in three places:

1. **Farmer Dashboard → "Harvest weather"** — temperature, condition, humidity,
   wind, rain chance, a 4-day strip, and a harvest advisory.
2. **Rider Dashboard → "Delivery conditions"** — the same data with a
   delivery-safety advisory instead.
3. **Weather outlook page** — full 7-day table plus town search.

The API values are also *interpreted*, not just printed. The same reading
produces different guidance per role:

| Condition | Farmer sees | Rider sees |
| --- | --- | --- |
| Thunderstorm | "Storm conditions. Hold off on harvesting and secure your stored produce." | "Storm conditions. Avoid accepting trips until this passes." |
| Rain ≥60% within 3 days | "Rain likely within three days. Harvest and list your crops early." | "Rain expected soon. Bring a tarpaulin for the pooled orders." |
| Clear, <34 °C | "Good harvest window. Clear enough to pick, pack, and list today." | "Clear roads. Good conditions for pooled deliveries." |

### 4.6 Error handling

Every failure is caught and turned into a message the user can act on. The
weather card degrades on its own — the rest of the dashboard keeps working.

| Failure | Detection | Message shown |
| --- | --- | --- |
| No internet | `SocketException` | "No internet connection. Check your network and try again." |
| Connection dropped | `http.ClientException` | "Could not reach the weather service. Check your connection." |
| Server too slow | `TimeoutException` (12 s) | "The weather service took too long to respond. Try again." |
| Rate limited | HTTP 429 | "Too many weather requests right now. Try again in a minute." |
| API down | HTTP 5xx | "The weather service is temporarily unavailable." |
| Other HTTP error | status ≠ 200 | "Weather request failed (404)." |
| Not JSON (e.g. an HTML error page) | `FormatException` | "The weather service returned an invalid response." |
| JSON missing expected keys | null check on `current` / `daily` | "The weather service returned an unexpected response." |

Each error state renders a card with the message and a **retry button**.

---

## 5. Bonus Features Implemented

| Bonus | How |
| --- | --- |
| **Multiple API endpoints** | Forecast endpoint + geocoding endpoint |
| **Search functionality** | Town search on the outlook page, debounced 450 ms so one lookup fires per pause in typing rather than one per keystroke |
| **Dynamic refresh without reloading the page** | `LiveBuilder` re-fetches every 10 minutes, a refresh button re-fetches on demand, and pull-to-refresh updates in place — all via `setState`, with no page rebuild |

Because any write elsewhere in the app signals the live screens to reload, the
service also holds a **5-minute cache** keyed by coordinates. Routine reloads
are served from memory, while the refresh button clears the cache first so
"refresh" always means a real request.

A POST request was not implemented because Open-Meteo is a read-only API and
exposes no POST endpoint.

---

## 6. Testing

`test/weather_service_test.dart` contains 13 tests run with `flutter test`,
using a mocked HTTP client so they need no network:

- Correct URL, host, and query parameters for both endpoints
- Parsing of current conditions and the daily arrays
- WMO code → condition mapping, including severe weather
- Every error path in the table above
- Advisory text for storm / incoming rain / fair weather
- Debounce guard: a one-character query never reaches the network
- Cache behaviour: repeat lookups reuse the result, `clearCache()` forces a
  fresh request

**Result:** 52 of 52 tests passing across the project; `flutter analyze` reports
no issues.

---

## 7. Screenshots

> Take these on a device or emulator and paste them in.

1. **API request working** — Farmer Dashboard showing the "Harvest weather"
   card with live values.
2. **Data displayed in the project** — Rider Dashboard "Delivery conditions"
   card with the delivery advisory.
3. **Multiple endpoints / search** — Weather outlook page with a town searched
   and the 7-day table shown.
4. **Error handling** — turn off Wi-Fi and mobile data, then open a dashboard to
   capture the "Weather unavailable" card.

---

## 8. Database Impact

No new collection was required. The integration **reads existing data** —
`latitude` and `longitude` in the `profile` map of the `mobileUsers`
collection, captured when the user pinned their location during registration.
Weather results are not persisted, because cached forecasts go stale faster
than they are useful.

---

## 9. Reflection

Integrating the Open-Meteo API turned AgriLink from a system that only records
transactions into one that helps users decide *when* to act — a farmer can now
see that a 100% chance of rain is coming and harvest early rather than losing
a crop, and a rider can see that a thunderstorm makes a pooled route unsafe
before accepting it. The main challenge was that Open-Meteo returns its daily
forecast in a column-oriented format, where each field is a separate parallel
array instead of a list of day objects, so the parser had to walk the arrays by
index and defend against fields of different lengths. A second challenge was
error handling: a weather widget must never take down the dashboard, so every
failure — no connection, timeout, rate limit, or an HTML error page arriving
where JSON was expected — had to be caught individually and turned into a clear
message with a retry option rather than an exception. The most valuable lesson
was that displaying raw API data is not the same as integrating it; mapping the
numeric WMO weather codes into role-specific advice for farmers and riders is
what actually made the data useful inside our system.
