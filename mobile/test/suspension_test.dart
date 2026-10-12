import 'package:agrilink_mobile/models/mobile_user.dart';
import 'package:agrilink_mobile/services/cloud_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_firestore.dart';

void main() {
  late FakeFirestore fake;
  late CloudDatabase db;

  setUp(() {
    fake = FakeFirestore();
    db = CloudDatabase(client: fake.client);
    fake.documents['mobileUsers/farm-1'] = {
      'id': 'farm-1',
      'name': 'Green Valley Farm',
      'email': 'farm@example.com',
      'role': 'farmer',
      'verificationStatus': 'active',
    };
    fake.documents['mobileUsers/buyer-1'] = {
      'id': 'buyer-1',
      'name': 'Maria',
      'email': 'maria@example.com',
      'role': 'consumer',
      'verificationStatus': 'active',
    };
  });

  test('a suspended farm leaves the marketplace and comes back on restore',
      () async {
    final cropId = await db.createCrop({
      'farmerId': 'farm-1',
      'name': 'Red Onions',
      'quantityKg': 100,
    });
    final farm = (await db.getAccount('farm-1'))!;

    await db.setAccountSuspended(farm, suspended: true, reason: 'Scam report');
    expect(await db.listCropListings(), isEmpty,
        reason: 'buyers no longer see the farm');
    expect(await db.listCropListings(farmerId: 'farm-1'), hasLength(1),
        reason: 'the farm still sees its own listing');
    expect(
      () => db.reduceCropStock(cropId, 10),
      throwsA(isA<Exception>()
          .having((e) => '$e', 'message', contains('not available'))),
      reason: 'a cart filled before the suspension cannot check out',
    );
    final suspended = MobileUser.fromJson((await db.getAccount('farm-1'))!);
    expect(suspended.isApproved, isFalse);
    expect(suspended.statusReason, 'Scam report');

    await db.setAccountSuspended(farm, suspended: false);
    expect(await db.listCropListings(), hasLength(1));
    final restored = MobileUser.fromJson((await db.getAccount('farm-1'))!);
    expect(restored.isApproved, isTrue);
    expect(restored.statusReason, isEmpty);
  });

  test('a consumer can be suspended too', () async {
    final buyer = (await db.getAccount('buyer-1'))!;
    await db.setAccountSuspended(buyer, suspended: true, reason: 'Fake payment');
    final account = MobileUser.fromJson((await db.getAccount('buyer-1'))!);
    expect(account.role, MobileRole.consumer);
    expect(account.verificationStatus, 'suspended');
    expect(account.isApproved, isFalse);
  });

  test('a report records who it is about', () async {
    await db.createReport({
      'reporterId': 'rider-1',
      'reporterRole': 'rider',
      'againstId': 'buyer-1',
      'againstName': 'Maria',
      'againstRole': 'consumer',
      'reason': 'Refused delivery and would not pay',
    });
    final report = (await db.listReports()).single;
    expect(report['againstId'], 'buyer-1');
    expect(report['againstRole'], 'consumer');
    expect(report['status'], 'open');
  });
}
