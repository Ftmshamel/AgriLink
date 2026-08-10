import 'dart:convert';

import 'package:agrilink_mobile/services/cloud_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  late FakeFirestore firestore;
  late CloudDatabase database;

  setUp(() async {
    firestore = FakeFirestore();
    database = CloudDatabase(client: firestore.client);
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

/// An in-memory stand-in for the Firestore REST endpoints [CloudDatabase] uses.
class FakeFirestore {
  final Map<String, Map<String, dynamic>> documents = {};

  http.Client get client => MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final segments = request.url.pathSegments;
    final tail = segments.sublist(6);

    if (segments[5] == 'documents:runQuery') {
      return _runQuery(jsonDecode(request.body) as Map<String, dynamic>);
    }
    final collection = tail.isEmpty ? '' : tail.first;

    switch (request.method) {
      case 'POST':
        final id = request.url.queryParameters['documentId']!;
        documents['$collection/$id'] =
            _decode(_fields(request.body)).cast<String, dynamic>();
        return _ok({'name': '$collection/$id'});
      case 'GET':
        if (tail.length == 2) {
          final stored = documents['$collection/${tail[1]}'];
          if (stored == null) return http.Response('{}', 404);
          return _ok(_document('$collection/${tail[1]}', stored));
        }
        return _ok({
          'documents': [
            for (final entry in documents.entries)
              if (entry.key.startsWith('$collection/'))
                _document(entry.key, entry.value),
          ],
        });
      case 'PATCH':
        final key = '$collection/${tail[1]}';
        final stored = documents[key];
        if (stored == null) return http.Response('{}', 404);
        stored.addAll(_decode(_fields(request.body)).cast<String, dynamic>());
        return _ok(_document(key, stored));
      case 'DELETE':
        documents.remove('$collection/${tail[1]}');
        return _ok(const {});
      default:
        return http.Response('{}', 405);
    }
  }

  http.Response _runQuery(Map<String, dynamic> body) {
    final query = body['structuredQuery'] as Map<String, dynamic>;
    final collection =
        (query['from'] as List).first['collectionId'] as String;
    final filter = query['where']['fieldFilter'] as Map<String, dynamic>;
    final field = filter['field']['fieldPath'] as String;
    final wanted = filter['value']['stringValue'];
    final rows = [
      for (final entry in documents.entries)
        if (entry.key.startsWith('$collection/') && entry.value[field] == wanted)
          {'document': _document(entry.key, entry.value)},
    ];
    return http.Response(
      jsonEncode(rows.isEmpty ? [const {'readTime': '1970-01-01T00:00:00Z'}] : rows),
      200,
      headers: {'content-type': 'application/json'},
    );
  }

  Map<String, dynamic> _fields(String body) =>
      (jsonDecode(body) as Map<String, dynamic>)['fields']
          as Map<String, dynamic>;

  Map<String, dynamic> _document(String name, Map<String, dynamic> data) =>
      {'name': name, 'fields': _encode(data)};

  http.Response _ok(Map<String, dynamic> body) => http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json'},
      );

  Map<String, dynamic> _encode(Map<String, dynamic> value) =>
      value.map((key, item) => MapEntry(key, _encodeValue(item)));

  Map<String, dynamic> _encodeValue(dynamic value) {
    if (value == null) return {'nullValue': null};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': '$value'};
    if (value is double) return {'doubleValue': value};
    if (value is Map) {
      return {
        'mapValue': {'fields': _encode(Map<String, dynamic>.from(value))},
      };
    }
    if (value is List) {
      return {
        'arrayValue': {'values': value.map(_encodeValue).toList()},
      };
    }
    return {'stringValue': '$value'};
  }

  Map<String, dynamic> _decode(Map<String, dynamic> fields) =>
      fields.map((key, value) =>
          MapEntry(key, _decodeValue(value as Map<String, dynamic>)));

  dynamic _decodeValue(Map<String, dynamic> value) {
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('integerValue')) {
      return int.parse('${value['integerValue']}');
    }
    if (value.containsKey('doubleValue')) return value['doubleValue'];
    if (value.containsKey('booleanValue')) return value['booleanValue'];
    if (value.containsKey('mapValue')) {
      final map = value['mapValue'] as Map<String, dynamic>;
      return _decode(map['fields'] as Map<String, dynamic>? ?? const {});
    }
    if (value.containsKey('arrayValue')) {
      final array = value['arrayValue'] as Map<String, dynamic>;
      return (array['values'] as List<dynamic>? ?? const [])
          .map((item) => _decodeValue(item as Map<String, dynamic>))
          .toList();
    }
    return null;
  }
}
