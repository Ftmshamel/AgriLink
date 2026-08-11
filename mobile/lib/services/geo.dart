import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Device location, with the permission dance in one place so every screen
/// reports the same, translatable errors instead of silently doing nothing.
class GeoService {
  static const _highAccuracy = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 10,
  );

  /// Throws with a user-facing message when location cannot be used.
  static Future<void> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Turn on your phone Location/GPS first.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      throw Exception('Location permission is needed to continue.');
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission is blocked. Enable it in App Settings.',
      );
    }
  }

  static LatLng? _lastPoint;
  static DateTime? _lastFix;

  /// Screens poll every few seconds; re-reading the GPS that often drains the
  /// battery for no benefit, so a recent fix is reused.
  static const _fixTtl = Duration(seconds: 45);

  static Future<LatLng> currentPoint({bool allowCached = true}) async {
    final cached = _lastPoint;
    if (allowCached &&
        cached != null &&
        _lastFix != null &&
        DateTime.now().difference(_lastFix!) < _fixTtl) {
      return cached;
    }
    await ensurePermission();
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 25),
      ),
    );
    return _remember(LatLng(position.latitude, position.longitude));
  }

  static DateTime? _retryAfter;

  /// Best-effort position that returns null instead of throwing, for screens
  /// that only use location to sort results.
  ///
  /// Live screens call this on every poll, so a refusal is remembered for a
  /// while — otherwise a rider who denied the permission would be re-prompted
  /// every few seconds.
  static Future<LatLng?> tryCurrentPoint() async {
    if (_retryAfter != null && DateTime.now().isBefore(_retryAfter!)) {
      return _lastPoint;
    }
    try {
      final point = await currentPoint();
      _retryAfter = null;
      return point;
    } catch (_) {
      _retryAfter = DateTime.now().add(const Duration(minutes: 2));
      return _lastPoint;
    }
  }

  static LatLng _remember(LatLng point) {
    _lastPoint = point;
    _lastFix = DateTime.now();
    return point;
  }

  static Stream<Position> watch() =>
      Geolocator.getPositionStream(locationSettings: _highAccuracy).map(
        (position) {
          _remember(LatLng(position.latitude, position.longitude));
          return position;
        },
      );

  static double distanceKm(LatLng from, LatLng to) =>
      const Distance().as(LengthUnit.Kilometer, from, to).toDouble();
}

/// Why a route fell back to a straight line instead of real road data.
enum RouteFailure {
  /// The device could not reach the routing server at all.
  connection('No connection to the routing service.'),

  /// The server accepted the request but took too long.
  timeout('The routing service took too long to respond.'),

  /// The server answered, but not with a usable route (5xx, 429, no route).
  unavailable('The routing service is unavailable right now.'),

  /// The body was not the JSON this app knows how to read.
  invalidResponse('The routing service returned an unreadable response.'),

  /// Fewer than two usable waypoints — nothing to route between.
  notEnoughStops('Not enough stops to build a route.');

  const RouteFailure(this.message);
  final String message;
}

/// A driving route returned by OSRM, or a straight-line fallback.
class RoutePath {
  const RoutePath({
    required this.points,
    required this.distanceKm,
    required this.duration,
    required this.isEstimate,
    this.failure,
  });

  final List<LatLng> points;
  final double distanceKm;
  final Duration duration;

  /// True when routing was unavailable and this is a straight-line guess.
  final bool isEstimate;

  /// Set only on a fallback, naming which failure caused it.
  final RouteFailure? failure;

  String get distanceLabel => formatKm(distanceKm);
  String get etaLabel => formatDuration(duration);
}

/// Public OSRM routing, used for the rider's road route and delivery ETAs.
class RouteService {
  static final _cache = <String, RoutePath>{};

  /// Swappable so tests can drive the failure paths without a network.
  static http.Client client = http.Client();

  static void clearCache() => _cache.clear();

  static String _keyFor(List<LatLng> waypoints) => waypoints
      .map((point) =>
          '${point.latitude.toStringAsFixed(4)},${point.longitude.toStringAsFixed(4)}')
      .join(';');

