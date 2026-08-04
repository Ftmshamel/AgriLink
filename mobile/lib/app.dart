import 'package:flutter/material.dart';

import 'models/mobile_user.dart';
import 'screens/admin_screens.dart';
import 'screens/auth_screens.dart';
import 'screens/consumer_screens.dart';
import 'screens/farmer_screens.dart';
import 'screens/rider_screens.dart';
import 'services/local_auth_service.dart';
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
        fontFamily: 'Roboto',
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

  @override
  void dispose() {
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
