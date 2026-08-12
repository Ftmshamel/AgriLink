import 'dart:convert';

import 'package:agrilink_mobile/services/cloud_database.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_firestore.dart';

void main() {
  late FakeFirestore firestore;
  late CloudDatabase database;

  setUp(() {
    firestore = FakeFirestore();
    database = CloudDatabase(client: firestore.client);
  });

  Map<String, dynamic> storedAccount(String email) => firestore.documents.values
      .firstWhere((doc) => doc['email'] == email);

  test('a new account is stored with PBKDF2, never a bare digest', () async {
    await database.createAccount(
      name: 'Carlo Mendoza',
      email: 'carlo@example.com',
      password: 'harvest123',
      phone: '09171234567',
      role: 'farmer',
      profile: const {},
    );

    final account = storedAccount('carlo@example.com');
    expect(account['passwordAlgorithm'], 'pbkdf2-sha256');
    expect(account['passwordIterations'], CloudDatabase.passwordIterations);
    expect(account['passwordHash'], hasLength(64));
    // The stored value must not be the single-pass digest of salt:password.
    final salt = account['passwordSalt'] as String;
    final naive = sha256.convert(utf8.encode('$salt:harvest123')).toString();
    expect(account['passwordHash'], isNot(naive));

    final signedIn =
        await database.authenticate('carlo@example.com', 'harvest123');
    expect(signedIn['name'], 'Carlo Mendoza');
    await expectLater(
      database.authenticate('carlo@example.com', 'wrong'),
      throwsA(isA<Exception>()),
    );
  });

  group('accounts created before PBKDF2', () {
    /// Writes an account in the original format: one SHA-256 pass, no
    /// algorithm recorded.
    Future<void> seedLegacyAccount() async {
      const salt = 'legacysalt000000000000';
      firestore.documents['mobileUsers/legacy-1'] = {
        'id': 'legacy-1',
        'name': 'Old Account',
        'email': 'old@example.com',
        'phone': '09170000000',
        'role': 'consumer',
        'passwordSalt': salt,
        'passwordHash':
            sha256.convert(utf8.encode('$salt:oldpassword')).toString(),
        'verificationStatus': 'active',
        'profile': <String, dynamic>{},
      };
    }

    test('can still sign in, and are upgraded in place', () async {
      await seedLegacyAccount();
      final legacyHash = storedAccount('old@example.com')['passwordHash'];

      final account =
          await database.authenticate('old@example.com', 'oldpassword');
      expect(account['name'], 'Old Account');

      // The weak hash is replaced the moment its owner proves the password.
      final stored = storedAccount('old@example.com');
      expect(stored['passwordAlgorithm'], 'pbkdf2-sha256');
      expect(stored['passwordHash'], isNot(legacyHash));

      // And the upgraded record still accepts the same password.
      final again =
          await database.authenticate('old@example.com', 'oldpassword');
      expect(again['email'], 'old@example.com');
    });

    test('a wrong password is still refused and nothing is upgraded', () async {
      await seedLegacyAccount();

      await expectLater(
        database.authenticate('old@example.com', 'guess'),
        throwsA(isA<Exception>()),
      );
      expect(storedAccount('old@example.com')['passwordAlgorithm'], isNull);
    });
  });

  test('signing in stays fast enough to feel instant', () async {
    await database.createAccount(
      name: 'Speed Test',
      email: 'speed@example.com',
      password: 'harvest123',
      phone: '09170000001',
      role: 'consumer',
      profile: const {},
    );

    final watch = Stopwatch()..start();
    await database.authenticate('speed@example.com', 'harvest123');
    watch.stop();

    // The work factor has to hurt an attacker without making a farmer wait.
    expect(watch.elapsedMilliseconds, lessThan(2000));
  });
}
