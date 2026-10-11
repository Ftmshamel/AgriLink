import 'package:agrilink_mobile/models/agri_models.dart';
import 'package:agrilink_mobile/services/cloud_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_firestore.dart';

// S&R Farm, San Ildefonso, to two restaurants in Cabanatuan City.
const _farm = (lat: 15.0794, lng: 120.9414);
const _burgos = (lat: 15.4864, lng: 120.9673);
const _maharlika = (lat: 15.4931, lng: 120.9702);

Map<String, dynamic> _order(
  String id, {
  required ({double lat, double lng}) drop,
  int kg = 50,
  String buyerId = 'buyer-1',
}) {
  const rates = DeliveryRates();
  final solo = rates.fee(distanceKm: 45.5, quantityKg: kg);
  return {
    'id': id,
    'buyerId': buyerId,
    'buyerName': buyerId,
    'farmerId': 'farm-1',
    'farmerName': 'S&R Farm',
    'cropName': 'Palay',
    'quantityKg': kg,
    'pricePerKg': 52,
    'totalPrice': kg * 52,
    'deliveryFee': solo,
    'deliveryAddress': 'Cabanatuan City',
    'farmLatitude': _farm.lat,
    'farmLongitude': _farm.lng,
    'deliveryLatitude': drop.lat,
    'deliveryLongitude': drop.lng,
    'paymentStatus': 'paid',
    'status': OrderStatus.readyForPickup.wire,
  };
}

void main() {
  const rates = DeliveryRates();

  group('sharing a trip', () {
    test('one order alone pays its own fee', () {
      final alone = AgriOrder.fromMap(_order('a', drop: _burgos));
      final shares = PoolPricing.shares([alone], rates);
      expect(shares['a'], alone.deliveryFee);
    });

    test('two buyers on one trip each pay much less than alone', () {
      final a = AgriOrder.fromMap(_order('a', drop: _burgos));
      final b = AgriOrder.fromMap(
          _order('b', drop: _maharlika, buyerId: 'buyer-2'));
      final shares = PoolPricing.shares([a, b], rates);

      expect(shares['a']!, lessThan(a.deliveryFee));
      expect(shares['b']!, lessThan(b.deliveryFee));
      // One trip, one base fare: together they cost about one trip, not two.
      final together = shares['a']! + shares['b']!;
      expect(together, closeTo(PoolPricing.tripCost([a, b], rates), 1));
      expect(together, lessThan(a.deliveryFee + b.deliveryFee));
    });

    test('nobody ever pays more than they were charged', () {
      // A tiny fee that a long shared route would otherwise exceed.
      final cheap = AgriOrder.fromMap(
          {..._order('a', drop: _burgos), 'deliveryFee': 50});
      final other = AgriOrder.fromMap(
          {..._order('b', drop: _maharlika), 'deliveryFee': 50});
      final shares = PoolPricing.shares([cheap, other], rates);
      expect(shares['a']!, lessThanOrEqualTo(50));
      expect(shares['b']!, lessThanOrEqualTo(50));
    });

    test('the rider is paid their share of the one trip', () {
      final a = AgriOrder.fromMap(_order('a', drop: _burgos));
      final b = AgriOrder.fromMap(
          _order('b', drop: _maharlika, buyerId: 'buyer-2'));
      final batch = PooledBatch(area: 'Cabanatuan City', orders: [a, b]);
      final shares = PoolPricing.shares([a, b], rates);
      expect(
        batch.payout,
        DeliveryPricing.riderPayout(shares['a']! + shares['b']!),
      );
    });
  });

  group('accepting a pooled trip', () {
    late FakeFirestore fake;
    late CloudDatabase db;

    setUp(() {
      fake = FakeFirestore();
      db = CloudDatabase(client: fake.client);
    });

    Future<AgriOrder> place(Map<String, dynamic> data) async {
      final id = await db.createOrder({...data}..remove('id'));
      return (await db.getOrder(id))!;
    }

    test('each buyer gets the savings back in their wallet, once', () async {
      final a = await place(_order('a', drop: _burgos));
      final b = await place(
          _order('b', drop: _maharlika, buyerId: 'buyer-2'));

      await db.acceptTrip(
        orders: [a, b],
        riderId: 'rider-1',
        riderName: 'Rovick',
        riderPhone: '0917',
        riderVehicle: 'L300',
        area: 'Cabanatuan City',
      );

      final savedA = (await db.getOrder(a.id))!;
      final savedB = (await db.getOrder(b.id))!;
      expect(savedA.poolRebate, greaterThan(0));
      expect(savedA.deliveryFee, a.deliveryFee - savedA.poolRebate);
      expect(await db.walletBalance('buyer-1'), savedA.poolRebate);
      expect(await db.walletBalance('buyer-2'), savedB.poolRebate);

      // The rider is paid for one trip, not two solo trips.
      final trips = await db.listTrips(riderId: 'rider-1');
      expect(
        trips.single['payout'],
        DeliveryPricing.riderPayout(savedA.deliveryFee + savedB.deliveryFee),
      );

      // A cancellation now refunds what is left, not the solo fee again.
      expect(savedA.refundableAmount, savedA.totalPrice + savedA.deliveryFee);
    });

    test('a lone order is not changed', () async {
      final a = await place(_order('a', drop: _burgos));
      await db.acceptTrip(
        orders: [a],
        riderId: 'rider-1',
        riderName: 'Rovick',
        riderPhone: '0917',
        riderVehicle: 'L300',
        area: 'Cabanatuan City',
      );
      final saved = (await db.getOrder(a.id))!;
      expect(saved.poolRebate, 0);
      expect(saved.deliveryFee, a.deliveryFee);
      expect(await db.walletBalance('buyer-1'), 0);
    });

    test('saved delivery rates are what new trips are priced with', () async {
      await db.saveDeliveryRates(const DeliveryRates(dieselPerLitre: 70));
      DeliveryRates.current = const DeliveryRates();
      final loaded = await db.loadDeliveryRates();
      expect(loaded.dieselPerLitre, 70);
      expect(DeliveryRates.current.dieselPerLitre, 70);
      DeliveryRates.current = const DeliveryRates();
    });
  });
}
