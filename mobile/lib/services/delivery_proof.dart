import 'package:latlong2/latlong.dart';

import '../models/agri_models.dart';

/// The rules a rider has to satisfy before a drop-off counts as delivered.
///
/// Kept free of Flutter and GPS plumbing so the decisions themselves can be
/// unit tested: the trip screen gathers the inputs, this says yes or no.
class DeliveryProof {
  /// How close to the buyer's pin the rider must be. Phone GPS is usually
  /// good to 5–30 m outdoors, and a pin dropped on a map is rarely on the exact
  /// gate, so 50 m leaves room for both while still meaning "at the door",
  /// not "down the street".
  static const geofenceMetres = 50.0;

  static const codeLength = 4;

  /// Farms and rural drop-offs can leave a phone stuck on a bad fix. Once a
  /// rider has been refused at a stop for this long, they may confirm anyway;
  /// the stop is then marked as confirmed outside the pin for the buyer, the
  /// farm and support to see. A mock location is never overridden.
  static const gpsOverrideAfter = Duration(minutes: 3);

  /// Checks the rider's position against the stop's pin: the buyer's for a
  /// drop-off, the farm's when [pickup].
  ///
  /// [drop] is null for stops with no pinned location; there is nothing to
  /// measure against, so the stop is allowed and recorded as unpinned.
  static GeofenceResult checkGeofence({
    required LatLng rider,
    required LatLng? drop,
    bool mocked = false,
    bool pickup = false,
  }) {
    final what = pickup ? 'pickup' : 'delivery';
    final whose = pickup ? 'the farm\'s' : 'the buyer\'s';
    if (mocked) {
      return GeofenceResult(
        allowed: false,
        distanceMetres: null,
        mocked: true,
        message: 'A mock-location app is active. Turn it off to confirm '
            '$what.',
      );
    }
    if (drop == null) {
      return GeofenceResult(
        allowed: true,
        distanceMetres: null,
        message: 'This ${pickup ? 'farm' : 'buyer'} has no pinned location.',
      );
    }
    final metres = const Distance().as(LengthUnit.Meter, rider, drop);
    if (metres > geofenceMetres) {
      return GeofenceResult(
        allowed: false,
        distanceMetres: metres,
        message: 'You are ${formatMetres(metres)} from $whose pin. '
            'Move within ${geofenceMetres.round()} m to confirm $what.',
      );
    }
    return GeofenceResult(
      allowed: true,
      distanceMetres: metres,
      message: 'At the ${pickup ? 'farm' : 'drop-off'} '
          '(${formatMetres(metres)} from the pin).',
    );
  }

  /// Whether a rider first refused at [firstMiss] may now confirm anyway.
  static bool canOverride(DateTime? firstMiss, DateTime now) =>
      firstMiss != null && now.difference(firstMiss) >= gpsOverrideAfter;

  /// The result recorded when a rider confirms outside the pin after
  /// [gpsOverrideAfter]; [distanceMetres] is null when there was no fix at all.
  static GeofenceResult overridden(double? distanceMetres) => GeofenceResult(
        allowed: true,
        overridden: true,
        distanceMetres: distanceMetres,
        message: distanceMetres == null
            ? 'Confirmed without a GPS fix.'
            : 'Confirmed ${formatMetres(distanceMetres)} from the pin after '
                'GPS kept failing.',
      );

  /// The codes the buyer at this stop may read out. Every order a buyer has on
  /// one trip shares a code, so this is normally a single value.
  static Set<String> expectedCodes(Iterable<AgriOrder> orders) => {
        for (final order in orders)
          if (order.deliveryCode.isNotEmpty) order.deliveryCode,
      };

  /// Orders assigned before delivery codes existed carry none; for those the
  /// geofence and photo are the only proof.
  static bool requiresCode(Iterable<AgriOrder> orders) =>
      expectedCodes(orders).isNotEmpty;

  static bool codeMatches(Iterable<AgriOrder> orders, String entered) {
    final expected = expectedCodes(orders);
    if (expected.isEmpty) return true;
    return expected.contains(entered.trim());
  }

  static String formatMetres(double metres) => metres >= 1000
      ? '${(metres / 1000).toStringAsFixed(1)} km'
      : '${metres.round()} m';
}

class GeofenceResult {
  const GeofenceResult({
    required this.allowed,
    required this.distanceMetres,
    required this.message,
    this.mocked = false,
    this.overridden = false,
  });

  final bool allowed;

  /// Refused because of a mock-location app; never overridable.
  final bool mocked;

  /// Allowed outside the pin after [DeliveryProof.gpsOverrideAfter].
  final bool overridden;

  /// Null when there was no pin to measure against or the fix was rejected.
  final double? distanceMetres;
  final String message;
}
