import 'dart:convert';

import 'package:http/http.dart' as http;

/// How an outgoing message actually ended up being handled.
enum EmailDeliveryStatus {
  /// The transactional provider accepted the message.
  sent,

  /// No provider is configured in this build, so nothing left the device.
  notConfigured,
}

class EmailDelivery {
  const EmailDelivery(this.status, {this.provider = ''});

  final EmailDeliveryStatus status;
  final String provider;

  bool get sent => status == EmailDeliveryStatus.sent;
}

/// Sends transactional mail straight from the app.
///
/// AgriLink has no server, so the provider credentials are compiled in with
/// `--dart-define` instead of living in a backend. Nothing is committed: an
/// unconfigured build reports [EmailDeliveryStatus.notConfigured] and the
/// caller decides what to do with the message it could not send.
///
/// ```powershell
/// flutter run `
///   --dart-define=AGRILINK_EMAIL_PROVIDER=brevo `
///   --dart-define=AGRILINK_EMAIL_API_KEY=xkeysib-... `
///   --dart-define=AGRILINK_EMAIL_SENDER=no-reply@agrilink.ph
/// ```
class EmailService {
  EmailService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _provider =
      String.fromEnvironment('AGRILINK_EMAIL_PROVIDER', defaultValue: '');
  static const _apiKey =
      String.fromEnvironment('AGRILINK_EMAIL_API_KEY', defaultValue: '');
  static const _senderEmail = String.fromEnvironment(
    'AGRILINK_EMAIL_SENDER',
    defaultValue: 'no-reply@agrilink.ph',
  );
  static const _senderName = String.fromEnvironment(
    'AGRILINK_EMAIL_SENDER_NAME',
    defaultValue: 'AgriLink',
  );
  static const _emailjsServiceId =
      String.fromEnvironment('AGRILINK_EMAILJS_SERVICE_ID', defaultValue: '');
  static const _emailjsTemplateId =
      String.fromEnvironment('AGRILINK_EMAILJS_TEMPLATE_ID', defaultValue: '');
  static const _emailjsPublicKey =
      String.fromEnvironment('AGRILINK_EMAILJS_PUBLIC_KEY', defaultValue: '');

  static bool get isConfigured =>
      _provider.isNotEmpty &&
      (_provider.toLowerCase() == 'emailjs'
          ? _emailjsServiceId.isNotEmpty &&
              _emailjsTemplateId.isNotEmpty &&
              _emailjsPublicKey.isNotEmpty
          : _apiKey.isNotEmpty);

  /// Mails a one-time password-reset [code] to [email].
  ///
  /// Throws when a provider is configured but rejects the message, so the
  /// caller never tells someone to check an inbox that will stay empty.
  Future<EmailDelivery> sendPasswordResetCode({
    required String email,
    required String name,
    required String code,
    required Duration validFor,
  }) {
    final minutes = validFor.inMinutes;
    return _send(
      toEmail: email,
      toName: name,
      subject: 'Your AgriLink password reset code',
      text: 'Hi $name,\n\n'
          'Use this code to reset your AgriLink password:\n\n'
          '    $code\n\n'
          'The code expires in $minutes minutes and can only be used once. '
          'If you did not ask for a reset, you can ignore this message and '
          'your password stays the same.\n\n'
          'AgriLink • Fresh harvest. Fair trade.',
      html: '''
<div style="font-family:Arial,Helvetica,sans-serif;color:#1A1F17;max-width:520px">
  <h2 style="color:#2E7D32;margin:0 0 6px">AgriLink password reset</h2>
  <p style="margin:0 0 18px;color:#6B7A66">Hi $name, use the code below to set a new password.</p>
  <div style="background:#EEF6E8;border:1px solid #CFE5C5;border-radius:14px;padding:18px;text-align:center">
    <div style="font-size:32px;font-weight:900;letter-spacing:8px;color:#2E7D32">$code</div>
  </div>
  <p style="margin:18px 0 0;color:#6B7A66;font-size:13px">
    This code expires in $minutes minutes and can only be used once.
    If you did not request a reset, ignore this email — your password will not change.
  </p>
</div>''',
      templateParams: {
        'to_email': email,
        'to_name': name,
        'code': code,
        'minutes': '$minutes',
      },
    );
  }

