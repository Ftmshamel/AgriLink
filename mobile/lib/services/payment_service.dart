import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Raised when an invoice cannot be created or read, already worded for the
/// buyer rather than left as a status code.
class PaymentException implements Exception {
  const PaymentException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One Xendit invoice, as much of it as the app needs.
class PaymentInvoice {
  const PaymentInvoice({
    required this.id,
    required this.url,
    required this.reference,
    required this.paid,
  });

  factory PaymentInvoice.fromMap(Map<String, dynamic> map) => PaymentInvoice(
        id: '${map['id'] ?? ''}',
        url: '${map['url'] ?? ''}',
        reference: '${map['reference'] ?? ''}',
        paid: map['paid'] == true,
      );

  final String id;

  /// Where the buyer pays. Opened outside the app.
  final String url;
  final String reference;
  final bool paid;
}

/// What Xendit says about an invoice right now.
class PaymentStatus {
  const PaymentStatus({required this.paid, required this.channel});

  final bool paid;

  /// The channel the buyer actually used - GCash, a card, a bank. Empty until
  /// they have paid, which is why the app cannot ask for it up front.
  final String channel;
}

/// Talks to the AgriLink payments worker, which is the only part of the system
/// that holds the Xendit secret key.
///
/// The app deliberately knows nothing about that key: anything shipped inside
/// an APK can be read by unzipping it. So the app asks the worker for an
/// invoice, sends the buyer to the URL it gets back, and afterwards asks the
/// worker whether Xendit has marked it paid. Nothing here is trusted to say a
/// payment happened - only Xendit can.
class PaymentService {
  PaymentService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Printed by `wrangler deploy`. While this is empty the app falls back to
  /// the manual reference-number checkout, so a build without a worker still
  /// works.
  static const baseUrl = String.fromEnvironment('AGRILINK_PAYMENTS_URL');

  /// Shared string the worker checks. It ships inside the APK, so it only
  /// stops a stranger who finds the URL - it is not user authentication.
  static const appToken = String.fromEnvironment('AGRILINK_PAYMENTS_TOKEN');

  static bool get enabled => baseUrl.isNotEmpty;

  static const _timeout = Duration(seconds: 20);

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (appToken.isNotEmpty) 'x-agrilink-token': appToken,
      };

  /// Asks the worker to open an invoice for [amount] pesos.
  ///
  /// [reference] becomes Xendit's external id, which is what ties the payment
  /// back to the order without the worker storing anything.
  Future<PaymentInvoice> createInvoice({
    required int amount,
    required String reference,
    required String description,
  }) async {
    final body = await _send(
      () => _client
          .post(
            Uri.parse('$baseUrl/invoice'),
            headers: _headers,
            body: jsonEncode({
              'amount': amount,
              'reference': reference,
              'description': description,
            }),
          )
          .timeout(_timeout),
    );
    final invoice = PaymentInvoice.fromMap(body);
    if (invoice.url.isEmpty) {
      throw const PaymentException(
        'The payment service did not return a checkout page.',
      );
    }
    return invoice;
  }

  /// Whether Xendit has seen the money yet, and how it arrived.
  Future<PaymentStatus> check(String invoiceId) async {
    final body = await _send(
      () => _client
          .get(
            Uri.parse('$baseUrl/invoice?id=${Uri.encodeQueryComponent(invoiceId)}'),
            headers: _headers,
          )
          .timeout(_timeout),
    );
    final channel = '${body['channel'] ?? ''}'.trim();
    final method = '${body['method'] ?? ''}'.trim();
    return PaymentStatus(
      paid: body['paid'] == true,
      channel: channel.isNotEmpty ? channel : method,
    );
  }

  /// One request, one JSON decode, and every failure turned into something
  /// that means anything on screen.
  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    final http.Response response;
    try {
      response = await request();
    } on TimeoutException {
      throw const PaymentException(
        'The payment service took too long to respond. Try again.',
      );
    } on SocketException {
      throw const PaymentException(
        'No internet connection. Check your network and try again.',
      );
    } on http.ClientException {
      throw const PaymentException(
        'Could not reach the payment service. Check your connection.',
      );
    }

    Map<String, dynamic> decoded = const {};
    try {
      final value = jsonDecode(response.body);
      if (value is Map<String, dynamic>) decoded = value;
    } on FormatException {
      throw const PaymentException(
        'The payment service returned an unreadable response.',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      // The worker forwards Xendit's own wording, which says far more than the
      // status code does.
      final detail = '${decoded['error'] ?? ''}'.trim();
      throw PaymentException(
        detail.isEmpty
            ? 'Payment request failed (${response.statusCode}).'
            : detail,
      );
    }
    return decoded;
  }
}
