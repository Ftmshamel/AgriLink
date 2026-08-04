import 'dart:convert';

import 'package:agrilink_mobile/models/agri_models.dart';
import 'package:agrilink_mobile/screens/rider_screens.dart';
import 'package:agrilink_mobile/services/cloud_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// In-memory stand-in for the Firestore REST API, speaking the same
/// documents/fields wire format [CloudDatabase] encodes and decodes.
class FakeFirestore {
  final Map<String, Map<String, Map<String, dynamic>>> collections = {};

  /// Firestore replies as UTF-8; without the charset `http.Response` falls
  /// back to latin1 and non-ASCII names like "Maria’s Kitchen" blow up.
  static http.Response _json(Object payload, [int status = 200]) =>
      http.Response(
        jsonEncode(payload),
        status,
        headers: const {'content-type': 'application/json; charset=utf-8'},
      );

  http.Client get client => MockClient((request) async {
        final tail = request.url.path.split('/documents/').last;
        final segments = tail.split('/');
        final collection = segments.first;
        final id = segments.length > 1 ? segments[1] : null;
        final store = collections.putIfAbsent(collection, () => {});

        switch (request.method) {
          case 'POST':
            final documentId = request.url.queryParameters['documentId']!;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            store[documentId] =
                Map<String, dynamic>.from(body['fields'] as Map);
            return _json({
              'name': 'projects/p/databases/(default)/documents/'
                  '$collection/$documentId',
              'fields': store[documentId],
            });

          case 'PATCH':
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            final existing = store[id!] ?? <String, dynamic>{};
            existing.addAll(Map<String, dynamic>.from(body['fields'] as Map));
            store[id] = existing;
            return _json({'fields': existing});

          case 'DELETE':
            store.remove(id);
            return _json(const {});

          case 'GET':
            if (id != null) {
              final document = store[id];
              if (document == null) return _json(const {}, 404);
              return _json({
                'name': 'projects/p/databases/(default)/documents/'
                    '$collection/$id',
                'fields': document,
              });
            }
            return _json({
              'documents': store.entries
                  .map((entry) => {
                        'name': 'projects/p/databases/(default)/documents/'
                            '$collection/${entry.key}',
                        'fields': entry.value,
                      })
                  .toList(),
            });

          default:
            return _json(const {}, 405);
        }
      });
}

