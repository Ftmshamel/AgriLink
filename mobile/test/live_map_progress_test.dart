import 'package:agrilink_mobile/services/geo.dart';
import 'package:agrilink_mobile/widgets/live_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

/// Rider → farm → buyer along one north-running road, 2.2 km and 10 min.
const _routeBody = '''
{"code":"Ok","routes":[{"distance":2224,"duration":600,"geometry":{
  "coordinates":[[120.0,15.0],[120.0,15.01],[120.0,15.02]]}}]}
''';

const _rider = LatLng(15.0, 120.0);
const _farm = LatLng(15.01, 120.0);
const _buyer = LatLng(15.02, 120.0);

Widget _map({LatLng? rider, void Function(RouteProgress)? onProgress}) =>
    MaterialApp(
      home: Scaffold(
        body: LiveRouteMap(
          stops: const [
            MapStop(
                point: _farm,
                label: 'Farm',
                icon: Icons.agriculture,
                color: Colors.orange),
            MapStop(
                point: _buyer,
                label: 'Buyer',
                icon: Icons.store,
                color: Colors.green),
          ],
          riderPoint: rider,
          showControls: false,
          onProgress: onProgress,
        ),
      ),
    );

void main() {
  setUp(() {
    RouteService.clearCache();
    RouteService.client =
        MockClient((_) async => http.Response(_routeBody, 200));
  });
  tearDown(() => RouteService.client = http.Client());

  testWidgets('distance and ETA count down as the rider moves',
      (tester) async {
    RouteProgress? progress;
    await tester.pumpWidget(
        _map(rider: _rider, onProgress: (value) => progress = value));
    await tester.pumpAndSettle();

    expect(progress!.left.distanceKm, closeTo(2.2, 0.1));
    expect(progress!.toNextStop.distanceKm, closeTo(1.1, 0.1));
    expect(progress!.left.duration.inSeconds, closeTo(600, 5));
    expect(find.textContaining('2.2 km •'), findsOneWidget);

    // Halfway: at the farm.
    await tester.pumpWidget(
        _map(rider: _farm, onProgress: (value) => progress = value));
    await tester.pumpAndSettle();

    expect(progress!.left.distanceKm, closeTo(1.1, 0.1));
    expect(progress!.left.duration.inSeconds, closeTo(300, 5));
    expect(progress!.toNextStop.distanceKm, lessThan(0.05));
    expect(find.textContaining('1.1 km •'), findsOneWidget);
  });

  testWidgets('the vehicle leaves the map when the trip is over',
      (tester) async {
    await tester.pumpWidget(_map(rider: _rider));
    await tester.pumpAndSettle();
    expect(find.byType(RiderNavigationMarker), findsOneWidget);

    await tester.pumpWidget(_map());
    await tester.pumpAndSettle();
    expect(find.byType(RiderNavigationMarker), findsNothing);
  });

  testWidgets('the full-screen button only shows when the page offers one',
      (tester) async {
    await tester.pumpWidget(_map(rider: _rider));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.fullscreen), findsNothing);

    var opened = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LiveRouteMap(
          stops: const [
            MapStop(
                point: _buyer,
                label: 'Buyer',
                icon: Icons.store,
                color: Colors.green),
          ],
          riderPoint: _rider,
          onExpand: () => opened = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.fullscreen));
    expect(opened, isTrue);
  });

  testWidgets('heading-up maps get a compass button to switch to north-up',
      (tester) async {
    Widget map({required bool headingUp}) => MaterialApp(
          home: Scaffold(
            body: LiveRouteMap(
              stops: const [
                MapStop(
                    point: _buyer,
                    label: 'Buyer',
                    icon: Icons.store,
                    color: Colors.green),
              ],
              riderPoint: _rider,
              headingUp: headingUp,
            ),
          ),
        );
    await tester.pumpWidget(map(headingUp: false));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.navigation), findsNothing);

    await tester.pumpWidget(map(headingUp: true));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.navigation));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.explore), findsOneWidget);
  });

  test('path length adds up each leg', () {
    expect(pathKm(const [_rider, _farm, _buyer]), closeTo(2.2, 0.1));
    expect(pathKm(const [_rider]), 0);
  });
}