  /// Tells an applicant what the superadmin decided.
  ///
  /// The review screen promises the applicant they will hear back, so this is
  /// what keeps that promise. A build with no mail provider simply reports
  /// [EmailDeliveryStatus.notConfigured] and the decision still stands.
  Future<EmailDelivery> sendVerificationDecision({
    required String email,
    required String name,
    required bool approved,
    required String role,
  }) {
    final greeting = name.isEmpty ? 'Hello' : 'Hi $name';
    final subject = approved
        ? 'Your AgriLink $role account is approved'
        : 'About your AgriLink $role application';
    final body = approved
        ? 'Your requirements have been reviewed and your account is now active. '
            'Open AgriLink and you can start trading straight away.'
        : 'A reviewer could not approve the requirements you submitted. Open '
            'AgriLink, go to your application screen, and tap "Resubmit '
            'requirements" to upload clearer photos.';
    return _send(
      toEmail: email,
      toName: name,
      subject: subject,
      text: '$greeting,\n\n$body\n\nAgriLink • Fresh harvest. Fair trade.',
      html: '''
<div style="font-family:Arial,Helvetica,sans-serif;color:#1A1F17;max-width:520px">
  <h2 style="color:${approved ? '#2E7D32' : '#B42318'};margin:0 0 6px">$subject</h2>
  <p style="margin:0 0 12px;color:#6B7A66">$greeting,</p>
  <p style="margin:0 0 18px;line-height:1.5">$body</p>
  <p style="margin:0;color:#6B7A66;font-size:13px">AgriLink • Fresh harvest. Fair trade.</p>
</div>''',
      templateParams: {
        'to_email': email,
        'to_name': name,
        'code': '',
        'minutes': '',
      },
    );
  }

  Future<EmailDelivery> _send({
    required String toEmail,
    required String toName,
    required String subject,
    required String text,
    required String html,
    required Map<String, String> templateParams,
  }) async {
    final provider = _provider.trim().toLowerCase();
    if (!isConfigured) return const EmailDelivery(EmailDeliveryStatus.notConfigured);

    final http.Response response;
    switch (provider) {
      case 'brevo':
      case 'sendinblue':
        response = await _client.post(
          Uri.https('api.brevo.com', '/v3/smtp/email'),
          headers: {
            'api-key': _apiKey,
            'accept': 'application/json',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'sender': {'name': _senderName, 'email': _senderEmail},
            'to': [
              {'email': toEmail, if (toName.isNotEmpty) 'name': toName},
            ],
            'subject': subject,
            'textContent': text,
            'htmlContent': html,
          }),
        );
      case 'resend':
        response = await _client.post(
          Uri.https('api.resend.com', '/emails'),
          headers: {
            'authorization': 'Bearer $_apiKey',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'from': '$_senderName <$_senderEmail>',
            'to': [toEmail],
            'subject': subject,
            'text': text,
            'html': html,
          }),
        );
      case 'emailjs':
        response = await _client.post(
          Uri.https('api.emailjs.com', '/api/v1.0/email/send'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'service_id': _emailjsServiceId,
            'template_id': _emailjsTemplateId,
            'user_id': _emailjsPublicKey,
            if (_apiKey.isNotEmpty) 'accessToken': _apiKey,
            'template_params': {...templateParams, 'subject': subject},
          }),
        );
      default:
        throw Exception('Unknown email provider "$_provider".');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'The reset email could not be sent (${response.statusCode}). '
        'Please try again in a moment.',
      );
    }
    return EmailDelivery(EmailDeliveryStatus.sent, provider: provider);
  }
}
