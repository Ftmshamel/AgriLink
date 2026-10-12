import 'package:agrilink_mobile/models/agri_models.dart';
import 'package:agrilink_mobile/services/cloud_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_firestore.dart';

String _day(DateTime date) => date.toIso8601String().substring(0, 10);

void main() {
  late FakeFirestore fake;
  late CloudDatabase db;

  setUp(() {
    fake = FakeFirestore();
    db = CloudDatabase(client: fake.client);
  });

  Future<String> placeOrder({
    String paymentStatus = 'paid',
    OrderStatus status = OrderStatus.preparing,
    DateTime? deliveryDate,
    String cropId = '',
  }) =>
      db.createOrder({
        'buyerId': 'buyer-1',
        'buyerName': 'Maria',
        'farmerId': 'farm-1',
        'farmerName': 'Green Valley Farm',
        'cropId': cropId,
        'cropName': 'Red Onions',
        'quantityKg': 20,
        'pricePerKg': 75,
        'totalPrice': 1500,
        'deliveryFee': 140,
        'paymentMethod': 'AgriLink Wallet',
        'paymentStatus': paymentStatus,
        'deliveryType': deliveryDate == null ? 'same_day' : 'scheduled',
        if (deliveryDate != null) 'deliveryDate': _day(deliveryDate),
        'status': status.wire,
      });

  group('wallet ledger', () {
    test('a cash-in is credited once however often it is checked', () async {
      expect(await db.walletBalance('buyer-1'), 0);

      final first = await db.creditCashIn(
        userId: 'buyer-1',
        amount: 500,
        invoiceId: 'inv-1',
      );
      final again = await db.creditCashIn(
        userId: 'buyer-1',
        amount: 500,
        invoiceId: 'inv-1',
      );

      expect(first, isTrue);
      expect(again, isFalse);
      expect(await db.walletBalance('buyer-1'), 500);
    });

    test('paying spends the balance and refuses to overdraw', () async {
      await db.creditCashIn(userId: 'buyer-1', amount: 2000, invoiceId: 'a');

      final reference = await db.payFromWallet(
        userId: 'buyer-1',
        amount: 1640,
        description: 'Order payment',
      );
      expect(reference, startsWith('WALLET-'));
      expect(await db.walletBalance('buyer-1'), 360);

      expect(
        () => db.payFromWallet(
          userId: 'buyer-1',
          amount: 500,
          description: 'Order payment',
        ),
        throwsA(isA<Exception>().having(
          (e) => '$e',
          'message',
          contains('Not enough wallet balance'),
        )),
      );
      expect(await db.walletBalance('buyer-1'), 360);
    });

    test('a checkout that failed half way returns the unused money once',
        () async {
      await db.creditCashIn(userId: 'buyer-1', amount: 1000, invoiceId: 'a');
      final reference = await db.payFromWallet(
        userId: 'buyer-1',
        amount: 800,
        description: 'Order payment',
      );

      await db.reverseWalletPayment(
        userId: 'buyer-1',
        reference: reference,
        amount: 300,
      );
      await db.reverseWalletPayment(
        userId: 'buyer-1',
        reference: reference,
        amount: 300,
      );

      expect(await db.walletBalance('buyer-1'), 500);
    });

    test('history lists every entry with its sign', () async {
      await db.creditCashIn(userId: 'buyer-1', amount: 1000, invoiceId: 'a');
      await db.payFromWallet(
        userId: 'buyer-1',
        amount: 400,
        description: 'Order payment',
      );
      await db.creditCashIn(userId: 'buyer-2', amount: 999, invoiceId: 'b');

      final entries = await db.listWalletTransactions('buyer-1');
      expect(entries, hasLength(2));
      expect(entries.map((e) => e.type),
          containsAll([WalletEntryType.cashIn, WalletEntryType.payment]));
      expect(entries.firstWhere((e) => e.type == WalletEntryType.payment).amount,
          -400);
    });
  });

  group('cancelling', () {
    test('a buyer cancels a scheduled order early and is refunded to the '
        'wallet, once', () async {
      final cropId = await db.createCrop({
        'farmerId': 'farm-1',
        'name': 'Red Onions',
        'quantityKg': 100,
      });
      final orderId = await placeOrder(
        deliveryDate: DateTime.now().add(const Duration(days: 10)),
        cropId: cropId,
      );

      final refunded = await db.cancelOrder(
        orderId,
        cancelledBy: 'buyer',
        restock: true,
      );
      expect(refunded, 1640);
      expect(await db.walletBalance('buyer-1'), 1640);

      final order = (await db.getOrder(orderId))!;
      expect(order.status, OrderStatus.cancelled);
      expect(order.cancelledBy, 'buyer');
      expect(order.refundedAmount, 1640);

      final crop = (await db.listCropListings(farmerId: 'farm-1')).single;
      expect(crop.quantityKg, 120, reason: 'cancelled kilos go back on sale');

      // A second tap, or the farm cancelling too, must not pay out again.
      await db.cancelOrder(orderId, cancelledBy: 'farmer');
      expect(await db.walletBalance('buyer-1'), 1640);
    });

    test('a buyer cannot cancel a same-day order', () async {
      final orderId = await placeOrder();
      expect(
        () => db.cancelOrder(orderId, cancelledBy: 'buyer'),
        throwsA(isA<Exception>().having(
            (e) => '$e', 'message', contains('Same-day'))),
      );
      expect((await db.getOrder(orderId))!.status, OrderStatus.preparing);
    });

    test('a buyer cannot cancel inside the five-day window', () async {
      final orderId = await placeOrder(
        deliveryDate: DateTime.now().add(const Duration(days: 4)),
      );
      expect(
        () => db.cancelOrder(orderId, cancelledBy: 'buyer'),
        throwsA(isA<Exception>().having(
            (e) => '$e', 'message', contains('5 days before'))),
      );
    });

    test('the farm can cancel a paid same-day order and the buyer is refunded',
        () async {
      final orderId = await placeOrder();
      final refunded = await db.cancelOrder(orderId, cancelledBy: 'farmer');
      expect(refunded, 1640);
      expect(await db.walletBalance('buyer-1'), 1640);
    });

    test('an unconfirmed manual payment is not refunded', () async {
      final orderId = await placeOrder(
        paymentStatus: 'submitted',
        status: OrderStatus.placed,
      );
      final refunded = await db.cancelOrder(orderId, cancelledBy: 'farmer');
      expect(refunded, 0);
      expect(await db.walletBalance('buyer-1'), 0);
    });
  });

  group('schedule rules', () {
    final now = DateTime(2026, 10, 11, 15);

    AgriOrder order({String? date, OrderStatus status = OrderStatus.preparing}) =>
        AgriOrder.fromMap({
          'id': 'o',
          'status': status.wire,
          'deliveryType': date == null ? 'same_day' : 'scheduled',
          if (date != null) 'deliveryDate': date,
        });

    test('the last day to cancel is exactly five days before delivery', () {
      expect(order(date: '2026-10-16').canBuyerCancel(now), isTrue);
      expect(order(date: '2026-10-15').canBuyerCancel(now), isFalse);
      expect(order().canBuyerCancel(now), isFalse);
    });

    test('nothing can be cancelled once a rider has it', () {
      final taken = AgriOrder.fromMap({
        'id': 'o',
        'status': OrderStatus.riderAssigned.wire,
        'riderId': 'rider-1',
        'deliveryType': 'scheduled',
        'deliveryDate': '2026-11-30',
      });
      expect(taken.canBuyerCancel(now), isFalse);
    });

    test('riders only see an order on its delivery day', () {
      expect(order(date: '2026-10-12').isDueForPickup(now), isFalse);
      expect(order(date: '2026-10-11').isDueForPickup(now), isTrue);
      expect(order().isDueForPickup(now), isTrue);
    });

    test('riders do not see even today\'s orders before 6 AM', () {
      final early = order(date: '2026-10-11');
      expect(early.isDueForPickup(DateTime(2026, 10, 11, 5, 59)), isFalse);
      expect(early.isDueForPickup(DateTime(2026, 10, 11, 6)), isTrue);
    });

    test('a same-day order that rolled past the cutoff reads as next-day', () {
      final rolled = AgriOrder.fromMap({
        'id': 'o',
        'deliveryType': 'same_day',
        'deliveryDate': '2026-10-12',
        'createdAt': '2026-10-11T19:00:00+08:00',
      });
      expect(rolled.isNextDay, isTrue);
      expect(rolled.canBuyerCancel(now), isFalse,
          reason: 'next-day is still same-day service and is final');

      final sameDay = AgriOrder.fromMap({
        'id': 'o',
        'deliveryType': 'same_day',
        'deliveryDate': '2026-10-11',
        'createdAt': '2026-10-11T09:00:00+08:00',
      });
      expect(sameDay.isNextDay, isFalse);
    });
  });

  group('delivery hours', () {
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(2026, 10, 11, hour, minute);
    final today = DateTime(2026, 10, 11);
    final tomorrow = DateTime(2026, 10, 12);

    test('orders before 6 PM are delivered the same day', () {
      expect(DeliveryHours.sameDayDate(at(6)), today);
      expect(DeliveryHours.sameDayDate(at(12)), today);
      expect(DeliveryHours.sameDayDate(at(17, 59)), today);
    });

    test('orders from 6 PM on are delivered tomorrow', () {
      expect(DeliveryHours.sameDayDate(at(18)), tomorrow);
      expect(DeliveryHours.sameDayDate(at(23, 59)), tomorrow);
      expect(DeliveryHours.pastCutoff(at(18)), isTrue);
      expect(DeliveryHours.pastCutoff(at(17, 59)), isFalse);
    });

    test('orders between midnight and 6 AM are still same-day', () {
      expect(DeliveryHours.sameDayDate(at(0)), today);
      expect(DeliveryHours.sameDayDate(at(5, 59)), today);
      expect(DeliveryHours.opensOn(today), at(6));
    });

    test('the rules run on Philippine time whatever the phone zone is', () {
      // 10:30 UTC is 6:30 PM in Manila: past the cutoff even on a phone set
      // to UTC, where it would still read as morning.
      final manila =
          DeliveryHours.inManila(DateTime.utc(2026, 10, 11, 10, 30));
      expect(manila, DateTime(2026, 10, 11, 18, 30));
      expect(DeliveryHours.pastCutoff(manila), isTrue);
      expect(DeliveryHours.sameDayDate(manila), tomorrow);

      // 9 PM UTC is already 5 AM the next day in Manila.
      expect(DeliveryHours.inManila(DateTime.utc(2026, 10, 10, 21)),
          DateTime(2026, 10, 11, 5));
    });

    test('scheduling starts the day after same-day would deliver', () {
      expect(DeliveryHours.firstScheduleDate(at(10)), tomorrow);
      expect(DeliveryHours.firstScheduleDate(at(19)),
          DateTime(2026, 10, 13));
    });
  });
}
