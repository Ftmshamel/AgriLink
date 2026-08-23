import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/agri_models.dart';
import 'document_check.dart';

class CloudDatabase {
  static const projectId = 'agrilink-19ea5';
  static const _base =
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  final http.Client _client;
  CloudDatabase({http.Client? client}) : _client = client ?? http.Client();

  // ---------------------------------------------------------------- accounts

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
    final now = DateTime.now().toUtc().toIso8601String();
    final data = <String, dynamic>{
      'id': id,
      'name': name.trim(),
      'email': normalizedEmail,
      'phone': phone.trim(),
      'role': role,
      ..._passwordFields(password),
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
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    try {
      final matches = await _queryEquals('mobileUsers', 'email', normalized);
      if (matches.isNotEmpty) return matches.first;
    } catch (_) {
      // Fall through to the scan below rather than failing a sign-in.
    }
    // Accounts written before emails were normalised can still be mixed case,
    // so a miss falls back to a full comparison.
    final accounts = await listCollection('mobileUsers');
    for (final account in accounts) {
      if ('${account['email']}'.toLowerCase() == normalized) return account;
    }
    return null;
  }

  Future<Map<String, dynamic>?> getAccount(String id) =>
      getDocument('mobileUsers', id);

  Future<List<Map<String, dynamic>>> listAccounts({String? role}) async {
    final accounts = await listCollection('mobileUsers');
    if (role == null) return accounts;
    return accounts.where((account) => account['role'] == role).toList();
  }

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
    if (!_passwordMatches(account, password)) {
      throw Exception('Incorrect password.');
    }
    await _upgradePasswordIfLegacy(account, password);
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

  Future<void> setVerificationStatus(String userId, String status) =>
      updateDocument('mobileUsers', userId, {
        'verificationStatus': status,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });

  Future<Map<String, dynamic>> uploadVerificationFile({
    required String userId,
    required String type,
    required String filename,
    required Uint8List bytes,
    DocumentInspection? inspection,
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
      if (inspection != null) ...{
        'contentHash': inspection.contentHash,
        'width': inspection.width,
        'height': inspection.height,
        'screeningFlags': DocumentCheck.encode(inspection.flags),
      },
    };
    await _create('mobileVerificationFiles', id, data);
    return {
      'id': id,
      'filename': filename,
      'size': bytes.length,
      'type': type,
    };
  }

