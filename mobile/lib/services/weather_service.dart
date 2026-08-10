import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/weather.dart';

/// A weather lookup that failed for a reason worth showing the user.
class WeatherException implements Exception {
  const WeatherException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Reads live conditions from the public Open-Meteo API.
///
/// Open-Meteo needs no API key and no account, so the app can ship without a
/// secret and a marker can run it straight from source. Two endpoints are used:
/// the forecast endpoint for conditions at a pinned farm or delivery address,
/// and the geocoding endpoint so anyone can look up another town by name.
class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _forecastHost = 'api.open-meteo.com';
  static const _geocodingHost = 'geocoding-api.open-meteo.com';
  static const _timeout = Duration(seconds: 12);

  /// Conditions barely move minute to minute, and every write in the app nudges
  /// the live screens to reload, so repeat lookups are served from here instead
  /// of hitting the API again.
  static const cacheLifetime = Duration(minutes: 5);
  final Map<String, (DateTime, FarmWeather)> _cache = {};

  /// Drops the cache so the next lookup is a real request. Used by the manual
  /// refresh button, where the point is to get fresh numbers.
  void clearCache() => _cache.clear();

  /// GET https://api.open-meteo.com/v1/forecast
  ///
  /// Returns current conditions plus a [days]-day outlook for the coordinates
  /// the account pinned during signup.
  Future<FarmWeather> loadForecast({
    required double latitude,
    required double longitude,
    String placeName = 'Your location',
    int days = 7,
  }) async {
    final cacheKey = '$latitude,$longitude,$days';
    final cached = _cache[cacheKey];
    if (cached != null &&
        DateTime.now().difference(cached.$1) < cacheLifetime) {
      return cached.$2;
    }

    final uri = Uri.https(_forecastHost, '/v1/forecast', {
      'latitude': '$latitude',
      'longitude': '$longitude',
      'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,'
          'precipitation,weather_code,wind_speed_10m',
      'daily': 'weather_code,temperature_2m_max,temperature_2m_min,'
          'precipitation_probability_max,precipitation_sum',
      'timezone': 'auto',
      'forecast_days': '$days',
    });

    final json = await _getJson(uri);
    if (json['current'] == null || json['daily'] == null) {
      throw const WeatherException(
        'The weather service returned an unexpected response.',
      );
    }
    final FarmWeather weather;
    try {
      weather = FarmWeather.fromJson(json, placeName: placeName);
    } on Object {
      throw const WeatherException(
        'The weather service returned data this app could not read.',
      );
    }
    _cache[cacheKey] = (DateTime.now(), weather);
    return weather;
  }

  /// GET https://geocoding-api.open-meteo.com/v1/search
  ///
  /// Powers the town search, so a farmer can check the weather over a buyer's
  /// municipality before promising a delivery date.
  Future<List<GeoPlace>> searchPlaces(String query, {int limit = 8}) async {
    final trimmed = query.trim();
    if (trimmed.length < 2) return const [];

    final uri = Uri.https(_geocodingHost, '/v1/search', {
      'name': trimmed,
      'count': '$limit',
      'language': 'en',
      'format': 'json',
    });

    final json = await _getJson(uri);
    // Open-Meteo omits "results" entirely when nothing matches.
    final results = json['results'] as List<dynamic>? ?? const [];
    return [
      for (final result in results)
        GeoPlace.fromJson(result as Map<String, dynamic>),
    ];
  }

  /// Shared request path: one GET, one JSON decode, and every failure mode
  /// turned into a message that means something on screen.
  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const WeatherException(
        'The weather service took too long to respond. Try again.',
      );
    } on SocketException {
      throw const WeatherException(
        'No internet connection. Check your network and try again.',
      );
    } on http.ClientException {
      throw const WeatherException(
        'Could not reach the weather service. Check your connection.',
      );
    }

    if (response.statusCode == 429) {
      throw const WeatherException(
        'Too many weather requests right now. Try again in a minute.',
      );
    }
    if (response.statusCode >= 500) {
      throw const WeatherException(
        'The weather service is temporarily unavailable.',
      );
    }
    if (response.statusCode != 200) {
      throw WeatherException(
        'Weather request failed (${response.statusCode}).',
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Expected a JSON object.');
      }
      return decoded;
    } on FormatException {
      throw const WeatherException(
        'The weather service returned an invalid response.',
      );
    }
  }
}
