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
      html: _layout(
        preheader: 'Your AgriLink reset code is $code.',
        heading: 'Reset your password',
        body: '''
<p style="margin:0 0 18px;font-size:16px;line-height:1.6;color:#3d4a3e">Hi ${_escape(name)}, use this code in the AgriLink app to set a new password.</p>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0">
  <tr><td align="center" style="background:#fbf3d6;border:2px dashed #e0b84a;border-radius:18px;padding:22px 10px">
    <div style="font-family:'Fredoka',Arial,Helvetica,sans-serif;font-size:40px;font-weight:700;letter-spacing:10px;color:#123d1c">$code</div>
    <div style="margin-top:6px;font-size:13px;color:#7a6a3a">Expires in $minutes minutes &middot; One-time use</div>
  </td></tr>
</table>
<p style="margin:20px 0 0;font-size:14px;line-height:1.6;color:#5a6a5b">Didn't ask for a reset? You can ignore this email. Your password stays the same, and no one can change it without this code.</p>''',
      ),
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
      html: _layout(
        preheader: subject,
        heading: approved
            ? 'You\'re approved!'
            : 'Your application needs another look',
        badge: approved ? 'APPROVED' : 'ACTION NEEDED',
        badgeColor: approved ? '#2d7a10' : '#b42318',
        body: '''
<p style="margin:0 0 12px;font-size:16px;line-height:1.6;color:#3d4a3e">${_escape(greeting)},</p>
<p style="margin:0 0 22px;font-size:16px;line-height:1.6;color:#3d4a3e">${_escape(body)}</p>
<table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td style="border-radius:999px;background:#ffd166">
  <a href="$_siteUrl" style="display:inline-block;padding:13px 26px;font-family:'Fredoka',Arial,Helvetica,sans-serif;font-size:16px;font-weight:700;color:#123d1c;text-decoration:none">Open AgriLink</a>
</td></tr></table>''',
      ),
      templateParams: {
        'to_email': email,
        'to_name': name,
        'code': '',
        'minutes': '',
      },
    );
  }

  static const _siteUrl = 'https://ftmshamel.github.io/AgriLink/';

  /// Names come from sign-up forms, so they are escaped before going into HTML.
  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  /// The shared email frame: the same farm banner, colours and type as the
  /// download page. Built from tables and inline styles because that is all
  /// Gmail and Outlook reliably render; the banner is a hosted image since
  /// mail clients do not draw SVG.
  static String _layout({
    required String preheader,
    required String heading,
    required String body,
    String badge = '',
    String badgeColor = '#2d7a10',
  }) {
    final badgeHtml = badge.isEmpty
        ? ''
        : '<div style="display:inline-block;margin:0 0 12px;padding:4px 12px;'
            'border-radius:999px;background:$badgeColor;color:#ffffff;'
            'font-size:12px;font-weight:700;letter-spacing:1px">$badge</div>';
    return '''
<!doctype html>
<html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<link href="https://fonts.googleapis.com/css2?family=Fredoka:wght@600;700&family=Nunito:wght@400;700&display=swap" rel="stylesheet"></head>
<body style="margin:0;padding:0;background:#fbf8ee">
<div style="display:none;max-height:0;overflow:hidden;opacity:0">${_escape(preheader)}</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#fbf8ee">
<tr><td align="center" style="padding:24px 12px">
  <table role="presentation" width="600" cellpadding="0" cellspacing="0" border="0" style="width:100%;max-width:600px;background:#ffffff;border-radius:24px;overflow:hidden;border:1px solid #e7e1c9">
    <tr><td><img src="${_siteUrl}email-header.jpg" width="600" alt="AgriLink - Fresh from the farm, straight to your door." style="display:block;width:100%;height:auto;border:0"></td></tr>
    <tr><td style="padding:30px 32px 32px;font-family:'Nunito',Arial,Helvetica,sans-serif">
      $badgeHtml
      <h1 style="margin:0 0 14px;font-family:'Fredoka',Arial,Helvetica,sans-serif;font-size:28px;line-height:1.2;font-weight:700;color:#123d1c">${_escape(heading)}</h1>
      $body
    </td></tr>
  </table>
</td></tr>
</table>
</body></html>''';
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
    if (!isConfigured) {
      return const EmailDelivery(EmailDeliveryStatus.notConfigured);
    }

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
            // One EmailJS template serves every message: its subject is
            // {{subject}} and its body {{{message_html}}}.
            'template_params': {
              ...templateParams,
              'subject': subject,
              'message': text,
              'message_html': html,
            },
          }),
        );
      default:
        throw Exception('Unknown email provider "$_provider".');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'The email could not be sent (${response.statusCode}). '
        'Please try again in a moment.',
      );
    }
    return EmailDelivery(EmailDeliveryStatus.sent, provider: provider);
  }
}
