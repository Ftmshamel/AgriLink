import 'package:agrilink_mobile/models/agri_models.dart';
import 'package:agrilink_mobile/services/geo.dart';
import 'package:agrilink_mobile/services/session.dart';
import 'package:flutter_test/flutter_test.dart';

CropListing crop({
  String id = 'crop-1',
  String farmerId = 'farm-1',
  String name = 'Red Onions',
  int price = 75,
  int quantity = 300,
  int moq = 10,
  double? lat = 15.5883,
  double? lng = 120.9192,
}) =>
    CropListing.fromMap({
      'id': id,
      'farmerId': farmerId,
      'farmerName': 'Green Valley Farm',
      'farmerPhone': '09170000001',
      'name': name,
      'quantityKg': quantity,
      'pricePerKg': price,
      'moqKg': moq,
      'farmLatitude': lat,
      'farmLongitude': lng,
      'farmLocation': 'Brgy. Esguerra, Talavera, Nueva Ecija',
      'status': 'active',
    });

AgriOrder order({
  String id = 'order-1',
  String farmerId = 'farm-1',
  String buyerId = 'buyer-1',
  String buyerName = 'Maria’s Kitchen',
  String status = 'ready_for_pickup',
  int quantity = 20,
  int deliveryFee = 140,
  String deliveryAddress = 'Burgos Ave, Brgy. Zulueta, Cabanatuan City',
  double? farmLat = 15.5883,
  double? farmLng = 120.9192,
  double? dropLat = 15.4865,
  double? dropLng = 120.9734,
  Map<String, dynamic> extra = const {},
}) =>
    AgriOrder.fromMap({
      'id': id,
      'buyerId': buyerId,
      'buyerName': buyerName,
      'buyerPhone': '09171112222',
      'farmerId': farmerId,
      'farmerName': 'Green Valley Farm',
      'farmerPhone': '09170000001',
      'cropName': 'Red Onions',
      'quantityKg': quantity,
      'pricePerKg': 75,
      'totalPrice': quantity * 75,
      'deliveryFee': deliveryFee,
      'deliveryAddress': deliveryAddress,
      'deliveryLatitude': dropLat,
      'deliveryLongitude': dropLng,
      'farmLocation': 'Brgy. Esguerra, Talavera, Nueva Ecija',
      'farmLatitude': farmLat,
      'farmLongitude': farmLng,
      'status': status,
      ...extra,
    });

