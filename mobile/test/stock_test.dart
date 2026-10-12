import 'package:agrilink_mobile/services/cloud_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_firestore.dart';

void main() {
  late FakeFirestore fake;
  late CloudDatabase db;

  setUp(() {
    fake = FakeFirestore();
    db = CloudDatabase(client: fake.client);
  });

  Future<String> publish(int kg) => db.createCrop({
        'farmerId': 'farm-1',
        'name': 'Red Onions',
        'quantityKg': kg,
      });

  Future<int> stockOf(String id) async =>
      (await db.listCropListings(farmerId: 'farm-1'))
          .firstWhere((crop) => crop.id == id)
          .quantityKg;

  test('a sale larger than the stock is refused and nothing changes',
      () async {
    final id = await publish(20);
    expect(
      () => db.reduceCropStock(id, 25),
      throwsA(isA<Exception>().having(
          (e) => '$e', 'message', contains('Only 20 kg of Red Onions'))),
    );
    expect(await stockOf(id), 20);
  });

  test('a sold-out listing says so', () async {
    final id = await publish(10);
    await db.reduceCropStock(id, 10);
    expect(
      () => db.reduceCropStock(id, 1),
      throwsA(isA<Exception>()
          .having((e) => '$e', 'message', contains('just sold out'))),
    );
  });

  test('a write that lands between the read and the write is not lost',
      () async {
    final id = await publish(20);
    final other = CloudDatabase(client: fake.client);
    var interleaved = false;
    fake.beforePatch = (key) async {
      if (interleaved) return;
      interleaved = true;
      // The competing checkout completes in full before ours is applied.
      await other.reduceCropStock(id, 15);
    };
    await expectLater(
      db.reduceCropStock(id, 15),
      throwsA(isA<Exception>()
          .having((e) => '$e', 'message', contains('Only 5 kg'))),
    );
    expect(await stockOf(id), 5,
        reason: 'only one of two 15 kg sales from 20 kg can succeed');
    expect(
      () => db.reduceCropStock(id, 15),
      throwsA(isA<Exception>()
          .having((e) => '$e', 'message', contains('Only 5 kg'))),
      reason: 'a retry sees what the other buyer left',
    );
  });

  test('cancelled kilos go back and reopen a sold-out listing', () async {
    final id = await publish(10);
    await db.reduceCropStock(id, 10);
    await db.restoreCropStock(id, 4);
    final crop = (await db.listCropListings(farmerId: 'farm-1')).single;
    expect(crop.quantityKg, 4);
    expect(crop.status, 'active');
  });
}
