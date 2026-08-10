import 'dart:convert';

import 'package:agrilink_mobile/models/weather.dart';
import 'package:agrilink_mobile/services/weather_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Trimmed copy of a real Open-Meteo forecast response.
const _forecastBody = '''
{
  "latitude": 15.5,
  "longitude": 121.0,
  "timezone": "Asia/Manila",
  "current": {
    "time": "2026-08-10T14:00",
    "temperature_2m": 31.2,
    "relative_humidity_2m": 78,
    "apparent_temperature": 37.1,
    "precipitation": 0.0,
    "weather_code": 2,
    "wind_speed_10m": 11.5
  },
  "daily": {
    "time": ["2026-08-10", "2026-08-11", "2026-08-12"],
    "weather_code": [2, 80, 95],
    "temperature_2m_max": [32.4, 30.1, 29.6],
    "temperature_2m_min": [25.1, 24.8, 24.3],
    "precipitation_probability_max": [20, 75, 90],
    "precipitation_sum": [0.0, 4.2, 18.6]
  }
}
''';

const _geocodingBody = '''
{
  "results": [
    {
      "id": 1729564,
      "name": "Cabanatuan City",
      "latitude": 15.4864,
      "longitude": 120.9673,
      "country": "Philippines",
      "admin1": "Nueva Ecija"
    }
  ]
}
''';

WeatherService _serviceReturning(
  String body, {
  int status = 200,
  void Function(Uri uri)? onRequest,
}) {
  return WeatherService(
    client: MockClient((request) async {
      onRequest?.call(request.url);
      return http.Response(
        body,
        status,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

void main() {
  group('forecast endpoint', () {
    test('parses current conditions and the daily outlook', () async {
      Uri? requested;
      final service = _serviceReturning(
        _forecastBody,
        onRequest: (uri) => requested = uri,
      );

      final weather = await service.loadForecast(
        latitude: 15.4865,
        longitude: 120.9734,
        placeName: 'Cabanatuan, Nueva Ecija',
      );

      expect(requested!.host, 'api.open-meteo.com');
      expect(requested!.path, '/v1/forecast');
      expect(requested!.queryParameters['latitude'], '15.4865');
      expect(requested!.queryParameters['timezone'], 'auto');

      expect(weather.placeName, 'Cabanatuan, Nueva Ecija');
      expect(weather.temperature, 31.2);
      expect(weather.humidity, 78);
      expect(weather.windKph, 11.5);
      expect(weather.condition.label, 'Partly cloudy');
      expect(weather.daily, hasLength(3));
      expect(weather.daily[1].condition.label, 'Rain showers');
      expect(weather.daily[2].condition.severe, isTrue);
      // Worst rain chance across the next three days.
      expect(weather.rainChanceSoon, 90);
    });

    test('reads a missing payload as an unusable response', () async {
      final service = _serviceReturning('{"latitude": 15.5}');
      await expectLater(
        service.loadForecast(latitude: 15.5, longitude: 121),
        throwsA(isA<WeatherException>()),
      );
    });

    test('reports malformed JSON instead of crashing', () async {
      final service = _serviceReturning('<html>gateway error</html>');
      await expectLater(
        service.loadForecast(latitude: 15.5, longitude: 121),
        throwsA(
          isA<WeatherException>().having(
            (error) => error.message,
            'message',
            contains('invalid response'),
          ),
        ),
      );
    });

    test('explains an unavailable service', () async {
      final service = _serviceReturning('{}', status: 503);
      await expectLater(
        service.loadForecast(latitude: 15.5, longitude: 121),
        throwsA(
          isA<WeatherException>().having(
            (error) => error.message,
            'message',
            contains('temporarily unavailable'),
          ),
        ),
      );
    });

    test('explains a dropped connection', () async {
      final service = WeatherService(
        client: MockClient((_) async => throw http.ClientException('failed')),
      );
      await expectLater(
        service.loadForecast(latitude: 15.5, longitude: 121),
        throwsA(
          isA<WeatherException>().having(
            (error) => error.message,
            'message',
            contains('Check your connection'),
          ),
        ),
      );
    });
  });

  group('caching', () {
    test('repeat lookups are served without a second request', () async {
      var calls = 0;
      final service = _serviceReturning(
        _forecastBody,
        onRequest: (_) => calls++,
      );

      await service.loadForecast(latitude: 15.5, longitude: 121);
      await service.loadForecast(latitude: 15.5, longitude: 121);
      expect(calls, 1);

      // A different pin is a different lookup.
      await service.loadForecast(latitude: 14.6, longitude: 121);
      expect(calls, 2);

      // And the refresh button forces a real request again.
      service.clearCache();
      await service.loadForecast(latitude: 15.5, longitude: 121);
      expect(calls, 3);
    });
  });

  group('geocoding endpoint', () {
    test('parses search results', () async {
      Uri? requested;
      final service = _serviceReturning(
        _geocodingBody,
        onRequest: (uri) => requested = uri,
      );

      final places = await service.searchPlaces('Cabanatuan');

      expect(requested!.host, 'geocoding-api.open-meteo.com');
      expect(requested!.queryParameters['name'], 'Cabanatuan');
      expect(places, hasLength(1));
      expect(places.single.label, 'Cabanatuan City, Nueva Ecija');
      expect(places.single.latitude, 15.4864);
    });

    test('treats an omitted results key as no matches', () async {
      final service = _serviceReturning('{"generationtime_ms": 0.5}');
      expect(await service.searchPlaces('Zzzzzz'), isEmpty);
    });

    test('does not call the API for a one-letter query', () async {
      var called = false;
      final service = _serviceReturning(
        _geocodingBody,
        onRequest: (_) => called = true,
      );
      expect(await service.searchPlaces('C'), isEmpty);
      expect(called, isFalse);
    });
  });

  group('advisories', () {
    FarmWeather weatherWith({required int code, required int rainChance}) {
      final body = jsonDecode(_forecastBody) as Map<String, dynamic>;
      body['current']['weather_code'] = code;
      body['daily']['precipitation_probability_max'] = [rainChance, 0, 0];
      return FarmWeather.fromJson(body, placeName: 'Test farm');
    }

    test('warns farmers and riders during a storm', () {
      final storm = weatherWith(code: 95, rainChance: 90);
      expect(storm.harvestAdvice, contains('Hold off on harvesting'));
      expect(storm.deliveryAdvice, contains('Avoid accepting trips'));
    });

    test('tells farmers to harvest early ahead of rain', () {
      final incoming = weatherWith(code: 2, rainChance: 75);
      expect(incoming.harvestAdvice, contains('Harvest and list your crops early'));
      expect(incoming.deliveryAdvice, contains('tarpaulin'));
    });

    test('clears both roles on a fair day', () {
      final fair = weatherWith(code: 0, rainChance: 10);
      expect(fair.harvestAdvice, contains('Good harvest window'));
      expect(fair.deliveryAdvice, contains('Clear roads'));
    });
  });
}
