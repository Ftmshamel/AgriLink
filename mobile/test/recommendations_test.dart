import 'package:agrilink_mobile/models/agri_models.dart';
import 'package:agrilink_mobile/services/cloud_database.dart';
import 'package:agrilink_mobile/services/geo.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_firestore.dart';

void main() {
  late FakeFirestore fake;
  late CloudDatabase db;

  setUp(() {
    fake = FakeFirestore();
    db = CloudDatabase(client: fake.client);
  });

  Future<String> delivered({
    String farmerId = 'farm-1',
    String riderId = 'rider-1',
  }) =>
      db.createOrder({
        'buyerId': 'buyer-1',
        'buyerName': 'Maria',
        'farmerId': farmerId,
        'farmerName': 'Green Valley Farm',
        'riderId': riderId,
        'riderName': 'Carlo',
        'cropName': 'Red Onions',
        'quantityKg': 20,
        'pricePerKg': 75,
        'totalPrice': 1500,
        'deliveryFee': 200,
        'paymentStatus': 'paid',
        'status': OrderStatus.delivered.wire,
      });

  group('ratings', () {
    test('averages only the orders buyers actually rated', () async {
      final a = await delivered();
      final b = await delivered();
      await delivered();
      await db.rateOrder(a, farmerRating: 5, riderRating: 4);
      await db.rateOrder(b, farmerRating: 4, riderRating: 2, comment: 'Late');

      final farm = await db.ratingFor(farmerId: 'farm-1');
      expect(farm.count, 2);
      expect(farm.average, 4.5);
      expect(farm.label, '4.5 ★ (2 ratings)');

      final rider = await db.ratingFor(riderId: 'rider-1');
      expect(rider.average, 3.0);

      final order = (await db.getOrder(b))!;
      expect(order.isRated, isTrue);
      expect(order.farmerRating, 4);
    });

    test('ratings are kept between 1 and 5', () async {
      final a = await delivered();
      await db.rateOrder(a, farmerRating: 9, riderRating: 0);
      final order = (await db.getOrder(a))!;
      expect(order.farmerRating, 5);
      expect(order.riderRating, 0);
    });

    test('nobody rated yet reads as such', () {
      expect(RatingSummary.of(const [0, 0]).label, 'No ratings yet');
    });
  });

  group('dispute refunds', () {
    Future<String> report(String orderId) async {
      await db.createReport({'orderId': orderId, 'reason': '2 kg short'});
      return '${(await db.listReports()).single['id']}';
    }

    test('resolving with a refund credits the buyer once', () async {
      final orderId = await delivered();
      final reportId = await report(orderId);

      final refunded = await db.resolveReportWithRefund(
        reportId: reportId,
        resolution: 'Refunded 2 kg',
        refundAmount: 150,
      );
      expect(refunded, 150);
      expect(await db.walletBalance('buyer-1'), 150);

      final again = await db.resolveReportWithRefund(
        reportId: reportId,
        resolution: 'Refunded 2 kg',
        refundAmount: 150,
      );
      expect(again, 0);
      expect(await db.walletBalance('buyer-1'), 150);

      final order = (await db.getOrder(orderId))!;
      expect(order.refundedAmount, 150);
    });

    test('a refund cannot exceed what the order cost', () async {
      final orderId = await delivered();
      final reportId = await report(orderId);
      expect(
        () => db.resolveReportWithRefund(
          reportId: reportId,
          resolution: 'x',
          refundAmount: 5000,
        ),
        throwsA(isA<Exception>().having(
            (e) => '$e', 'message', contains('At most ₱1700'))),
      );
      expect(await db.walletBalance('buyer-1'), 0);
    });

    test('resolving without a refund just closes it', () async {
      final orderId = await delivered();
      final reportId = await report(orderId);
      final refunded = await db.resolveReportWithRefund(
        reportId: reportId,
        resolution: 'Farm re-sent the missing kilos',
        refundAmount: 0,
      );
      expect(refunded, 0);
      final reports = await db.listReports();
      expect(reports.single['status'], 'resolved');
    });
  });

  test('payouts are recorded per payee', () async {
    final a = await delivered();
    await db.markPayout(orderIds: [a], payee: 'farmer', reference: 'GC-1');
    final order = (await db.getOrder(a))!;
    expect(order.isFarmerPaid, isTrue);
    expect(order.isRiderPaid, isFalse);
    expect(order.raw['farmerPayoutReference'], 'GC-1');
  });

  test('a suspension keeps its reason', () async {
    final account = await db.createAccount(
      name: 'Ben',
      email: 'ben@farm.ph',
      password: 'Farmer2026!',
      phone: '0917',
      role: 'farmer',
      profile: const {},
    );
    await db.setVerificationStatus('${account['id']}', 'suspended',
        reason: 'Fake documents');
    final saved = (await db.getAccount('${account['id']}'))!;
    expect(saved['statusReason'], 'Fake documents');
  });

  group('helpers', () {
    test('harvest dates read like dates', () {
      expect(formatHarvestDate('2026-10-20'), 'Oct 20, 2026');
      expect(formatHarvestDate('next week'), 'next week');
    });

    test('plurals', () {
      expect(plural(1, 'farmer'), '1 farmer');
      expect(plural(0, 'consumer'), '0 consumers');
      expect(plural(2, 'rider'), '2 riders');
    });

    test('orders sort by when they are due', () {
      AgriOrder order(String id, String date) => AgriOrder.fromMap({
            'id': id,
            'deliveryType': 'scheduled',
            'deliveryDate': date,
          });
      final list = [
        order('later', '2026-10-21'),
        order('today', '2026-10-11'),
        order('mid', '2026-10-15'),
      ]..sort(AgriOrder.byDueDate);
      expect(list.map((o) => o.id), ['today', 'mid', 'later']);
      expect(list.first.isDueBy(DateTime(2026, 10, 11, 9)), isTrue);
      expect(list.last.isDueBy(DateTime(2026, 10, 11, 9)), isFalse);
    });

    test('low stock is under three minimum orders', () {
      CropListing crop(int kg) => CropListing.fromMap({
            'id': 'c',
            'quantityKg': kg,
            'moqKg': 10,
            'status': 'active',
          });
      expect(crop(29).isLowStock, isTrue);
      expect(crop(30).isLowStock, isFalse);
      expect(crop(0).isLowStock, isFalse, reason: 'that is sold out');
    });
  });
}
