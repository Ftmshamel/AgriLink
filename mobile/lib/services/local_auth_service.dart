import 'package:shared_preferences/shared_preferences.dart';

import '../models/mobile_user.dart';
import 'cloud_database.dart';

class LocalAuthService {
  static const _sessionKey = 'agrilink_mobile_session_v1';

  final CloudDatabase database = CloudDatabase();

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

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }
}