  /// The already-resolved route for [stops], or null if it has not been
  /// fetched yet. Lets a list paint a real distance without awaiting.
  static RoutePath? cached(List<LatLng> stops) {
    final waypoints = stops.where((point) => point.latitude != 0).toList();
    if (waypoints.length < 2) return null;
    return _cache[_keyFor(waypoints)];
  }

  static Future<RoutePath> route(List<LatLng> stops) async {
    final waypoints = stops.where((point) => point.latitude != 0).toList();
    if (waypoints.length < 2) {
      return const RoutePath(
        points: [],
        distanceKm: 0,
        duration: Duration.zero,
        isEstimate: true,
        failure: RouteFailure.notEnoughStops,
      );
    }
    final key = _keyFor(waypoints);
    final cached = _cache[key];
    if (cached != null) return cached;

    final coordinates = waypoints
        .map((point) => '${point.longitude},${point.latitude}')
        .join(';');
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/$coordinates'
      '?overview=full&geometries=geojson',
    );
    // Each failure mode is caught separately so the app can say which one
    // happened; they all degrade to the same straight-line estimate, because a
    // rider must never be blocked from seeing a distance.
    final http.Response response;
    try {
      response = await client.get(
        uri,
        headers: const {'User-Agent': 'AgriLinkMobile/1.0'},
      ).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      return _straightLine(waypoints, RouteFailure.timeout);
    } on SocketException {
      return _straightLine(waypoints, RouteFailure.connection);
    } on http.ClientException {
      return _straightLine(waypoints, RouteFailure.connection);
    }

    if (response.statusCode != 200) {
      return _straightLine(waypoints, RouteFailure.unavailable);
    }

    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = payload['routes'] as List<dynamic>? ?? const [];
      if (routes.isEmpty) {
        return _straightLine(waypoints, RouteFailure.unavailable);
      }
      final first = routes.first as Map<String, dynamic>;
      final geometry = first['geometry'] as Map<String, dynamic>;
      final coordinateList = geometry['coordinates'] as List<dynamic>;
      final path = RoutePath(
        // OSRM returns [longitude, latitude] — the reverse of latlong2 — so
        // every pair is flipped here.
        points: coordinateList.map((value) {
          final pair = value as List<dynamic>;
          return LatLng(
            (pair[1] as num).toDouble(),
            (pair[0] as num).toDouble(),
          );
        }).toList(),
        distanceKm: ((first['distance'] as num?)?.toDouble() ?? 0) / 1000,
        duration: Duration(
          seconds: ((first['duration'] as num?)?.round() ?? 0),
        ),
        isEstimate: false,
      );
      _cache[key] = path;
      return path;
    } on Object {
      // Not JSON, or JSON in a shape this app cannot read.
      return _straightLine(waypoints, RouteFailure.invalidResponse);
    }
  }

  static RoutePath _straightLine(List<LatLng> stops, [RouteFailure? failure]) {
    var distance = 0.0;
    for (var index = 0; index < stops.length - 1; index++) {
      distance += GeoService.distanceKm(stops[index], stops[index + 1]);
    }
    return RoutePath(
      points: stops,
      distanceKm: distance,
      // Roughly 28 km/h average on provincial roads with stops.
      duration: Duration(minutes: (distance / 28 * 60).round()),
      isEstimate: true,
      failure: failure,
    );
  }
}

String formatKm(double km) {
  if (km <= 0) return '—';
  if (km < 1) return '${(km * 1000).round()} m';
  return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
}

String formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes <= 0) return '—';
  if (minutes < 60) return '$minutes min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${rest}m';
}

String formatPeso(num value) {
  final rounded = value.round();
  final digits = rounded.abs().toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(',');
    buffer.write(digits[index]);
  }
  return '${rounded < 0 ? '-' : ''}₱$buffer';
}

String formatClock(DateTime time) {
  final local = time.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour < 12 ? 'AM' : 'PM'}';
}

String formatRelativeDay(DateTime time) {
  final local = time.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(local.year, local.month, local.day);
  final difference = today.difference(that).inDays;
  if (difference == 0) return 'Today';
  if (difference == 1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[local.month - 1]} ${local.day.toString().padLeft(2, '0')}';
}
