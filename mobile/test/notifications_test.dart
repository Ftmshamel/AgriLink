import 'package:agrilink_mobile/models/agri_models.dart';
import 'package:agrilink_mobile/services/notifications.dart';
import 'package:flutter_test/flutter_test.dart';

String _at(int hour) => DateTime(2026, 10, 11, hour).toUtc().toIso8601String();

AgriOrder _order(Map<String, dynamic> extra) => AgriOrder.fromMap({
      'id': 'o1',
      'reference': '#AG-0001',
      'buyerName': 'Maria',
      'cropName': 'Red Onions',
      'quantityKg': 20,
      'totalPrice': 1500,
      'deliveryFee': 200,
      ...extra,
    });

void main() {
  test('a buyer hears about each step, newest first, with their code', () {
    final notices = NoticeFeed.forConsumer([
      _order({
        'status': OrderStatus.inTransit.wire,
        'riderName': 'Rovick',
        'deliveryCode': '0778',
        'timeline': {
          OrderStatus.placed.wire: _at(8),
          OrderStatus.preparing.wire: _at(9),
          OrderStatus.riderAssigned.wire: _at(10),
          OrderStatus.inTransit.wire: _at(11),
        },
      }),
    ]);
    expect(notices.map((n) => n.title), [
      'On the way • your delivery code is 0778',
      'Rovick accepted your delivery',
      'The farm is packing your order',
    ]);
  });

  test('a buyer is told about refunds and shared-trip savings', () {
    final cancelled = NoticeFeed.forConsumer([
      _order({
        'status': OrderStatus.cancelled.wire,
        'refundedAmount': 1700,
        'timeline': {OrderStatus.cancelled.wire: _at(9)},
      }),
    ]);
    expect(cancelled.single.title, contains('₱1,700 back in your wallet'));

    final pooled = NoticeFeed.forConsumer([
      _order({'poolRebate': 795, 'riderAssignedAt': _at(10)}),
    ]);
    expect(pooled.single.title, contains('₱795 back in your wallet'));
  });

  test('a farm hears about new orders, ratings, and payouts', () {
    final notices = NoticeFeed.forFarmer([
      _order({
        'status': OrderStatus.delivered.wire,
        'deliveryType': 'scheduled',
        'deliveryDate': '2026-10-19',
        'farmerRating': 5,
        'ratedAt': _at(15),
        'farmerPaidAt': _at(16),
        'farmerPayoutReference': 'GC-1',
        'timeline': {
          OrderStatus.placed.wire: _at(8),
          OrderStatus.delivered.wire: _at(14),
        },
      }),
    ]);
    expect(notices.map((n) => n.title), [
      'Payout sent • ₱1,500',
      'Maria rated you 5/5',
      'Delivered to Maria',
      'New order from Maria • for Mon, Oct 19',
    ]);
  });

  test('a rider hears when packed orders are waiting', () {
    final notices = NoticeFeed.forRider(const [], [
      _order({
        'deliveryAddress': 'Burgos Ave, Cabanatuan City',
        'timeline': {OrderStatus.readyForPickup.wire: _at(9)},
      }),
    ]);
    expect(notices.single.title, '1 packed order waiting for a rider');
    expect(notices.single.body, 'Heading to Cabanatuan City');
  });

  test('admins hear about applications and disputes', () {
    final notices = NoticeFeed.forAdmin(
      [
        {
          'id': 'a',
          'name': 'Mang Ben',
          'role': 'farmer',
          'verificationStatus': 'pending_review',
          'createdAt': _at(8),
        },
        {'id': 'b', 'name': 'Done', 'verificationStatus': 'active'},
      ],
      [
        {'id': 'r', 'reporterName': 'Maria', 'reason': 'Short', 'createdAt': _at(9)},
      ],
    );
    expect(notices.map((n) => n.title), [
      'New dispute from Maria',
      'Mang Ben applied as a farmer',
    ]);
  });

  test('only what came after the last visit is unread', () {
    final notices = NoticeFeed.forConsumer([
      _order({
        'timeline': {
          OrderStatus.preparing.wire: _at(9),
          OrderStatus.readyForPickup.wire: _at(11),
        },
      }),
    ]);
    expect(NoticeSeen.unread(notices, null), 2);
    expect(NoticeSeen.unread(notices, DateTime(2026, 10, 11, 10)), 1);
    expect(NoticeSeen.unread(notices, DateTime(2026, 10, 11, 12)), 0);
  });
}
