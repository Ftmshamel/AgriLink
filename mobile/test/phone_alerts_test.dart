import 'package:agrilink_mobile/models/agri_models.dart';
import 'package:agrilink_mobile/models/mobile_user.dart';
import 'package:agrilink_mobile/services/cloud_database.dart';
import 'package:agrilink_mobile/services/phone_alerts.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_firestore.dart';

MobileUser _user(String id, MobileRole role) => MobileUser(
      id: id,
      name: id,
      email: '$id@example.com',
      password: '',
      phone: '',
      role: role,
    );

void main() {
  late FakeFirestore fake;
  late CloudDatabase db;

  setUp(() {
    fake = FakeFirestore();
    db = CloudDatabase(client: fake.client);
  });

  test('each role is notified about its own updates', () async {
    await db.createOrder({
      'buyerId': 'buyer-1',
      'buyerName': 'Maria',
      'farmerId': 'farm-1',
      'farmerName': 'Green Valley Farm',
      'cropName': 'Red Onions',
      'quantityKg': 20,
      'status': OrderStatus.placed.wire,
    });

    final farm = await PhoneAlerts.noticesFor(
        _user('farm-1', MobileRole.farmer), db);
    expect(farm.map((n) => n.title), contains(startsWith('New order from Maria')));

    final otherFarm = await PhoneAlerts.noticesFor(
        _user('farm-2', MobileRole.farmer), db);
    expect(otherFarm, isEmpty, reason: 'farms only hear about their own orders');

    final rider = await PhoneAlerts.noticesFor(
        _user('rider-1', MobileRole.rider), db);
    expect(rider, isEmpty, reason: 'nothing is packed for riders yet');
  });
}
