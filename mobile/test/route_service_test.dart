import 'dart:async';
import 'dart:io';

import 'package:agrilink_mobile/services/geo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

/// Trimmed copy of a real OSRM response (S&R Farm → Cabanatuan).
const _routeBody = '''
{
  "code": "Ok",
  "routes": [{
    "distance": 49426,
    "duration": 2893.8,
    "geometry": {
      "coordinates": [
        [120.941396, 15.079411],
        [120.950000, 15.200000],
        [120.967269, 15.486488]
      ]
    }
  }],
  "waypoints": [
    {"location": [120.941396, 15.079411], "name": ""},
    {"location": [120.967269, 15.486488], "name": "General Tinio Street"}
  ]
}
''';

/// Two points far enough apart that a straight line is clearly not the road.
const _farm = LatLng(15.0794, 120.9414);
const _buyer = LatLng(15.4864, 120.9673);

void main() {
  setUp(RouteService.clearCache);
  tearDown(() => RouteService.client = http.Client());

  void respondWith(http.Response Function() build) {
    RouteService.client = MockClient((_) async => build());
  }

  test('parses distance, duration, and the road geometry', () async {
    Uri? requested;
    RouteService.client = MockClient((request) async {
      requested = request.url;
      return http.Response(_routeBody, 200);
    });

    final route = await RouteService.route([_farm, _buyer]);

    expect(requested!.host, 'router.project-osrm.org');
    // OSRM takes longitude first, so the path must carry lon,lat pairs.
    expect(requested!.path, contains('120.9414,15.0794'));
    expect(requested!.queryParameters['geometries'], 'geojson');

    expect(route.isEstimate, isFalse);
    expect(route.failure, isNull);
    expect(route.distanceKm, closeTo(49.4, 0.1));
    expect(route.duration.inMinutes, 48);
    expect(route.distanceLabel, '49 km');
    expect(route.etaLabel, '48 min');

    // [lon, lat] from OSRM must come back as [lat, lng] for the map.
    expect(route.points.first.latitude, closeTo(15.0794, 0.001));
    expect(route.points.first.longitude, closeTo(120.9414, 0.001));
  });

  test('a repeat lookup is served from cache', () async {
    var calls = 0;
    RouteService.client = MockClient((_) async {
      calls++;
      return http.Response(_routeBody, 200);
    });

    await RouteService.route([_farm, _buyer]);
    await RouteService.route([_farm, _buyer]);
    expect(calls, 1);
    expect(RouteService.cached([_farm, _buyer]), isNotNull);
  });

  group('error handling falls back to a usable estimate', () {
    test('connection issue', () async {
      respondWith(() => throw const SocketException('no route to host'));
      final route = await RouteService.route([_farm, _buyer]);

      expect(route.failure, RouteFailure.connection);
      expect(route.isEstimate, isTrue);
      // The rider still gets a distance rather than an error.
      expect(route.distanceKm, greaterThan(0));
      expect(route.duration.inMinutes, greaterThan(0));
    });

    test('dropped client connection', () async {
      respondWith(() => throw http.ClientException('connection closed'));
      final route = await RouteService.route([_farm, _buyer]);
      expect(route.failure, RouteFailure.connection);
    });

    test('timeout', () async {
      RouteService.client = MockClient((_) async {
        throw TimeoutException('too slow');
      });
      final route = await RouteService.route([_farm, _buyer]);
      expect(route.failure, RouteFailure.timeout);
      expect(route.isEstimate, isTrue);
    });

    test('service unavailable', () async {
      respondWith(() => http.Response('{}', 503));
      final route = await RouteService.route([_farm, _buyer]);
      expect(route.failure, RouteFailure.unavailable);
    });

    test('rate limited', () async {
      respondWith(() => http.Response('{}', 429));
      final route = await RouteService.route([_farm, _buyer]);
      expect(route.failure, RouteFailure.unavailable);
    });

    test('no route between the points', () async {
      respondWith(
        () => http.Response('{"code":"NoRoute","routes":[]}', 200),
      );
      final route = await RouteService.route([_farm, _buyer]);
      expect(route.failure, RouteFailure.unavailable);
    });

    test('invalid response — an HTML error page where JSON was expected',
        () async {
      respondWith(() => http.Response('<html>502 Bad Gateway</html>', 200));
      final route = await RouteService.route([_farm, _buyer]);
      expect(route.failure, RouteFailure.invalidResponse);
      expect(route.isEstimate, isTrue);
    });

    test('valid JSON in an unexpected shape', () async {
      respondWith(() => http.Response('{"routes":[{"distance":1}]}', 200));
      final route = await RouteService.route([_farm, _buyer]);
      expect(route.failure, RouteFailure.invalidResponse);
    });

    test('a failed route is never cached', () async {
      respondWith(() => http.Response('{}', 503));
      await RouteService.route([_farm, _buyer]);
      expect(RouteService.cached([_farm, _buyer]), isNull);
    });
  });

  test('a single stop is not routed at all', () async {
    var called = false;
    RouteService.client = MockClient((_) async {
      called = true;
      return http.Response(_routeBody, 200);
    });

    final route = await RouteService.route([_farm]);
    expect(called, isFalse);
    expect(route.failure, RouteFailure.notEnoughStops);
    expect(route.distanceKm, 0);
  });
}