void main() {
  late FakeFirestore fake;
  late CloudDatabase db;

  setUp(() {
    fake = FakeFirestore();
    db = CloudDatabase(client: fake.client);
  });

  Future<String> publishCrop({
    String farmerId = 'farm-1',
    String name = 'Red Onions',
    int quantity = 300,
  }) =>
      db.createCrop({
        'farmerId': farmerId,
        'farmerName': 'Green Valley Farm',
        'farmerPhone': '09170000001',
        'name': name,
        'category': 'Vegetables',
        'quantityKg': quantity,
        'pricePerKg': 75,
        'moqKg': 10,
        'farmLocation': 'Brgy. Esguerra, Talavera, Nueva Ecija',
        'farmLatitude': 15.5883,
        'farmLongitude': 120.9192,
        'status': 'active',
      });

  Future<String> placeOrder({
    String cropId = 'crop-1',
    String farmerId = 'farm-1',
    String buyerId = 'buyer-1',
    String buyerName = 'Maria’s Kitchen',
    String address = 'Burgos Ave, Brgy. Zulueta, Cabanatuan City',
    int quantity = 20,
  }) =>
      db.createOrder({
        'buyerId': buyerId,
        'buyerName': buyerName,
        'buyerPhone': '09171112222',
        'farmerId': farmerId,
        'farmerName': 'Green Valley Farm',
        'farmerPhone': '09170000001',
        'cropId': cropId,
        'cropName': 'Red Onions',
        'quantityKg': quantity,
        'pricePerKg': 75,
        'totalPrice': quantity * 75,
        'deliveryFee': 140,
        'deliveryAddress': address,
        'deliveryLatitude': 15.4865,
        'deliveryLongitude': 120.9734,
        'farmLocation': 'Brgy. Esguerra, Talavera, Nueva Ecija',
        'farmLatitude': 15.5883,
        'farmLongitude': 120.9192,
        'paymentMethod': 'GCash',
        'status': OrderStatus.placed.wire,
      });

  test('an order travels from consumer to farmer to rider to delivered',
      () async {
    final cropId = await publishCrop();

    // Consumer checks out.
    final orderId = await placeOrder(cropId: cropId);
    await db.reduceCropStock(cropId, 20);

    var order = (await db.getOrder(orderId))!;
    expect(order.status, OrderStatus.placed);
    expect(order.reference, startsWith('#AG-'));
    expect(order.timeline.containsKey(OrderStatus.placed.wire), isTrue);

    final crops = await db.listCropListings(farmerId: 'farm-1');
    expect(crops.single.quantityKg, 280,
        reason: 'checkout should reserve stock so the farm cannot oversell');

    // The order is not offered to riders until the farm packs it.
    expect(
      (await db.listAgriOrders())
          .where((o) => o.status == OrderStatus.readyForPickup),
      isEmpty,
    );

    // Farmer confirms, then marks it packed.
    await db.advanceOrder(orderId, OrderStatus.preparing,
        existingTimeline: order.timeline);
    order = (await db.getOrder(orderId))!;
    await db.advanceOrder(orderId, OrderStatus.readyForPickup,
        existingTimeline: order.timeline);

    order = (await db.getOrder(orderId))!;
    expect(order.status, OrderStatus.readyForPickup);
    expect(
      order.timeline.keys,
      containsAll([
        OrderStatus.placed.wire,
        OrderStatus.preparing.wire,
        OrderStatus.readyForPickup.wire,
      ]),
      reason: 'each leg should be stamped so buyers see a real timeline',
    );

    // It now shows up in the open rider pool.
    final pool = (await db.listAgriOrders())
        .where((o) => o.status == OrderStatus.readyForPickup && !o.hasRider)
        .toList();
    expect(pool, hasLength(1));

    // Rider accepts the batch.
    final tripId = await db.acceptTrip(
      orders: pool,
      riderId: 'rider-1',
      riderName: 'Carlo Mendoza',
      riderPhone: '09173334444',
      riderVehicle: 'Honda TMX',
      area: 'Cabanatuan City',
    );

    order = (await db.getOrder(orderId))!;
    expect(order.status, OrderStatus.riderAssigned);
    expect(order.riderId, 'rider-1');
    expect(order.riderName, 'Carlo Mendoza');
    expect(order.tripId, tripId);

    // Nobody else can see it in the pool now.
    expect(
      (await db.listAgriOrders())
          .where((o) => o.status == OrderStatus.readyForPickup && !o.hasRider),
      isEmpty,
    );

    // Rider shares position; the buyer's tracking screen reads it back.
    await db.broadcastRiderPosition(
      orderIds: [orderId],
      latitude: 15.52,
      longitude: 120.94,
    );
    order = (await db.getOrder(orderId))!;
    expect(order.riderPoint, isNotNull);
    expect(order.riderPoint!.latitude, closeTo(15.52, 0.0001));

    // Pickup, then delivery.
    await db.advanceOrder(orderId, OrderStatus.pickedUp,
        existingTimeline: order.timeline);
    order = (await db.getOrder(orderId))!;
    await db.advanceOrder(orderId, OrderStatus.inTransit,
        existingTimeline: order.timeline);
    order = (await db.getOrder(orderId))!;
    await db.advanceOrder(orderId, OrderStatus.delivered,
        existingTimeline: order.timeline);
    await db.completeTrip(tripId);

    order = (await db.getOrder(orderId))!;
    expect(order.status, OrderStatus.delivered);
    expect(order.status.isOpen, isFalse);
    expect(order.riderPayout, 112);

    // Every leg is recorded, in the order it happened.
    expect(order.timeline.keys, [
      OrderStatus.placed.wire,
      OrderStatus.preparing.wire,
      OrderStatus.readyForPickup.wire,
      OrderStatus.riderAssigned.wire,
      OrderStatus.pickedUp.wire,
      OrderStatus.inTransit.wire,
      OrderStatus.delivered.wire,
    ]);
    final stamps = order.timeline.values.toList();
    for (var i = 1; i < stamps.length; i++) {
      expect(stamps[i].isBefore(stamps[i - 1]), isFalse);
    }

    final trips = await db.listTrips(riderId: 'rider-1');
    expect(trips.single['status'], 'completed');
    expect(trips.single['orderCount'], 1);
  });

  test('orders heading to the same town pool into one rider trip', () async {
    final cropA = await publishCrop(name: 'Red Onions');
    final cropB = await publishCrop(farmerId: 'farm-2', name: 'Tomatoes');

    final first = await placeOrder(cropId: cropA, buyerId: 'buyer-1');
    final second = await placeOrder(
      cropId: cropB,
      farmerId: 'farm-2',
      buyerId: 'buyer-2',
      buyerName: 'Bistro Lokal',
      address: 'Maharlika Highway, Brgy. Kapitan Pepe, Cabanatuan City',
      quantity: 30,
    );
    // A third order heading somewhere else must not join the batch.
    final elsewhere = await placeOrder(
      cropId: cropA,
      buyerId: 'buyer-3',
      buyerName: 'FreshMart',
      address: 'Brgy. San Roque, Gapan, Nueva Ecija',
    );

    for (final id in [first, second, elsewhere]) {
      final order = (await db.getOrder(id))!;
      await db.advanceOrder(id, OrderStatus.readyForPickup,
          existingTimeline: order.timeline);
    }

    final pool = (await db.listAgriOrders())
        .where((o) => o.status == OrderStatus.readyForPickup && !o.hasRider)
        .toList();

    final grouped = <String, List<AgriOrder>>{};
    for (final order in pool) {
      grouped.putIfAbsent(order.dropArea, () => []).add(order);
    }
    expect(grouped.keys, containsAll(['Cabanatuan City', 'Gapan']));

    final batch = PooledBatch(
      area: 'Cabanatuan City',
      orders: grouped['Cabanatuan City']!,
    );
    expect(batch.orderCount, 2);
    expect(batch.farmCount, 2);
    expect(batch.totalKg, 50);

    await db.acceptTrip(
      orders: batch.orders,
      riderId: 'rider-1',
      riderName: 'Carlo Mendoza',
      riderPhone: '09173334444',
      riderVehicle: 'Honda TMX',
      area: batch.area,
    );

    final mine = await db.listAgriOrders(riderId: 'rider-1');
    expect(mine, hasLength(2));
    expect(mine.every((order) => order.tripId == mine.first.tripId), isTrue);

    // The Gapan order stays available for another rider.
    final stillOpen = (await db.listAgriOrders())
        .where((o) => o.status == OrderStatus.readyForPickup && !o.hasRider)
        .toList();
    expect(stillOpen.single.id, elsewhere);
  });

  test('a pooled trip visits every farm before any buyer', () async {
    final cropA = await publishCrop();
    final cropB = await publishCrop(farmerId: 'farm-2', name: 'Tomatoes');
    final ids = [
      await placeOrder(cropId: cropA, buyerId: 'buyer-1'),
      await placeOrder(cropId: cropA, buyerId: 'buyer-2', buyerName: 'Bistro'),
      await placeOrder(cropId: cropB, farmerId: 'farm-2', buyerId: 'buyer-1'),
    ];
    final orders = <AgriOrder>[
      for (final id in ids) (await db.getOrder(id))!,
    ];

    final stops = buildTripStops(orders, null);

    // Two farms and two buyers, even though there are three orders.
    expect(stops.where((stop) => stop.isPickup), hasLength(2));
    expect(stops.where((stop) => !stop.isPickup), hasLength(2));

    final firstDropIndex = stops.indexWhere((stop) => !stop.isPickup);
    final lastPickupIndex =
        stops.lastIndexWhere((stop) => stop.isPickup);
    expect(lastPickupIndex, lessThan(firstDropIndex),
        reason: 'a rider cannot deliver produce before collecting it');

    // The buyer with two orders gets one combined stop.
    final combined =
        stops.firstWhere((stop) => !stop.isPickup && stop.orders.length == 2);
    expect(combined.totalKg, 40);
    expect(combined.contactName, 'Maria’s Kitchen');

    expect(stops.every((stop) => !stop.isComplete), isTrue);
  });

  test('reducing stock to zero marks the listing sold out', () async {
    final cropId = await publishCrop(quantity: 25);
    await db.reduceCropStock(cropId, 25);
    final crop = (await db.listCropListings()).single;
    expect(crop.quantityKg, 0);
    expect(crop.status, 'sold_out');
    expect(crop.inStock, isFalse);
  });

  test('rider availability is stored on the account', () async {
    await db.setRiderAvailability(
      riderId: 'rider-1',
      online: true,
      latitude: 15.5,
      longitude: 120.9,
    );
    var account = await db.getAccount('rider-1');
    expect(account!['riderOnline'], isTrue);

    await db.setRiderAvailability(riderId: 'rider-1', online: false);
    account = await db.getAccount('rider-1');
    expect(account!['riderOnline'], isFalse);
  });

  test('reports open for review and can be resolved', () async {
    await db.createReport({
      'reporterId': 'buyer-1',
      'reporterName': 'Maria’s Kitchen',
      'farmerId': 'farm-1',
      'farmerName': 'Green Valley Farm',
      'reason': 'Quantity mismatch',
    });
    var reports = await db.listReports();
    expect(reports.single['status'], 'open');

    await db.resolveReport('${reports.single['id']}', 'Refunded the buyer');
    reports = await db.listReports();
    expect(reports.single['status'], 'resolved');
    expect(reports.single['resolution'], 'Refunded the buyer');
  });
}
