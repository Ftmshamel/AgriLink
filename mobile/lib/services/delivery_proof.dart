import 'package:latlong2/latlong.dart';

import '../models/agri_models.dart';

/// The rules a rider has to satisfy before a drop-off counts as delivered.
///
/// Kept free of Flutter and GPS plumbing so the decisions themselves can be
/// unit tested: the trip screen gathers the inputs, this says yes or no.
class DeliveryProof {
  /// How close to the buyer's pin the rider must be. Phone GPS is usually
  /// good to 5–30 m outdoors, and a pin dropped on a map is rarely on the exact
  /// gate, so 150 m allows for both without accepting "same street, wrong
  /// barangay".
  static const geofenceMetres = 150.0;

  static const codeLength = 4;

  /// Checks the rider's position against the drop-off pin.
  ///
  /// [drop] is null for buyers who never pinned a location; there is nothing
  /// to measure against, so the stop is allowed and recorded as unpinned.
  static GeofenceResult checkGeofence({
    required LatLng rider,
    required LatLng? drop,
    bool mocked = false,
  }) {
    if (mocked) {
      return const GeofenceResult(
        allowed: false,
        distanceMetres: null,
        message: 'A mock-location app is active. Turn it off to confirm '
            'delivery.',
      );
    }
    if (drop == null) {
      return const GeofenceResult(
        allowed: true,
        distanceMetres: null,
        message: 'This buyer has no pinned location.',
      );
    }
    final metres = const Distance().as(LengthUnit.Meter, rider, drop);
    if (metres > geofenceMetres) {
      return GeofenceResult(
        allowed: false,
        distanceMetres: metres,
        message: 'You are ${formatMetres(metres)} from the buyer\'s pin. '
            'Move within ${geofenceMetres.round()} m to confirm delivery.',
      );
    }
    return GeofenceResult(
      allowed: true,
      distanceMetres: metres,
      message: 'At the drop-off (${formatMetres(metres)} from the pin).',
    );
  }

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
  });

  final bool allowed;

  /// Null when there was no pin to measure against or the fix was rejected.
  final double? distanceMetres;
  final String message;
}
