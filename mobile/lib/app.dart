import 'dart:async';

import 'package:flutter/material.dart';

import 'models/mobile_user.dart';
import 'screens/admin_screens.dart';
import 'screens/auth_screens.dart';
import 'screens/consumer_screens.dart';
import 'screens/farmer_screens.dart';
import 'screens/rider_screens.dart';
import 'services/local_auth_service.dart';
import 'services/phone_alerts.dart';
import 'services/session.dart';
import 'utils/app_colors.dart';

final authService = LocalAuthService();

class AgriLinkApp extends StatelessWidget {
  const AgriLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AgriLink Mobile',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: green,
          primary: green,
          secondary: orange,
          surface: Colors.white,
        ),
        scaffoldBackgroundColor: canvas,
        fontFamily: 'Nunito',
        textTheme: _headingsInFredoka(),
        appBarTheme: const AppBarTheme(
          backgroundColor: canvas,
          foregroundColor: ink,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFE6EAE2)),
          ),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Colors.white,
          indicatorColor: lightGreen,
          height: 72,
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

/// Headings use Fredoka, the rounded face of the download page and emails;
/// body text stays in Nunito. Fredoka has no peso sign, so prices in a heading
/// fall back to Nunito for that one glyph.
TextTheme _headingsInFredoka() {
  const heading = TextStyle(
    fontFamily: 'Fredoka',
    fontFamilyFallback: ['Nunito'],
    fontWeight: FontWeight.w600,
  );
  return const TextTheme(
    displayLarge: heading,
    displayMedium: heading,
    displaySmall: heading,
    headlineLarge: heading,
    headlineMedium: heading,
    headlineSmall: heading,
    titleLarge: heading,
  );
}

/// Sends a signed-in account to its role shell, or to the review screen while
/// a farmer/rider application is still pending.
void openUserHome(BuildContext context, MobileUser user) {
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => RoleHome(user: user)),
    (_) => false,
  );
}

Future<void> signOut(BuildContext context) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Log out?'),
      content: const Text('You will need your email and password to sign in '
          'again.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await authService.logout();
  if (!context.mounted) return;
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => const AuthWelcomePage()),
    (_) => false,
  );
}

/// Owns the [AppSession] for the signed-in user so every screen underneath
/// shares one refresh signal.
class RoleHome extends StatefulWidget {
  const RoleHome({super.key, required this.user});

  final MobileUser user;

  @override
  State<RoleHome> createState() => _RoleHomeState();
}

class _RoleHomeState extends State<RoleHome> {
  late final AppSession _session = AppSession(widget.user);
  Timer? _approvalPoll;

  @override
  void initState() {
    super.initState();
    _watchForApproval();
  }

  /// Keeps the account's status current: an applicant drops into their role
  /// shell as soon as a superadmin approves them, and a user who is suspended
  /// while signed in is moved to the suspended screen within a poll, instead
  /// of carrying on until they next sign in.
  void _watchForApproval() {
    // Records where this user's updates stand, so only later ones notify.
    unawaited(PhoneAlerts.check(database: authService.database));
    _approvalPoll = Timer.periodic(const Duration(seconds: 20), _refreshApproval);
  }

  Future<void> _refreshApproval(Timer timer) async {
    // The same tick turns new inbox updates into phone notifications while
    // the app is open; a background task covers the app being closed.
    unawaited(PhoneAlerts.check(database: authService.database));
    final Map<String, dynamic>? account;
    try {
      account = await authService.database.getAccount(_session.user.id);
    } catch (_) {
      return; // Offline or a transient failure: try again on the next tick.
    }
    if (!mounted) {
      timer.cancel();
      return;
    }
    if (account == null) return;
    final latest = MobileUser.fromJson(account);
    // Only a change of status rebuilds the shell; other fields are refreshed
    // by the screens that show them.
    if (latest.verificationStatus != _session.user.verificationStatus ||
        latest.statusReason != _session.user.statusReason) {
      _session.updateUser(latest);
    }
  }

  @override
  void dispose() {
    _approvalPoll?.cancel();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _session,
      builder: (context, _) {
        final user = _session.user;
        if (!user.isApproved) {
          return VerificationPendingPage(user: user);
        }
        return switch (user.role) {
          MobileRole.consumer => ConsumerShell(session: _session),
          MobileRole.farmer => FarmerShell(session: _session),
          MobileRole.rider => RiderShell(session: _session),
          MobileRole.superadmin => SuperadminShell(session: _session),
        };
      },
    );
  }
}
