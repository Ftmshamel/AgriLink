import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

class CloudDatabase {
  static const projectId = 'agrilink-19ea5';
  static const _base =
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  final http.Client _client;
  CloudDatabase({http.Client? client}) : _client = client ?? http.Client();

  Future<Map<String, dynamic>> createAccount({
    required String name,
    required String email,
    required String password,
    required String phone,
    required String role,
    required Map<String, dynamic> profile,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    final existing = await findAccountByEmail(normalizedEmail);
    if (existing != null) {
      throw Exception('An account with that email already exists.');
    }
    final id = 'mobile-${DateTime.now().millisecondsSinceEpoch}-${_token(6)}';
    final salt = _token(24);
    final now = DateTime.now().toUtc().toIso8601String();
    final data = <String, dynamic>{
      'id': id,
      'name': name.trim(),
      'email': normalizedEmail,
      'phone': phone.trim(),
      'role': role,
      'passwordSalt': salt,
      'passwordHash': _hash(password, salt),
      'verificationStatus': role == 'consumer' || role == 'superadmin'
          ? 'active'
          : 'pending_review',
      'profile': profile,
      'createdAt': now,
      'updatedAt': now,
    };
    await _create('mobileUsers', id, data);
    return data;
  }

  Future<Map<String, dynamic>?> findAccountByEmail(String email) async {
    final accounts = await listCollection('mobileUsers');
    final normalized = email.trim().toLowerCase();
    for (final account in accounts) {
      if ('${account['email']}'.toLowerCase() == normalized) return account;
    }
    return null;
  }

  Future<Map<String, dynamic>?> getAccount(String id) => getDocument(
        'mobileUsers',
        id,
      );

  Future<Map<String, dynamic>> authenticate(
    String email,
    String password, {
    bool staffOnly = false,
  }) async {
    final account = await findAccountByEmail(email);
    if (account == null) throw Exception('No account found with that email.');
    final role = '${account['role']}';
    if (staffOnly && role != 'superadmin') {
      throw Exception('This account is not authorized for platform access.');
    }
    if (!staffOnly && role == 'superadmin') {
      throw Exception('Use Platform staff access for this account.');
    }
    final salt = '${account['passwordSalt'] ?? ''}';
    if (_hash(password, salt) != account['passwordHash']) {
      throw Exception('Incorrect password.');
    }
    return account;
  }

  Future<Map<String, dynamic>> migrateLegacyStaff(
    String email,
    String password,
  ) async {
    final legacy = await getDocument('agriData', 'main');
    final users = legacy?['users'] as List<dynamic>? ?? const [];
    for (final value in users) {
      final user = Map<String, dynamic>.from(value as Map);
      final role = '${user['role'] ?? ''}'.toLowerCase();
      if ('${user['email'] ?? ''}'.toLowerCase() ==
              email.trim().toLowerCase() &&
          '${user['password'] ?? ''}' == password &&
          (role == 'admin' || role == 'superadmin')) {
        return createAccount(
          name: '${user['name'] ?? 'AgriLink Superadmin'}',
          email: email,
          password: password,
          phone: '${user['phone'] ?? ''}',
          role: 'superadmin',
          profile: const {'migratedFrom': 'agriData/main'},
        );
      }
    }
    throw Exception('Invalid platform staff credentials.');
  }

  Future<Map<String, dynamic>> uploadVerificationFile({
    required String userId,
    required String type,
    required String filename,
    required Uint8List bytes,
  }) async {
    if (bytes.length > 750000) {
      throw Exception('File must be smaller than 750 KB.');
    }
    final id = '$userId-${type.replaceAll(' ', '-')}-${_token(6)}';
    final data = <String, dynamic>{
      'id': id,
      'userId': userId,
      'type': type,
      'filename': filename,
      'contentBase64': base64Encode(bytes),
      'size': bytes.length,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    };
    await _create('mobileVerificationFiles', id, data);
    return {
      'id': id,
      'filename': filename,
      'size': bytes.length,
      'type': type,
    };
  }

  Future<List<Map<String, dynamic>>> listCrops({String? farmerId}) async {
    final values = await listCollection('mobileCrops');
    if (farmerId == null) return values;
    return values.where((item) => item['farmerId'] == farmerId).toList();
  }

  Future<void> createCrop(Map<String, dynamic> crop) async {
    final id = 'crop-${DateTime.now().millisecondsSinceEpoch}-${_token(5)}';
    await _create('mobileCrops', id, {
      ...crop,
      'id': id,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> createOrder(Map<String, dynamic> order) async {
    final id = 'order-${DateTime.now().millisecondsSinceEpoch}-${_token(5)}';
    await _create('mobileOrders', id, {
      ...order,
      'id': id,
      'status': order['status'] ?? 'pending',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> createReport(Map<String, dynamic> report) async {
    final id = 'report-${DateTime.now().millisecondsSinceEpoch}-${_token(5)}';
    await _create('mobileReports', id, {
      ...report,
      'id': id,
      'status': 'open',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> updateDocument(
    String collection,
    String id,
    Map<String, dynamic> fields,
  ) async {
    final masks = fields.keys
        .map((key) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent(key)}')
        .join('&');
    final response = await _client.patch(
      Uri.parse('$_base/$collection/$id?$masks'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fields': _encodeMap(fields)}),
    );
    _ensureSuccess(response);
  }

  Future<List<Map<String, dynamic>>> listOrders({
    String? buyerId,
    String? farmerId,
    String? riderId,
  }) async {
    var values = await listCollection('mobileOrders');
    if (buyerId != null) {
      values = values.where((item) => item['buyerId'] == buyerId).toList();
    }
    if (farmerId != null) {
      values = values.where((item) => item['farmerId'] == farmerId).toList();
    }
    if (riderId != null) {
      values = values.where((item) => item['riderId'] == riderId).toList();
    }
    return values;
  }

  Future<List<Map<String, dynamic>>> listCollection(String collection) async {
    final response =
        await _client.get(Uri.parse('$_base/$collection?pageSize=200'));
    _ensureSuccess(response);
    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final documents = decoded['documents'] as List<dynamic>? ?? const [];
    return documents
        .map((value) => _decodeDocument(value as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>?> getDocument(
    String collection,
    String id,
  ) async {
    final response = await _client.get(Uri.parse('$_base/$collection/$id'));
    if (response.statusCode == 404) return null;
    _ensureSuccess(response);
    return _decodeDocument(
      jsonDecode(response.body) as Map<String, dynamic>,
    );
  }

  Future<void> _create(
    String collection,
    String id,
    Map<String, dynamic> value,
  ) async {
    final uri = Uri.parse('$_base/$collection').replace(
      queryParameters: {'documentId': id},
    );
    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'fields': _encodeMap(value)}),
    );
    _ensureSuccess(response);
  }

  void _ensureSuccess(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Database request failed (${response.statusCode}).';
      try {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        message = '${(body['error'] as Map?)?['message'] ?? message}';
      } catch (_) {}
      throw Exception(message);
    }
  }

  Map<String, dynamic> _decodeDocument(Map<String, dynamic> document) {
    final result = _decodeMap(
      document['fields'] as Map<String, dynamic>? ?? const {},
    );
    result['_documentName'] = document['name'];
    return result;
  }

  Map<String, dynamic> _decodeMap(Map<String, dynamic> fields) {
    return fields.map((key, value) => MapEntry(
          key,
          _decodeValue(value as Map<String, dynamic>),
        ));
  }

  dynamic _decodeValue(Map<String, dynamic> value) {
    if (value.containsKey('stringValue')) return value['stringValue'];
    if (value.containsKey('integerValue')) {
      return int.tryParse('${value['integerValue']}') ?? 0;
    }
    if (value.containsKey('doubleValue')) return value['doubleValue'];
    if (value.containsKey('booleanValue')) return value['booleanValue'];
    if (value.containsKey('nullValue')) return null;
    if (value.containsKey('mapValue')) {
      final map = value['mapValue'] as Map<String, dynamic>;
      return _decodeMap(map['fields'] as Map<String, dynamic>? ?? const {});
    }
    if (value.containsKey('arrayValue')) {
      final array = value['arrayValue'] as Map<String, dynamic>;
      return (array['values'] as List<dynamic>? ?? const [])
          .map((item) => _decodeValue(item as Map<String, dynamic>))
          .toList();
    }
    return null;
  }

  Map<String, dynamic> _encodeMap(Map<String, dynamic> value) {
    return value.map((key, item) => MapEntry(key, _encodeValue(item)));
  }

  Map<String, dynamic> _encodeValue(dynamic value) {
    if (value == null) return {'nullValue': null};
    if (value is String) return {'stringValue': value};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': '$value'};
    if (value is double) return {'doubleValue': value};
    if (value is Map<String, dynamic>) {
      return {
        'mapValue': {'fields': _encodeMap(value)}
      };
    }
    if (value is List) {
      return {
        'arrayValue': {'values': value.map(_encodeValue).toList()}
      };
    }
    return {'stringValue': '$value'};
  }

  String _token(int length) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  String _hash(String password, String salt) {
    return sha256.convert(utf8.encode('$salt:$password')).toString();
  }
}