void main() {
  group('OrderStatus', () {
    test('reads the legacy status values already in Firestore', () {
      expect(OrderStatus.parse('paid_preparing'), OrderStatus.preparing);
      expect(OrderStatus.parse('ready_for_pickup'), OrderStatus.readyForPickup);
      expect(OrderStatus.parse('rider_assigned'), OrderStatus.riderAssigned);
      expect(OrderStatus.parse('in_transit'), OrderStatus.inTransit);
      expect(OrderStatus.parse('pending'), OrderStatus.placed);
    });

    test('falls back to placed for unknown values', () {
      expect(OrderStatus.parse('something-else'), OrderStatus.placed);
      expect(OrderStatus.parse(null), OrderStatus.placed);
    });

    test('tracks which states are open and which sit with the rider', () {
      expect(OrderStatus.delivered.isOpen, isFalse);
      expect(OrderStatus.cancelled.isOpen, isFalse);
      expect(OrderStatus.preparing.isOpen, isTrue);
      expect(OrderStatus.inTransit.isWithRider, isTrue);
      expect(OrderStatus.preparing.isWithRider, isFalse);
    });

    test('steps run in delivery order', () {
      expect(
        OrderStatus.placed.step < OrderStatus.preparing.step,
        isTrue,
      );
      expect(
        OrderStatus.pickedUp.step < OrderStatus.delivered.step,
        isTrue,
      );
    });
  });

  group('DeliveryPricing', () {
    test('charges base fare plus distance and handling', () {
      final fee = DeliveryPricing.fee(distanceKm: 10, quantityKg: 20);
      expect(fee, 60 + 80 + 30);
    });

    test('uses a default distance when nothing is pinned', () {
      expect(DeliveryPricing.fee(distanceKm: 0, quantityKg: 0), 100);
    });

    test('pays the rider the agreed share of the fee', () {
      expect(DeliveryPricing.riderPayout(200), 160);
    });
  });

  group('AgriOrder', () {
    test('derives a reference from the id timestamp when none was saved', () {
      // Matches the reference CloudDatabase.createOrder writes for this id.
      expect(order(id: 'order-1750000001234-ab1').reference, '#AG-1234');
      expect(order(id: 'order-1750000000007-zz9').reference, '#AG-0007');
    });

    test('prefers the stored reference over the derived one', () {
      expect(
        order(extra: const {'reference': '#AG-9042'}).reference,
        '#AG-9042',
      );
    });

    test('grand total adds the delivery fee to the produce cost', () {
      final value = order(quantity: 20, deliveryFee: 140);
      expect(value.totalPrice, 1500);
      expect(value.grandTotal, 1640);
      expect(value.riderPayout, 112);
    });

    test('reads the town out of a Philippine address for pooling', () {
      expect(
        order(deliveryAddress: 'Burgos Ave, Brgy. Zulueta, Cabanatuan City')
            .dropArea,
        'Cabanatuan City',
      );
      expect(
        order(deliveryAddress: 'Brgy. San Roque, Gapan, Nueva Ecija').dropArea,
        'Gapan',
      );
      expect(order(deliveryAddress: '').dropArea, 'Unassigned area');
    });

    test('parses the timeline written by advanceOrder', () {
      final value = order(
        status: 'delivered',
        extra: {
          'timeline': {
            'placed': '2026-08-01T02:15:00.000Z',
            'delivered': '2026-08-01T07:30:00.000Z',
          },
        },
      );
      expect(value.timeline['delivered']!.toUtc().hour, 7);
      expect(value.status, OrderStatus.delivered);
    });

    test('exposes map points only when both coordinates exist', () {
      expect(order().pickupPoint, isNotNull);
      expect(order(farmLat: null).pickupPoint, isNull);
      expect(order(dropLng: null).dropPoint, isNull);
      expect(order().routeKm, greaterThan(5));
    });
  });

  group('CropListing', () {
    test('infers a category and emoji when the farmer did not pick one', () {
      expect(crop(name: 'Fresh Pechay').category, CropCategory.leafy);
      expect(crop(name: 'Sweet Mango').category, CropCategory.fruits);
      expect(crop(name: 'Palay').category, CropCategory.grains);
      expect(crop(name: 'Red Onions').category, CropCategory.vegetables);
      expect(crop(name: 'Red Onions').emoji, '🧅');
    });

    test('honours an explicit category over the guess', () {
      final listing = CropListing.fromMap({
        'id': 'c',
        'name': 'Pechay',
        'category': 'Grains',
      });
      expect(listing.category, CropCategory.grains);
    });

    test('is out of stock when the quantity runs out', () {
      expect(crop(quantity: 0).inStock, isFalse);
      expect(crop(quantity: 5).inStock, isTrue);
    });

    test('never reports a zero minimum order', () {
      expect(crop(moq: 0).moqKg, 1);
    });
  });

  group('PooledBatch', () {
    test('sums payout and load across the orders in the batch', () {
      final batch = PooledBatch(
        area: 'Cabanatuan City',
        orders: [
          order(id: 'a', quantity: 20, deliveryFee: 140),
          order(id: 'b', farmerId: 'farm-2', quantity: 30, deliveryFee: 200),
        ],
      );
      expect(batch.orderCount, 2);
      expect(batch.farmCount, 2);
      expect(batch.totalKg, 50);
      expect(batch.payout, 112 + 160);
    });

    test('caps capacity at a full load', () {
      final batch = PooledBatch(
        area: 'Gapan',
        orders: [order(quantity: 900)],
      );
      expect(batch.capacity, 1.0);
    });

    test('names the route from the farms and the destination town', () {
      final batch = PooledBatch(
        area: 'Cabanatuan City',
        orders: [order(id: 'a'), order(id: 'b')],
      );
      expect(batch.route, 'Talavera → Cabanatuan City');
    });
  });

  group('CartController', () {
    test('merges repeat additions of the same crop', () {
      final cart = CartController();
      cart.add(crop(), 20);
      cart.add(crop(), 15);
      expect(cart.count, 1);
      expect(cart.totalKg, 35);
      expect(cart.subtotal, 35 * 75);
    });

    test('keeps separate crops apart and removes on zero quantity', () {
      final cart = CartController();
      cart.add(crop(id: 'a'), 10);
      cart.add(crop(id: 'b', price: 50), 10);
      expect(cart.count, 2);
      expect(cart.subtotal, 750 + 500);

      cart.setQuantity('a', 0);
      expect(cart.count, 1);
      expect(cart.lineFor('a'), isNull);

      cart.clear();
      expect(cart.isEmpty, isTrue);
    });
  });

  group('TripStop', () {
    test('a pickup is done once its orders are collected', () {
      final stop = TripStop(
        kind: StopKind.pickup,
        title: 'Green Valley Farm',
        contactName: 'Roberto',
        phone: '09170000001',
        address: 'Talavera',
        point: null,
        orders: [order(status: 'picked_up'), order(status: 'in_transit')],
      );
      expect(stop.isComplete, isTrue);
      expect(stop.label, 'PICKUP');
    });

    test('a cancelled order does not hold a stop open', () {
      final stop = TripStop(
        kind: StopKind.dropoff,
        title: 'Maria’s Kitchen',
        contactName: 'Maria',
        phone: '09171112222',
        address: 'Cabanatuan',
        point: null,
        orders: [order(status: 'delivered'), order(status: 'cancelled')],
      );
      expect(stop.isComplete, isTrue);
    });

    test('a drop-off is open until everything on it is delivered', () {
      final stop = TripStop(
        kind: StopKind.dropoff,
        title: 'Maria’s Kitchen',
        contactName: 'Maria',
        phone: '09171112222',
        address: 'Cabanatuan',
        point: null,
        orders: [order(status: 'delivered'), order(status: 'in_transit')],
      );
      expect(stop.isComplete, isFalse);
      expect(stop.totalKg, 40);
    });
  });

  group('formatting', () {
    test('groups peso amounts in thousands', () {
      expect(formatPeso(0), '₱0');
      expect(formatPeso(840), '₱840');
      expect(formatPeso(1720), '₱1,720');
      expect(formatPeso(2840000), '₱2,840,000');
    });

    test('switches distance units below a kilometre', () {
      expect(formatKm(0), '—');
      expect(formatKm(0.4), '400 m');
      expect(formatKm(8.24), '8.2 km');
      expect(formatKm(42.4), '42 km');
    });

    test('reads durations as hours and minutes', () {
      expect(formatDuration(const Duration(minutes: 24)), '24 min');
      expect(formatDuration(const Duration(minutes: 135)), '2h 15m');
      expect(formatDuration(const Duration(minutes: 120)), '2h');
    });
  });
}
