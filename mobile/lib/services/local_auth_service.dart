import 'package:shared_preferences/shared_preferences.dart';

import '../models/mobile_user.dart';
import 'cloud_database.dart';
import 'email_service.dart';

/// The outcome of asking for a reset code, including the code itself when the
/// build has no mail provider and therefore could not send it.
class PasswordResetTicket {
  const PasswordResetTicket({
    required this.email,
    required this.expiresAt,
    required this.delivered,
    this.previewCode,
  });

  final String email;
  final DateTime expiresAt;

  /// Whether the code actually left the device as an email.
  final bool delivered;

  /// Only populated on unconfigured builds so the flow stays testable — see
  /// [EmailService] for how to switch real delivery on.
  final String? previewCode;
}

class LocalAuthService {
  static const _sessionKey = 'agrilink_mobile_session_v1';

  final CloudDatabase database = CloudDatabase();
  final EmailService email = EmailService();

  Future<MobileUser?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(_sessionKey);
    if (userId == null) return null;
    final account = await database.getAccount(userId);
    return account == null ? null : MobileUser.fromJson(account);
  }

  Future<MobileUser> login(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final account = await database.authenticate(email, password);
    final found = MobileUser.fromJson(account);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, found.id);
    return found;
  }

  Future<MobileUser> loginSuperadmin(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 550));
    Map<String, dynamic> account;
    try {
      account = await database.authenticate(email, password, staffOnly: true);
    } catch (_) {
      account = await database.migrateLegacyStaff(email, password);
    }
    final admin = MobileUser.fromJson(account);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, admin.id);
    return admin;
  }

  Future<MobileUser> signup(MobileUser user) async {
    await Future<void>.delayed(const Duration(milliseconds: 550));
    final account = await database.createAccount(
      name: user.name,
      email: user.email,
      password: user.password,
      phone: user.phone,
      role: user.role.name,
      profile: user.verification,
    );
    final saved = MobileUser.fromJson(account);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, saved.id);
    return saved;
  }

  /// Step 1 — mint a code for [emailAddress] and mail it to the account owner.
  Future<PasswordResetTicket> requestPasswordReset(String emailAddress) async {
    final request = await database.createPasswordReset(emailAddress);
    final delivery = await email.sendPasswordResetCode(
      email: request.email,
      name: request.name.isEmpty ? 'there' : request.name,
      code: request.code,
      validFor: CloudDatabase.resetCodeLifetime,
    );
    return PasswordResetTicket(
      email: request.email,
      expiresAt: request.expiresAt,
      delivered: delivery.sent,
      previewCode: delivery.sent ? null : request.code,
    );
  }

  /// Step 2 — trade the emailed code for the id that authorises the reset.
  Future<String> verifyPasswordResetCode(String emailAddress, String code) =>
      database.verifyPasswordResetCode(emailAddress, code);

  /// Step 3 — store the new password and burn the ticket.
  Future<void> completePasswordReset({
    required String emailAddress,
    required String ticketId,
    required String newPassword,
  }) =>
      database.completePasswordReset(
        email: emailAddress,
        ticketId: ticketId,
        newPassword: newPassword,
      );

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }
}
