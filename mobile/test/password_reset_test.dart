import 'package:agrilink_mobile/services/cloud_database.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_firestore.dart';

void main() {
  late FakeFirestore firestore;
  late CloudDatabase database;

  setUp(() async {
    firestore = FakeFirestore();
    database = CloudDatabase(client: firestore.client);
    // Most tests are about what a code does, not about the throttle; the
    // throttle has its own test below.
    CloudDatabase.resetRequestCooldown = Duration.zero;
    await database.createAccount(
      name: 'Carlo Mendoza',
      email: 'Carlo@Example.com',
      password: 'harvest123',
      phone: '09171234567',
      role: 'farmer',
      profile: const {'location': 'Nueva Ecija'},
    );
  });

  test('emails a six-digit code that unlocks a new password', () async {
    final request = await database.createPasswordReset('carlo@example.com');
    expect(request.code, matches(RegExp(r'^\d{6}$')));
    expect(request.email, 'carlo@example.com');
    expect(request.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);

    final ticketId = await database.verifyPasswordResetCode(
      'carlo@example.com',
      request.code,
    );
    await database.completePasswordReset(
      email: 'carlo@example.com',
      ticketId: ticketId,
      newPassword: 'newharvest456',
    );

    final account =
        await database.authenticate('carlo@example.com', 'newharvest456');
    expect(account['name'], 'Carlo Mendoza');
    await expectLater(
      database.authenticate('carlo@example.com', 'harvest123'),
      throwsA(isA<Exception>()),
    );
  });

  test('a used code cannot be replayed', () async {
    final request = await database.createPasswordReset('carlo@example.com');
    final ticketId = await database.verifyPasswordResetCode(
      'carlo@example.com',
      request.code,
    );
    await database.completePasswordReset(
      email: 'carlo@example.com',
      ticketId: ticketId,
      newPassword: 'newharvest456',
    );

    await expectLater(
      database.verifyPasswordResetCode('carlo@example.com', request.code),
      throwsA(isA<Exception>()),
    );
  });

  test('requesting a new code retires the previous one', () async {
    final first = await database.createPasswordReset('carlo@example.com');
    final second = await database.createPasswordReset('carlo@example.com');

    await expectLater(
      database.verifyPasswordResetCode('carlo@example.com', first.code),
      throwsA(isA<Exception>()),
    );
    expect(
      await database.verifyPasswordResetCode(
        'carlo@example.com',
        second.code,
      ),
      isNotEmpty,
    );
  });

  test('wrong codes are burned after the attempt limit', () async {
    final request = await database.createPasswordReset('carlo@example.com');
    final wrong = request.code == '000000' ? '111111' : '000000';

    for (var attempt = 0; attempt < CloudDatabase.maxResetAttempts; attempt++) {
      await expectLater(
        database.verifyPasswordResetCode('carlo@example.com', wrong),
        throwsA(isA<Exception>()),
      );
    }
    // Even the real code is refused once the request has been exhausted.
    await expectLater(
      database.verifyPasswordResetCode('carlo@example.com', request.code),
      throwsA(isA<Exception>()),
    );
  });

  test('a second code cannot be demanded straight away', () async {
    CloudDatabase.resetRequestCooldown = const Duration(minutes: 1);
    await database.createPasswordReset('carlo@example.com');

    // Anyone who knows the address could otherwise hold the button down and
    // flood that person's inbox.
    await expectLater(
      database.createPasswordReset('carlo@example.com'),
      throwsA(
        isA<Exception>().having(
          (error) => '$error',
          'message',
          contains('Please wait'),
        ),
      ),
    );
  });

  test('unknown emails are rejected before a ticket is written', () async {
    await expectLater(
      database.createPasswordReset('nobody@example.com'),
      throwsA(isA<Exception>()),
    );
    expect(
      firestore.documents.keys.where((key) => key.contains('PasswordResets')),
      isEmpty,
    );
  });
}