  /// Finds the same picture submitted by a different applicant.
  ///
  /// Queried by hash so only genuine collisions are downloaded — the documents
  /// themselves carry the base64 image and are far too heavy to scan.
  Future<List<Map<String, dynamic>>> findDuplicateUploads({
    required String contentHash,
    required String excludingUserId,
  }) async {
    if (contentHash.isEmpty) return const [];
    try {
      final matches = await _queryEquals(
        'mobileVerificationFiles',
        'contentHash',
        contentHash,
        limit: 5,
      );
      return matches
          .where((file) => '${file['userId']}' != excludingUserId)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Removes an applicant's files so a rejected application can be resubmitted
  /// without the old, refused images hanging around for the reviewer.
  Future<void> deleteVerificationFiles(String userId) async {
    final files = await listVerificationFiles(userId);
    for (final file in files) {
      await deleteDocument('mobileVerificationFiles', '${file['id']}');
    }
  }

  Future<List<Map<String, dynamic>>> listVerificationFiles(
    String userId,
  ) async {
    final files = await listCollection('mobileVerificationFiles');
    return files.where((file) => file['userId'] == userId).toList();
  }

  // --------------------------------------------------------- password resets

  /// How long an emailed reset code stays usable.
  static const resetCodeLifetime = Duration(minutes: 15);

  /// Wrong codes tolerated before the whole request is burned.
  static const maxResetAttempts = 5;

  /// Minimum gap between reset requests for one account.
  ///
  /// Without this, anybody who knows an email address can hold down "Send reset
  /// code" and flood that person's inbox — and burn the daily quota of the mail
  /// provider along with it. Settable so tests can exercise the surrounding
  /// behaviour without waiting a real minute.
  static Duration resetRequestCooldown = const Duration(seconds: 60);

  /// Issues a one-time reset code for [email].
  ///
  /// The code itself is never stored. It only survives as part of the document
  /// id `sha256(reference:code)`, so the ticket can be fetched by someone who
  /// already knows the code but cannot be read back out of the collection —
  /// see `firestore.rules`, which allows `get` but not `list` here. Each
  /// request mints a fresh reference, which is what retires any earlier code.
  Future<PasswordResetRequest> createPasswordReset(String email) async {
    final account = await findAccountByEmail(email);
    if (account == null) {
      throw Exception('No account found with that email.');
    }
    final userId = '${account['id'] ?? ''}';
    if (userId.isEmpty) {
      throw Exception('That account cannot be reset from the app.');
    }
    final lastRequest =
        DateTime.tryParse('${account['passwordResetRequestedAt'] ?? ''}');
    if (lastRequest != null) {
      final waited = DateTime.now().toUtc().difference(lastRequest);
      if (waited < resetRequestCooldown) {
        final left = resetRequestCooldown - waited;
        throw Exception(
          'Please wait ${left.inSeconds + 1} seconds before asking for another code.',
        );
      }
    }
    final reference = _token(24);
    final code = _numericCode(6);
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(resetCodeLifetime);
    await _create('mobilePasswordResets', _resetTicketId(reference, code), {
      'userId': userId,
      'expiresAt': expiresAt.toIso8601String(),
      'createdAt': now.toIso8601String(),
    });
    await updateDocument('mobileUsers', userId, {
      'passwordResetReference': reference,
      'passwordResetExpiresAt': expiresAt.toIso8601String(),
      'passwordResetAttempts': 0,
      'passwordResetRequestedAt': now.toIso8601String(),
    });
    return PasswordResetRequest(
      userId: userId,
      name: '${account['name'] ?? ''}',
      email: '${account['email'] ?? email}',
      code: code,
      expiresAt: expiresAt,
    );
  }

  /// Exchanges a code for the ticket id that authorises the actual reset.
  Future<String> verifyPasswordResetCode(String email, String code) async {
    final account = await findAccountByEmail(email);
    if (account == null) throw Exception('No account found with that email.');
    final userId = '${account['id'] ?? ''}';
    final reference = '${account['passwordResetReference'] ?? ''}';
    final expiresAt = DateTime.tryParse(
      '${account['passwordResetExpiresAt'] ?? ''}',
    );
    final attempts = (account['passwordResetAttempts'] as num?)?.toInt() ?? 0;
    if (reference.isEmpty || expiresAt == null) {
      throw Exception('Request a new reset code first.');
    }
    if (DateTime.now().toUtc().isAfter(expiresAt)) {
      throw Exception('That code has expired. Request a new one.');
    }
    if (attempts >= maxResetAttempts) {
      throw Exception('Too many incorrect codes. Request a new one.');
    }
    final ticketId = _resetTicketId(reference, code.trim());
    final ticket = await getDocument('mobilePasswordResets', ticketId);
    if (ticket == null || ticket['userId'] != userId) {
      await updateDocument('mobileUsers', userId, {
        'passwordResetAttempts': attempts + 1,
      });
      final left = maxResetAttempts - attempts - 1;
      throw Exception(
        left > 0
            ? 'That code is incorrect. $left ${left == 1 ? 'try' : 'tries'} left.'
            : 'That code is incorrect. Request a new one.',
      );
    }
    return ticketId;
  }

  /// Sets a new password and burns the ticket so the code cannot be reused.
  Future<void> completePasswordReset({
    required String email,
    required String ticketId,
    required String newPassword,
  }) async {
    final account = await findAccountByEmail(email);
    if (account == null) throw Exception('No account found with that email.');
    final userId = '${account['id'] ?? ''}';
    final ticket = await getDocument('mobilePasswordResets', ticketId);
    if (ticket == null || ticket['userId'] != userId) {
      throw Exception('That reset session has expired. Start again.');
    }
    final expiresAt = DateTime.tryParse('${ticket['expiresAt'] ?? ''}');
    if (expiresAt == null || DateTime.now().toUtc().isAfter(expiresAt)) {
      throw Exception('That reset session has expired. Start again.');
    }
    await updateDocument('mobileUsers', userId, {
      ..._passwordFields(newPassword),
      'passwordResetReference': '',
      'passwordResetExpiresAt': '',
      'passwordResetAttempts': 0,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    await deleteDocument('mobilePasswordResets', ticketId);
  }

  String _resetTicketId(String reference, String code) =>
      'reset-${sha256.convert(utf8.encode('$reference:$code'))}';

  // ------------------------------------------------------------------- crops

  Future<List<CropListing>> listCropListings({String? farmerId}) async {
    final values = await listCollection('mobileCrops');
    final crops = values.map(CropListing.fromMap).toList();
    final filtered = farmerId == null
        ? crops
        : crops.where((crop) => crop.farmerId == farmerId).toList();
    filtered.sort((a, b) {
      final left = b.createdAt ?? DateTime(1970);
      final right = a.createdAt ?? DateTime(1970);
      return left.compareTo(right);
    });
    return filtered;
  }

  Future<List<Map<String, dynamic>>> listCrops({String? farmerId}) async {
    final values = await listCollection('mobileCrops');
    if (farmerId == null) return values;
    return values.where((item) => item['farmerId'] == farmerId).toList();
  }

  Future<String> createCrop(Map<String, dynamic> crop) async {
    final id = 'crop-${DateTime.now().millisecondsSinceEpoch}-${_token(5)}';
    await _create('mobileCrops', id, {
      ...crop,
      'id': id,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    return id;
  }

  Future<void> updateCrop(String id, Map<String, dynamic> fields) =>
      updateDocument('mobileCrops', id, {
        ...fields,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      });

  Future<void> deleteCrop(String id) => deleteDocument('mobileCrops', id);

  /// Removes [soldKg] from a listing so the marketplace never oversells stock.
  Future<void> reduceCropStock(String cropId, int soldKg) async {
    if (cropId.isEmpty || soldKg <= 0) return;
    final current = await getDocument('mobileCrops', cropId);
    if (current == null) return;
    final remaining = ((current['quantityKg'] as num?)?.round() ?? 0) - soldKg;
    await updateCrop(cropId, {
      'quantityKg': remaining < 0 ? 0 : remaining,
      if (remaining <= 0) 'status': 'sold_out',
    });
  }

  // ------------------------------------------------------------------ orders

  Future<List<AgriOrder>> listAgriOrders({
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
    final orders = values.map(AgriOrder.fromMap).toList();
    orders.sort((a, b) {
      final left = b.createdAt ?? DateTime(1970);
      final right = a.createdAt ?? DateTime(1970);
      return left.compareTo(right);
    });
    return orders;
  }

  Future<AgriOrder?> getOrder(String id) async {
    final value = await getDocument('mobileOrders', id);
    return value == null ? null : AgriOrder.fromMap(value);
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

  Future<String> createOrder(Map<String, dynamic> order) async {
    final now = DateTime.now();
    final id = 'order-${now.millisecondsSinceEpoch}-${_token(5)}';
    final status = '${order['status'] ?? OrderStatus.placed.wire}';
    await _create('mobileOrders', id, {
      ...order,
      'id': id,
      'reference': _orderReference(now),
      'status': status,
      'timeline': {status: now.toUtc().toIso8601String()},
      'createdAt': now.toUtc().toIso8601String(),
    });
    return id;
  }

  /// Moves an order to [status] and stamps the transition on its timeline so
  /// consumers can see when each leg actually happened.
  Future<void> advanceOrder(
    String orderId,
    OrderStatus status, {
    Map<String, dynamic> extra = const {},
    Map<String, DateTime> existingTimeline = const {},
  }) async {
    final now = DateTime.now().toUtc();
    final timeline = <String, dynamic>{
      for (final entry in existingTimeline.entries)
        entry.key: entry.value.toUtc().toIso8601String(),
      status.wire: now.toIso8601String(),
    };
    await updateDocument('mobileOrders', orderId, {
      ...extra,
      'status': status.wire,
      'timeline': timeline,
      'updatedAt': now.toIso8601String(),
    });
  }

  // ------------------------------------------------------------------- trips

  /// Claims every order in a pooled batch for one rider in a single trip.
  Future<String> acceptTrip({
    required List<AgriOrder> orders,
    required String riderId,
    required String riderName,
    required String riderPhone,
    required String riderVehicle,
    required String area,
  }) async {
    final now = DateTime.now();
    final tripId = 'trip-${now.millisecondsSinceEpoch}-${_token(5)}';
    await _create('mobileTrips', tripId, {
      'id': tripId,
      'riderId': riderId,
      'riderName': riderName,
      'area': area,
      'orderIds': orders.map((order) => order.id).toList(),
      'orderCount': orders.length,
      'totalKg': orders.fold<int>(0, (sum, order) => sum + order.quantityKg),
      'payout': orders.fold<int>(0, (sum, order) => sum + order.riderPayout),
      'status': 'active',
      'startedAt': now.toUtc().toIso8601String(),
      'createdAt': now.toUtc().toIso8601String(),
    });
    for (final order in orders) {
      await advanceOrder(
        order.id,
        OrderStatus.riderAssigned,
        existingTimeline: order.timeline,
        extra: {
          'riderId': riderId,
          'riderName': riderName,
          'riderPhone': riderPhone,
          'riderVehicle': riderVehicle,
          'tripId': tripId,
          'riderAssignedAt': now.toUtc().toIso8601String(),
        },
      );
    }
    return tripId;
  }

  Future<List<Map<String, dynamic>>> listTrips({String? riderId}) async {
    final trips = await listCollection('mobileTrips');
    final filtered = riderId == null
        ? trips
        : trips.where((trip) => trip['riderId'] == riderId).toList();
    filtered.sort((a, b) {
      final left = '${b['createdAt'] ?? ''}';
      final right = '${a['createdAt'] ?? ''}';
      return left.compareTo(right);
    });
    return filtered;
  }

  Future<void> completeTrip(String tripId) => updateDocument(
        'mobileTrips',
        tripId,
        {
          'status': 'completed',
          'completedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );

  /// Publishes the rider's live position onto every order in the trip so the
  /// buyers watching those orders all see the same pin move.
  Future<void> broadcastRiderPosition({
    required List<String> orderIds,
    required double latitude,
    required double longitude,
  }) async {
    final stamp = DateTime.now().toUtc().toIso8601String();
    for (final orderId in orderIds) {
      await updateDocument('mobileOrders', orderId, {
        'riderLatitude': latitude,
        'riderLongitude': longitude,
        'riderUpdatedAt': stamp,
      });
    }
  }

  /// Marks a rider available (or not) for new pooled trips.
  Future<void> setRiderAvailability({
    required String riderId,
    required bool online,
    double? latitude,
    double? longitude,
  }) =>
      updateDocument('mobileUsers', riderId, {
        'riderOnline': online,
        if (latitude != null) 'riderLatitude': latitude,
        if (longitude != null) 'riderLongitude': longitude,
        'riderStatusUpdatedAt': DateTime.now().toUtc().toIso8601String(),
      });

  // ----------------------------------------------------------------- reports

  Future<void> createReport(Map<String, dynamic> report) async {
    final id = 'report-${DateTime.now().millisecondsSinceEpoch}-${_token(5)}';
    await _create('mobileReports', id, {
      ...report,
      'id': id,
      'status': 'open',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> listReports() async {
    final reports = await listCollection('mobileReports');
    reports.sort((a, b) => '${b['createdAt']}'.compareTo('${a['createdAt']}'));
    return reports;
  }

  Future<void> resolveReport(String id, String resolution) => updateDocument(
        'mobileReports',
        id,
        {
          'status': 'resolved',
          'resolution': resolution,
          'resolvedAt': DateTime.now().toUtc().toIso8601String(),
        },
      );

  // ------------------------------------------------------------- firestore io

  Future<void> updateDocument(
    String collection,
    String id,
    Map<String, dynamic> fields,
  ) async {
    if (id.isEmpty) throw Exception('Missing document id.');
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

  Future<void> deleteDocument(String collection, String id) async {
    final response = await _client.delete(Uri.parse('$_base/$collection/$id'));
    if (response.statusCode == 404) return;
    _ensureSuccess(response);
  }

  Future<List<Map<String, dynamic>>> listCollection(String collection) async {
    final documents = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final uri = Uri.parse('$_base/$collection').replace(
        queryParameters: {
          'pageSize': '300',
          if (pageToken != null) 'pageToken': pageToken,
        },
      );
      final response = await _client.get(uri);
      _ensureSuccess(response);
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final page = decoded['documents'] as List<dynamic>? ?? const [];
      documents.addAll(
        page.map((value) => _decodeDocument(value as Map<String, dynamic>)),
      );
      pageToken = decoded['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);
    return documents;
  }

  /// Runs a server-side equality filter so a lookup does not have to download
  /// the whole collection.
  Future<List<Map<String, dynamic>>> _queryEquals(
    String collection,
    String field,
    String value, {
    int limit = 1,
  }) async {
    final response = await _client.post(
      Uri.parse('$_base:runQuery'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'structuredQuery': {
          'from': [
            {'collectionId': collection},
          ],
          'where': {
            'fieldFilter': {
              'field': {'fieldPath': field},
              'op': 'EQUAL',
              'value': {'stringValue': value},
            },
          },
          'limit': limit,
        },
      }),
    );
    _ensureSuccess(response);
    final rows = jsonDecode(response.body) as List<dynamic>;
    return [
      for (final row in rows)
        if ((row as Map<String, dynamic>)['document'] != null)
          _decodeDocument(row['document'] as Map<String, dynamic>),
    ];
  }

  Future<Map<String, dynamic>?> getDocument(
    String collection,
    String id,
  ) async {
    if (id.isEmpty) return null;
    final response = await _client.get(Uri.parse('$_base/$collection/$id'));
    if (response.statusCode == 404) return null;
    _ensureSuccess(response);
    return _decodeDocument(jsonDecode(response.body) as Map<String, dynamic>);
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
    if (value.containsKey('timestampValue')) return value['timestampValue'];
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
    if (value is Map) {
      return {
        'mapValue': {
          'fields': _encodeMap(Map<String, dynamic>.from(value)),
        }
      };
    }
    if (value is List) {
      return {
        'arrayValue': {'values': value.map(_encodeValue).toList()}
      };
    }
    return {'stringValue': '$value'};
  }

  String _orderReference(DateTime now) {
    final tail = now.millisecondsSinceEpoch.remainder(10000);
    return '#AG-${tail.toString().padLeft(4, '0')}';
  }

  String _token(int length) {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => alphabet[random.nextInt(alphabet.length)],
    ).join();
  }

  String _numericCode(int length) {
    final random = Random.secure();
    return List.generate(length, (_) => '${random.nextInt(10)}').join();
  }

  // ------------------------------------------------------------- passwords

  /// Work factor for new passwords.
  ///
  /// A single SHA-256 pass is far too cheap: commodity hardware tries billions
  /// of those per second, so a leaked hash is a leaked password. PBKDF2 makes
  /// each guess cost the attacker the same as it costs us. The count is a
  /// compromise — high enough to hurt an attacker, low enough that a mid-range
  /// phone still signs in quickly, since this runs in Dart on the device.
  static const passwordIterations = 60000;
  static const passwordAlgorithm = 'pbkdf2-sha256';

  /// The fields to store for [password]. Written on signup and on reset.
  Map<String, dynamic> _passwordFields(String password) {
    final salt = _token(24);
    return {
      'passwordSalt': salt,
      'passwordHash': _pbkdf2(password, salt, passwordIterations),
      'passwordAlgorithm': passwordAlgorithm,
      'passwordIterations': passwordIterations,
    };
  }

  /// Checks [password] against a stored account, accepting both the current
  /// PBKDF2 format and the original single-pass SHA-256 one.
  bool _passwordMatches(Map<String, dynamic> account, String password) {
    final salt = '${account['passwordSalt'] ?? ''}';
    final stored = '${account['passwordHash'] ?? ''}';
    if (salt.isEmpty || stored.isEmpty) return false;
    if ('${account['passwordAlgorithm'] ?? ''}' == passwordAlgorithm) {
      final rounds = (account['passwordIterations'] as num?)?.toInt() ??
          passwordIterations;
      return _constantTimeEquals(_pbkdf2(password, salt, rounds), stored);
    }
    return _constantTimeEquals(_legacyHash(password, salt), stored);
  }

  /// Accounts created before PBKDF2 are re-hashed the next time their owner
  /// signs in, so the weak hashes drain away without anyone resetting.
  Future<void> _upgradePasswordIfLegacy(
    Map<String, dynamic> account,
    String password,
  ) async {
    if ('${account['passwordAlgorithm'] ?? ''}' == passwordAlgorithm) return;
    final userId = '${account['id'] ?? ''}';
    if (userId.isEmpty) return;
    try {
      final fields = _passwordFields(password);
      await updateDocument('mobileUsers', userId, fields);
      account.addAll(fields);
    } catch (_) {
      // Never block a valid sign-in because the upgrade could not be saved.
    }
  }

  String _pbkdf2(String password, String salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(password));
    // One 32-byte block is enough for a 256-bit key, so this is PBKDF2 with
    // the block index fixed at 1.
    final firstInput = <int>[...utf8.encode(salt), 0, 0, 0, 1];
    var block = hmac.convert(firstInput).bytes;
    final result = List<int>.from(block);
    for (var round = 1; round < iterations; round++) {
      block = hmac.convert(block).bytes;
      for (var i = 0; i < result.length; i++) {
        result[i] ^= block[i];
      }
    }
    return result.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _legacyHash(String password, String salt) =>
      sha256.convert(utf8.encode('$salt:$password')).toString();

  /// Compares without an early exit, so the time taken cannot reveal how much
  /// of the hash was correct.
  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }
}

/// A freshly issued reset code, returned once so it can be emailed.
class PasswordResetRequest {
  const PasswordResetRequest({
    required this.userId,
    required this.name,
    required this.email,
    required this.code,
    required this.expiresAt,
  });

  final String userId;
  final String name;
  final String email;
  final String code;
  final DateTime expiresAt;
}
