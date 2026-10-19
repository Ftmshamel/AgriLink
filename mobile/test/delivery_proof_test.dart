import 'dart:typed_data';

import 'package:agrilink_mobile/models/agri_models.dart';
import 'package:agrilink_mobile/services/cloud_database.dart';
import 'package:agrilink_mobile/services/delivery_proof.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'order_flow_test.dart' show FakeFirestore;

AgriOrder _order(String id, {String code = '', String buyerId = 'buyer-1'}) =>
    AgriOrder.fromMap({
      'id': id,
      'buyerId': buyerId,
      'status': OrderStatus.inTransit.wire,
      if (code.isNotEmpty) 'deliveryCode': code,
    });

void main() {
  // Burgos Ave, Cabanatuan City.
  const drop = LatLng(15.4865, 120.9734);

  group('geofence', () {
    test('accepts a rider standing at the pin', () {
      final result = DeliveryProof.checkGeofence(
        rider: const LatLng(15.4866, 120.9735),
        drop: drop,
      );
      expect(result.allowed, isTrue);
      expect(result.distanceMetres, lessThan(20));
    });

    test('accepts a rider just inside the radius', () {
      // ~0.0004° of latitude is roughly 44 m.
      final result = DeliveryProof.checkGeofence(
        rider: const LatLng(15.4869, 120.9734),
        drop: drop,
      );
      expect(result.allowed, isTrue);
    });

    test('refuses a rider a block away', () {
      // ~0.0012° of latitude is roughly 133 m.
      final result = DeliveryProof.checkGeofence(
        rider: const LatLng(15.4877, 120.9734),
        drop: drop,
      );
      expect(result.allowed, isFalse);
    });

    test('refuses a rider a few hundred metres away', () {
      final result = DeliveryProof.checkGeofence(
        rider: const LatLng(15.4900, 120.9734),
        drop: drop,
      );
      expect(result.allowed, isFalse);
      expect(result.distanceMetres, greaterThan(DeliveryProof.geofenceMetres));
      expect(result.message, contains('Move within 50 m'));
    });

    test('refuses a rider in another town', () {
      // Gapan, Nueva Ecija.
      final result = DeliveryProof.checkGeofence(
        rider: const LatLng(15.3072, 120.9464),
        drop: drop,
      );
      expect(result.allowed, isFalse);
      expect(result.message, contains('km from the buyer'));
    });

    test('refuses a mocked GPS fix even when it claims to be at the pin', () {
      final result = DeliveryProof.checkGeofence(
        rider: drop,
        drop: drop,
        mocked: true,
      );
      expect(result.allowed, isFalse);
      expect(result.message, contains('mock-location'));
    });

    test('checks pickups against the farm pin', () {
      final result = DeliveryProof.checkGeofence(
        rider: const LatLng(15.4900, 120.9734),
        drop: drop,
        pickup: true,
      );
      expect(result.allowed, isFalse);
      expect(result.message, contains("the farm's pin"));
      expect(result.message, contains('confirm pickup'));
    });

    test('a mock location is flagged so it can never be overridden', () {
      final result =
          DeliveryProof.checkGeofence(rider: drop, drop: drop, mocked: true);
      expect(result.mocked, isTrue);
    });

    test('a rider stuck outside the pin may confirm after three minutes', () {
      final first = DateTime(2026, 10, 11, 9);
      expect(DeliveryProof.canOverride(null, first), isFalse);
      expect(
        DeliveryProof.canOverride(first, first.add(const Duration(minutes: 2))),
        isFalse,
      );
      expect(
        DeliveryProof.canOverride(first, first.add(const Duration(minutes: 3))),
        isTrue,
      );
      final overridden = DeliveryProof.overridden(420);
      expect(overridden.allowed, isTrue);
      expect(overridden.overridden, isTrue);
      expect(overridden.message, contains('420 m'));
      expect(DeliveryProof.overridden(null).message, contains('without a GPS'));
    });

    test('allows an unpinned buyer but records no distance', () {
      final result = DeliveryProof.checkGeofence(rider: drop, drop: null);
      expect(result.allowed, isTrue);
      expect(result.distanceMetres, isNull);
    });
  });

  group('delivery code', () {
    test('matches the code the buyer was shown', () {
      final orders = [_order('a', code: '4821'), _order('b', code: '4821')];
      expect(DeliveryProof.requiresCode(orders), isTrue);
      expect(DeliveryProof.codeMatches(orders, '4821'), isTrue);
      expect(DeliveryProof.codeMatches(orders, ' 4821 '), isTrue);
      expect(DeliveryProof.codeMatches(orders, '1234'), isFalse);
      expect(DeliveryProof.codeMatches(orders, ''), isFalse);
    });

    test('orders assigned before codes existed do not require one', () {
      final orders = [_order('legacy')];
      expect(DeliveryProof.requiresCode(orders), isFalse);
      expect(DeliveryProof.codeMatches(orders, ''), isTrue);
    });
  });

  group('database', () {
    late FakeFirestore fake;
    late CloudDatabase db;

    setUp(() {
      fake = FakeFirestore();
      db = CloudDatabase(client: fake.client);
    });

    Future<String> place(String buyerId, String address) => db.createOrder({
          'buyerId': buyerId,
          'buyerName': buyerId,
          'farmerId': 'farm-1',
          'farmerName': 'Green Valley Farm',
          'cropName': 'Red Onions',
          'quantityKg': 10,
          'deliveryAddress': address,
          'status': OrderStatus.readyForPickup.wire,
        });

    test('accepting a trip gives each drop-off its own four-digit code',
        () async {
      final first = await place('buyer-1', 'Burgos Ave, Cabanatuan City');
      final second = await place('buyer-1', 'Burgos Ave, Cabanatuan City');
      final other = await place('buyer-2', 'Maharlika Hwy, Cabanatuan City');

      final orders = [
        for (final id in [first, second, other]) (await db.getOrder(id))!,
      ];
      await db.acceptTrip(
        orders: orders,
        riderId: 'rider-1',
        riderName: 'Carlo Mendoza',
        riderPhone: '09173334444',
        riderVehicle: 'L300 Van',
        area: 'Cabanatuan City',
      );

      final a = (await db.getOrder(first))!;
      final b = (await db.getOrder(second))!;
      final c = (await db.getOrder(other))!;
      expect(a.deliveryCode, matches(RegExp(r'^\d{4}$')));
      expect(b.deliveryCode, a.deliveryCode,
          reason: 'one buyer at one address reads out a single code');
      expect(c.deliveryCode, matches(RegExp(r'^\d{4}$')));
    });

    test('a delivery proof is stored with its location and read back',
        () async {
      final orderId = await place('buyer-1', 'Burgos Ave, Cabanatuan City');
      final photo = Uint8List.fromList(List.generate(64, (i) => i));

      final proofId = await db.uploadDeliveryProof(
        orderIds: [orderId],
        riderId: 'rider-1',
        photo: photo,
        latitude: 15.4866,
        longitude: 120.9735,
        distanceMetres: 14.2,
      );
      final order = (await db.getOrder(orderId))!;
      await db.advanceOrder(
        orderId,
        OrderStatus.delivered,
        existingTimeline: order.timeline,
        extra: {
          'deliveryProofId': proofId,
          'deliveredDistanceMetres': 14.2,
          'deliveryCodeVerified': true,
        },
      );

      final proof = (await db.getDeliveryProof(proofId))!;
      expect(proof['riderId'], 'rider-1');
      expect(proof['orderIds'], [orderId]);
      expect(proof['photoBase64'], isNotEmpty);

      final delivered = (await db.getOrder(orderId))!;
      expect(delivered.deliveryProofId, proofId);
      expect(delivered.deliveredDistanceMetres, closeTo(14.2, 0.01));
      expect(delivered.deliveryCodeVerified, isTrue);
      expect(delivered.isReceiptConfirmed, isFalse);
    });

    test('a pickup photo is stored with its kind and override flag',
        () async {
      final proofId = await db.uploadDeliveryProof(
        orderIds: const ['order-1'],
        riderId: 'rider-1',
        photo: Uint8List.fromList(List.generate(16, (i) => i)),
        kind: 'pickup',
        outsidePin: true,
      );
      final proof = (await db.getDeliveryProof(proofId))!;
      expect(proof['kind'], 'pickup');
      expect(proof['outsidePin'], isTrue);
      expect(proof.containsKey('latitude'), isFalse,
          reason: 'no GPS fix means no position is invented');
    });

    test('an oversized delivery photo is refused', () async {
      expect(
        () => db.uploadDeliveryProof(
          orderIds: const ['order-1'],
          riderId: 'rider-1',
          photo: Uint8List(750001),
          latitude: 0,
          longitude: 0,
        ),
        throwsException,
      );
    });

    test('the buyer can confirm receipt or dispute the delivery', () async {
      final kept = await place('buyer-1', 'Burgos Ave, Cabanatuan City');
      final contested = await place('buyer-2', 'Maharlika Hwy, Cabanatuan');

      await db.confirmReceived(kept);
      await db.markDeliveryDisputed(contested);

      final confirmed = (await db.getOrder(kept))!;
      expect(confirmed.isReceiptConfirmed, isTrue);
      expect(confirmed.isDisputed, isFalse);

      final disputed = (await db.getOrder(contested))!;
      expect(disputed.isDisputed, isTrue);
      expect(disputed.isReceiptConfirmed, isFalse);
    });
  });
}
