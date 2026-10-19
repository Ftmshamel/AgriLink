import 'package:agrilink_mobile/services/geo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  // A straight road heading north, then east: farm at the start, buyer at
  // the end.
  const road = [
    LatLng(15.000, 120.000),
    LatLng(15.010, 120.000),
    LatLng(15.020, 120.000),
    LatLng(15.020, 120.010),
  ];

  test('the line starts at the rider and drops the road already driven', () {
    const rider = LatLng(15.015, 120.0001);
    final left = remainingRoute(road, rider);

    expect(left.points.first, rider);
    expect(left.points.last, road.last);
    expect(left.segment, 1);
    // The first two pins of the road are behind the rider and gone.
    expect(left.points, isNot(contains(road[0])));
    expect(left.points, isNot(contains(road[1])));
    expect(left.offRouteMeters, lessThan(20));
  });

  test('progress never jumps back to an earlier segment', () {
    // Out and back along the same road, as a farm pickup often is.
    const outAndBack = [
      LatLng(15.000, 120.000),
      LatLng(15.010, 120.000),
      LatLng(15.000, 120.000),
    ];
    const rider = LatLng(15.004, 120.000);
    final returning = remainingRoute(outAndBack, rider, fromSegment: 1);
    expect(returning.segment, 1);
    expect(returning.points.last, outAndBack.last);
  });

  test('a rider far from the road is reported off route', () {
    final left = remainingRoute(road, const LatLng(15.010, 120.005));
    expect(left.offRouteMeters, greaterThan(400));
  });
}
