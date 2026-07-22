import 'dart:convert';
import 'dart:async';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const AgriLinkApp());

const green = Color(0xFF2D7A10);
const darkGreen = Color(0xFF174A0A);
const lightGreen = Color(0xFFEDF7E6);
const orange = Color(0xFFF08800);
const ink = Color(0xFF172018);
const muted = Color(0xFF667085);
const canvas = Color(0xFFF6F8F4);

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

enum MobileRole { consumer, rider }

class MobileUser {
  const MobileUser({
    required this.name,
    required this.email,
    required this.password,
    required this.phone,
    required this.role,
  });

  final String name;
  final String email;
  final String password;
  final String phone;
  final MobileRole role;

  Map<String, dynamic> toJson() => {
        'name': name,
        'email': email,
        'password': password,
        'phone': phone,
        'role': role.name,
      };

  factory MobileUser.fromJson(Map<String, dynamic> json) => MobileUser(
        name: json['name'] as String,
        email: json['email'] as String,
        password: json['password'] as String,
        phone: json['phone'] as String? ?? '',
        role: json['role'] == 'rider' ? MobileRole.rider : MobileRole.consumer,
      );
}

class LocalAuthService {
  static const _accountsKey = 'agrilink_mobile_accounts_v1';
  static const _sessionKey = 'agrilink_mobile_session_v1';

  Future<List<MobileUser>> _accounts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_accountsKey);
    if (raw == null) return [];
    final values = jsonDecode(raw) as List<dynamic>;
    return values
        .map((item) => MobileUser.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<MobileUser?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_sessionKey);
    if (email == null) return null;
    final users = await _accounts();
    for (final user in users) {
      if (user.email.toLowerCase() == email.toLowerCase()) return user;
    }
    return null;
  }

  Future<MobileUser> login(String email, String password) async {
    await Future<void>.delayed(const Duration(milliseconds: 450));
    final users = await _accounts();
    MobileUser? found;
    for (final user in users) {
      if (user.email.toLowerCase() == email.trim().toLowerCase()) {
        found = user;
        break;
      }
    }
    if (found == null) throw Exception('No account found with that email.');
    if (found.password != password) throw Exception('Incorrect password.');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, found.email);
    return found;
  }

  Future<MobileUser> signup(MobileUser user) async {
    await Future<void>.delayed(const Duration(milliseconds: 550));
    final users = await _accounts();
    if (users.any(
      (item) => item.email.toLowerCase() == user.email.toLowerCase(),
    )) {
      throw Exception('An account with that email already exists.');
    }
    users.add(user);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _accountsKey,
      jsonEncode(users.map((item) => item.toJson()).toList()),
    );
    await prefs.setString(_sessionKey, user.email);
    return user;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }
}

final authService = LocalAuthService();

void openUserHome(BuildContext context, MobileUser user) {
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(
      builder: (_) => user.role == MobileRole.consumer
          ? ConsumerShell(user: user)
          : RiderShell(user: user),
    ),
    (_) => false,
  );
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final results = await Future.wait<dynamic>([
      authService.restoreSession(),
      Future<void>.delayed(const Duration(milliseconds: 1500)),
    ]);
    if (!mounted) return;
    final user = results.first as MobileUser?;
    if (user != null) {
      openUserHome(context, user);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AuthWelcomePage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/logo.png', width: 190, height: 190),
              const SizedBox(height: 22),
              const Text(
                'Fresh harvest. Fair trade.',
                style: TextStyle(color: muted, fontSize: 15),
              ),
              const SizedBox(height: 34),
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AuthWelcomePage extends StatelessWidget {
  const AuthWelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkGreen,
      body: Stack(
        children: [
          Positioned(
            right: -70,
            top: 70,
            child: Icon(
              Icons.eco,
              size: 260,
              color: Colors.white.withValues(alpha: .045),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  flex: 6,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 66,
                              height: 66,
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Image.asset('assets/logo.png'),
                            ),
                            const SizedBox(width: 12),
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'AgriLink',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -.5,
                                  ),
                                ),
                                Text(
                                  'Connecting Agriculture',
                                  style: TextStyle(
                                    color: Color(0xFFA8D98E),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: orange.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(99),
                            border: Border.all(
                              color: orange.withValues(alpha: .45),
                            ),
                          ),
                          child: const Text(
                            'FARM-TO-TABLE • PHILIPPINES',
                            style: TextStyle(
                              color: Color(0xFFFFB84D),
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .8,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Fresh harvests.\nSmarter deliveries.',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 38,
                            height: 1.08,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -1.3,
                          ),
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          'Buy directly from trusted farms or earn as an AgriLink delivery partner.',
                          style: TextStyle(
                            color: Color(0xFFCFE5C5),
                            fontSize: 15,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: 22),
                        const Wrap(
                          spacing: 9,
                          runSpacing: 9,
                          children: [
                            _HeroChip(
                                icon: Icons.verified, text: 'Verified farms'),
                            _HeroChip(
                                icon: Icons.route, text: 'Pooled delivery'),
                            _HeroChip(
                                icon: Icons.savings_outlined,
                                text: 'Fair prices'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(32)),
                  ),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const LoginPage()),
                          ),
                          icon: const Icon(Icons.login),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.all(17),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          label: const Text(
                            'Log in to AgriLink',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 11),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const SignupPage()),
                          ),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.all(16),
                            side: const BorderSide(color: Color(0xFFD0D9CC)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text(
                            'Create an account',
                            style: TextStyle(
                              color: darkGreen,
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text(
                        'For Consumers and Riders',
                        style: TextStyle(
                          color: muted,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: .13)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF7BC35A), size: 15),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _showPassword = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await authService.login(_email.text, _password.text);
      if (mounted) openUserHome(context, user);
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            const _AuthIcon(icon: Icons.eco_outlined),
            const SizedBox(height: 16),
            const Text(
              'Welcome back',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            const Text(
              'Log in to your AgriLink account.',
              style: TextStyle(color: muted, fontSize: 15),
            ),
            const SizedBox(height: 24),
            if (_error != null) ...[
              _AuthError(message: _error!),
              const SizedBox(height: 16),
            ],
            _AuthField(
              controller: _email,
              label: 'Email address',
              hint: 'you@example.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                if (value == null || !value.contains('@')) {
                  return 'Enter a valid email address.';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Password',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const AlertDialog(
                      title: Text('Password reset'),
                      content: Text(
                        'Password recovery will be enabled with the cloud authentication service.',
                      ),
                    ),
                  ),
                  child: const Text('Forgot password?'),
                ),
              ],
            ),
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your password.'
                  : null,
              decoration: _fieldDecoration(
                hint: '••••••••',
                icon: Icons.lock_outline,
                suffix: IconButton(
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.login),
              label: Padding(
                padding: const EdgeInsets.all(15),
                child: Text(_loading ? 'Logging in…' : 'Log in'),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('No account yet?', style: TextStyle(color: muted)),
                TextButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const SignupPage()),
                  ),
                  child: const Text('Create one free'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  MobileRole _role = MobileRole.consumer;
  bool _showPassword = false;
  bool _agreed = false;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreed) {
      setState(() => _error = 'Please accept the Terms and Privacy Policy.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = await authService.signup(
        MobileUser(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          phone: _phone.text.trim(),
          role: _role,
        ),
      );
      if (mounted) openUserHome(context, user);
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          children: [
            const Text(
              'Create your account',
              style: TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 5),
            const Text(
              'Join AgriLink as a buyer or delivery partner.',
              style: TextStyle(color: muted, fontSize: 15),
            ),
            const SizedBox(height: 22),
            if (_error != null) ...[
              _AuthError(message: _error!),
              const SizedBox(height: 16),
            ],
            const Text(
              'I am a…',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: _SignupRoleCard(
                    icon: Icons.shopping_basket_outlined,
                    title: 'Consumer',
                    subtitle: 'Restaurant / buyer',
                    selected: _role == MobileRole.consumer,
                    onTap: () => setState(() => _role = MobileRole.consumer),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SignupRoleCard(
                    icon: Icons.local_shipping_outlined,
                    title: 'Rider',
                    subtitle: 'Delivery partner',
                    selected: _role == MobileRole.rider,
                    onTap: () => setState(() => _role = MobileRole.rider),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _AuthField(
              controller: _name,
              label: _role == MobileRole.consumer
                  ? 'Full name / Business name'
                  : 'Full name',
              hint: _role == MobileRole.consumer
                  ? 'e.g. Maria’s Kitchen'
                  : 'e.g. Carlo Mendoza',
              icon: Icons.person_outline,
              validator: _required('Enter your name.'),
            ),
            const SizedBox(height: 15),
            _AuthField(
              controller: _phone,
              label: 'Phone number',
              hint: '+63 9XX XXX XXXX',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              validator: (value) => value == null || value.trim().length < 10
                  ? 'Enter a valid phone number.'
                  : null,
            ),
            const SizedBox(height: 15),
            _AuthField(
              controller: _email,
              label: 'Email address',
              hint: 'you@example.com',
              icon: Icons.email_outlined,
              keyboardType: TextInputType.emailAddress,
              validator: (value) => value == null || !value.contains('@')
                  ? 'Enter a valid email address.'
                  : null,
            ),
            const SizedBox(height: 15),
            const Text(
              'Password',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 7),
            TextFormField(
              controller: _password,
              obscureText: !_showPassword,
              validator: (value) => value == null || value.length < 6
                  ? 'Use at least 6 characters.'
                  : null,
              decoration: _fieldDecoration(
                hint: 'Minimum 6 characters',
                icon: Icons.lock_outline,
                suffix: IconButton(
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 15),
            _AuthField(
              controller: _confirm,
              label: 'Confirm password',
              hint: 'Repeat your password',
              icon: Icons.lock_reset,
              obscureText: !_showPassword,
              validator: (value) =>
                  value != _password.text ? 'Passwords do not match.' : null,
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              value: _agreed,
              onChanged: (value) => setState(() => _agreed = value ?? false),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'I agree to the Terms of Service and Privacy Policy.',
                style: TextStyle(fontSize: 13, color: muted),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.person_add_alt_1),
              label: Padding(
                padding: const EdgeInsets.all(15),
                child: Text(_loading ? 'Creating account…' : 'Create account'),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Already registered?',
                    style: TextStyle(color: muted)),
                TextButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginPage()),
                  ),
                  child: const Text('Log in'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  FormFieldValidator<String> _required(String message) =>
      (value) => value == null || value.trim().isEmpty ? message : null;
}

class _AuthScaffold extends StatelessWidget {
  const _AuthScaffold({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkGreen,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 22, 16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withValues(alpha: .10),
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 46,
                    height: 46,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Image.asset('assets/logo.png'),
                  ),
                  const SizedBox(width: 10),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AgriLink',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'Secure account access',
                        style: TextStyle(
                          color: Color(0xFFA8D98E),
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
                ),
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthIcon extends StatelessWidget {
  const _AuthIcon({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: 54,
        height: 54,
        decoration: BoxDecoration(
          color: green,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, color: Colors.white, size: 27),
      ),
    );
  }
}

class _AuthField extends StatelessWidget {
  const _AuthField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
  });
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final FormFieldValidator<String>? validator;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 7),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          validator: validator,
          decoration: _fieldDecoration(hint: hint, icon: icon),
        ),
      ],
    );
  }
}

InputDecoration _fieldDecoration({
  required String hint,
  required IconData icon,
  Widget? suffix,
}) {
  return InputDecoration(
    hintText: hint,
    prefixIcon: Icon(icon),
    suffixIcon: suffix,
    filled: true,
    fillColor: Colors.white,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Color(0xFFD9E0D6), width: 1.5),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: green, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Colors.red, width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: Colors.red, width: 2),
    ),
  );
}

class _AuthError extends StatelessWidget {
  const _AuthError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFCDD3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 20),
          const SizedBox(width: 9),
          Expanded(
              child: Text(message, style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
  }
}

class _SignupRoleCard extends StatelessWidget {
  const _SignupRoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? lightGreen : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? green : const Color(0xFFD9E0D6),
            width: selected ? 2 : 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: selected ? green : muted),
            const SizedBox(height: 9),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            Text(subtitle, style: const TextStyle(color: muted, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class RoleGate extends StatefulWidget {
  const RoleGate({super.key});

  @override
  State<RoleGate> createState() => _RoleGateState();
}

class _RoleGateState extends State<RoleGate> {
  bool _showRoles = false;

  void _open(Widget page) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: !_showRoles
                ? _Welcome(
                    key: const ValueKey('welcome'),
                    onStart: () => setState(() => _showRoles = true),
                  )
                : _Roles(
                    key: const ValueKey('roles'),
                    onConsumer: () => _open(
                      const ConsumerShell(
                        user: MobileUser(
                          name: 'Consumer',
                          email: 'consumer@agrilink.ph',
                          password: '',
                          phone: '',
                          role: MobileRole.consumer,
                        ),
                      ),
                    ),
                    onRider: () => _open(
                      const RiderShell(
                        user: MobileUser(
                          name: 'Rider',
                          email: 'rider@agrilink.ph',
                          password: '',
                          phone: '',
                          role: MobileRole.rider,
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({super.key, required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(),
        Container(
          width: 112,
          height: 112,
          decoration: BoxDecoration(
            color: green,
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [
              BoxShadow(
                color: Color(0x332D7A10),
                blurRadius: 30,
                offset: Offset(0, 14),
              ),
            ],
          ),
          child: const Icon(Icons.eco_rounded, color: Colors.white, size: 62),
        ),
        const SizedBox(height: 30),
        const Text(
          'AgriLink',
          style: TextStyle(
            color: darkGreen,
            fontSize: 40,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.5,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Fresh harvest. Fair trade.\nDelivered together.',
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 17, height: 1.5),
        ),
        const Spacer(),
        const _Pill(
          icon: Icons.location_on_outlined,
          text: 'Connecting farms across Central Luzon',
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: onStart,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.all(17),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Explore mockup',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}

class _Roles extends StatelessWidget {
  const _Roles({
    super.key,
    required this.onConsumer,
    required this.onRider,
  });
  final VoidCallback onConsumer;
  final VoidCallback onRider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const _Brand(),
        const Spacer(),
        const Text(
          'Continue as',
          style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose a role to preview its mobile experience.',
          style: TextStyle(color: muted, fontSize: 16),
        ),
        const SizedBox(height: 28),
        _RoleCard(
          icon: Icons.shopping_bag_outlined,
          title: 'Consumer',
          subtitle: 'Buy fresh crops in bulk and track deliveries.',
          color: green,
          onTap: onConsumer,
        ),
        const SizedBox(height: 16),
        _RoleCard(
          icon: Icons.local_shipping_outlined,
          title: 'Rider',
          subtitle: 'Pool nearby orders and deliver in one trip.',
          color: orange,
          onTap: onRider,
        ),
        const Spacer(flex: 2),
        const Center(
          child: Text(
            'UI MOCKUP • LOCAL DEMO DATA',
            style: TextStyle(
              color: muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, color: color, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(color: muted, height: 1.35),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class ConsumerShell extends StatefulWidget {
  const ConsumerShell({super.key, required this.user});
  final MobileUser user;

  @override
  State<ConsumerShell> createState() => _ConsumerShellState();
}

class _ConsumerShellState extends State<ConsumerShell> {
  int _index = 0;
  int _cart = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      ConsumerHome(
        user: widget.user,
        cartCount: _cart,
        onAdd: () => setState(() => _cart++),
        onCart: () => _showCart(context),
      ),
      const ConsumerOrders(),
      ConsumerProfile(user: widget.user),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront),
            label: 'Market',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }

  void _showCart(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your bulk order',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 18),
            const _LineItem(
              emoji: '🥬',
              name: 'Fresh Pechay',
              detail: '20 kg × ₱42',
              price: '₱840',
            ),
            const Divider(height: 30),
            const _Money(label: 'Subtotal', value: '₱840'),
            const _Money(label: 'Pooled delivery', value: '₱120'),
            const SizedBox(height: 8),
            const _Money(label: 'Total', value: '₱960', strong: true),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Mock order placed successfully!'),
                    ),
                  );
                  setState(() => _cart = 0);
                },
                child: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('Place order'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ConsumerHome extends StatelessWidget {
  const ConsumerHome({
    super.key,
    required this.user,
    required this.cartCount,
    required this.onAdd,
    required this.onCart,
  });
  final MobileUser user;
  final int cartCount;
  final VoidCallback onAdd;
  final VoidCallback onCart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Good morning,', style: TextStyle(color: muted)),
                  Text(
                    user.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Badge(
              isLabelVisible: cartCount > 0,
              label: Text('$cartCount'),
              child: IconButton.filledTonal(
                onPressed: onCart,
                icon: const Icon(Icons.shopping_cart_outlined),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        TextField(
          decoration: InputDecoration(
            hintText: 'Search crops or farms',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: const Icon(Icons.tune),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [darkGreen, green]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FARM-TO-TABLE',
                      style: TextStyle(
                        color: Color(0xFFBDE7A9),
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.3,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Save more when\nyou buy in bulk.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Direct prices from verified farms',
                      style: TextStyle(color: Color(0xFFD8EAD1)),
                    ),
                  ],
                ),
              ),
              Text('🧺', style: TextStyle(fontSize: 66)),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const _SectionTitle(title: 'Browse categories', action: 'See all'),
        const SizedBox(height: 12),
        const SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _Category(emoji: '🥬', label: 'Leafy'),
              _Category(emoji: '🍅', label: 'Vegetables'),
              _Category(emoji: '🥭', label: 'Fruits'),
              _Category(emoji: '🌾', label: 'Grains'),
            ],
          ),
        ),
        const SizedBox(height: 26),
        const _SectionTitle(title: 'Fresh near you', action: 'View map'),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: .66,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: crops.length,
          itemBuilder: (context, index) {
            final crop = crops[index];
            return _CropCard(
              crop: crop,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ProductDetails(crop: crop, onAdd: onAdd),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class ProductDetails extends StatefulWidget {
  const ProductDetails({super.key, required this.crop, required this.onAdd});
  final Crop crop;
  final VoidCallback onAdd;

  @override
  State<ProductDetails> createState() => _ProductDetailsState();
}

class _ProductDetailsState extends State<ProductDetails> {
  int quantity = 20;

  @override
  Widget build(BuildContext context) {
    final total = widget.crop.price * quantity;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.favorite_border)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          Container(
            height: 250,
            decoration: BoxDecoration(
              color: widget.crop.tint,
              borderRadius: BorderRadius.circular(28),
            ),
            alignment: Alignment.center,
            child:
                Text(widget.crop.emoji, style: const TextStyle(fontSize: 120)),
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.crop.name,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              _Pill(
                icon: Icons.verified,
                text: 'Verified',
                color: green,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '₱${widget.crop.price}/kg',
            style: const TextStyle(
              color: green,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: lightGreen,
                    child: Text(widget.crop.farmer.substring(0, 1)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.crop.farmer,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${widget.crop.location} • ${widget.crop.distance}',
                          style: const TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Harvest details',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
          ),
          const SizedBox(height: 10),
          const Text(
            'Freshly harvested this morning. Carefully sorted and packed for restaurants, retailers, and bulk buyers.',
            style: TextStyle(color: muted, height: 1.55),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Quantity',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    Text('Minimum 10 kg', style: TextStyle(color: muted)),
                  ],
                ),
              ),
              IconButton.filledTonal(
                onPressed:
                    quantity > 10 ? () => setState(() => quantity -= 10) : null,
                icon: const Icon(Icons.remove),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  '$quantity kg',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton.filledTonal(
                onPressed: () => setState(() => quantity += 10),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () {
              widget.onAdd();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${widget.crop.name} added to cart')),
              );
            },
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            child: Text('Add to cart  •  ₱${total.toStringAsFixed(0)}'),
          ),
        ],
      ),
    );
  }
}

class ConsumerOrders extends StatelessWidget {
  const ConsumerOrders({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        const _PageHeader(
          eyebrow: 'MY PURCHASES',
          title: 'Orders',
          subtitle: 'Track every harvest from farm to your door.',
        ),
        const SizedBox(height: 22),
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DeliveryTracking()),
            ),
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Pill(
                        icon: Icons.local_shipping,
                        text: 'IN TRANSIT',
                        color: green,
                      ),
                      Spacer(),
                      Text(
                        '#AG-1048',
                        style: TextStyle(
                            color: muted, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  SizedBox(height: 18),
                  _LineItem(
                    emoji: '🥬',
                    name: 'Pechay & Tomatoes',
                    detail: '35 kg • 2 farms',
                    price: '₱1,720',
                  ),
                  Divider(height: 28),
                  Row(
                    children: [
                      Icon(Icons.schedule, color: green, size: 19),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Arriving today, 2:30–3:00 PM',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      Icon(Icons.chevron_right),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        const _PastOrder(
          id: '#AG-1039',
          name: 'Sweet Mangoes',
          detail: '40 kg • Delivered Jul 16',
          price: '₱3,200',
          emoji: '🥭',
        ),
        const SizedBox(height: 14),
        const _PastOrder(
          id: '#AG-1021',
          name: 'Red Onions',
          detail: '25 kg • Delivered Jul 10',
          price: '₱1,875',
          emoji: '🧅',
        ),
      ],
    );
  }
}

class DeliveryTracking extends StatelessWidget {
  const DeliveryTracking({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Track delivery')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          const _LiveOsmMap(riderMode: false),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                children: [
                  const Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: lightGreen,
                        child: Icon(Icons.person, color: green),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Carlo Mendoza',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              'Rider • Honda TMX • ABC 1234',
                              style: TextStyle(color: muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.phone_outlined, color: green),
                    ],
                  ),
                  Divider(height: 30),
                  Row(
                    children: [
                      Icon(Icons.local_shipping, color: green),
                      SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Rider is on the way',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              '8.4 km away • ETA 24 minutes',
                              style: TextStyle(color: muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Delivery progress',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 14),
          const _TimelineItem(
            title: 'Order confirmed',
            subtitle: '10:15 AM',
            done: true,
          ),
          const _TimelineItem(
            title: 'Picked up from 2 farms',
            subtitle: '12:48 PM',
            done: true,
          ),
          const _TimelineItem(
            title: 'On the way to your restaurant',
            subtitle: 'Current status',
            done: true,
            active: true,
          ),
          const _TimelineItem(
            title: 'Delivered',
            subtitle: 'Estimated by 3:00 PM',
            done: false,
            last: true,
          ),
        ],
      ),
    );
  }
}

class ConsumerProfile extends StatelessWidget {
  const ConsumerProfile({super.key, required this.user});
  final MobileUser user;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _PageHeader(
          eyebrow: 'CONSUMER ACCOUNT',
          title: user.name,
          subtitle: '${user.email} • ${user.phone}',
        ),
        const SizedBox(height: 24),
        const _ProfileTile(
          icon: Icons.location_on_outlined,
          title: 'Delivery addresses',
          subtitle: '2 saved locations',
        ),
        const _ProfileTile(
          icon: Icons.payments_outlined,
          title: 'Payment methods',
          subtitle: 'Cash on delivery',
        ),
        const _ProfileTile(
          icon: Icons.favorite_border,
          title: 'Favorite farms',
          subtitle: '4 verified farms',
        ),
        const _ProfileTile(
          icon: Icons.help_outline,
          title: 'Help & support',
          subtitle: 'FAQs and contact',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            await authService.logout();
            if (!context.mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const AuthWelcomePage()),
              (_) => false,
            );
          },
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
        ),
      ],
    );
  }
}

class RiderShell extends StatefulWidget {
  const RiderShell({super.key, required this.user});
  final MobileUser user;

  @override
  State<RiderShell> createState() => _RiderShellState();
}

class _RiderShellState extends State<RiderShell> {
  int _index = 0;
  bool _online = true;

  @override
  Widget build(BuildContext context) {
    final pages = [
      RiderDashboard(
        user: widget.user,
        online: _online,
        onToggle: (value) => setState(() => _online = value),
      ),
      const OrderPool(),
      const RiderTrips(),
      RiderProfile(user: widget.user),
    ];
    return Scaffold(
      body: SafeArea(child: pages[_index]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Pool',
          ),
          NavigationDestination(
            icon: Icon(Icons.route_outlined),
            selectedIcon: Icon(Icons.route),
            label: 'Trips',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}

class RiderDashboard extends StatelessWidget {
  const RiderDashboard({
    super.key,
    required this.user,
    required this.online,
    required this.onToggle,
  });
  final MobileUser user;
  final bool online;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFFFFE7C2),
              child: Icon(Icons.person, color: orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Ready to ride?', style: TextStyle(color: muted)),
                  Text(
                    user.name,
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            IconButton.filledTonal(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none),
            ),
          ],
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: online ? darkGreen : const Color(0xFF475467),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .13),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  online ? Icons.wifi_tethering : Icons.wifi_off,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      online ? 'You’re online' : 'You’re offline',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      online
                          ? 'New pooled trips are visible'
                          : 'Go online to receive trips',
                      style: const TextStyle(color: Color(0xFFD7E5D1)),
                    ),
                  ],
                ),
              ),
              Switch(value: online, onChanged: onToggle),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.payments_outlined,
                label: 'Today',
                value: '₱1,240',
                tint: lightGreen,
                color: green,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: _StatCard(
                icon: Icons.local_shipping_outlined,
                label: 'Trips',
                value: '3',
                tint: Color(0xFFFFF1DD),
                color: orange,
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const _SectionTitle(title: 'Active delivery', action: 'View route'),
        const SizedBox(height: 12),
        Card(
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const ActiveTrip()),
            ),
            child: const Padding(
              padding: EdgeInsets.all(18),
              child: Column(
                children: [
                  Row(
                    children: [
                      _Pill(
                        icon: Icons.route,
                        text: 'BATCH #B-208',
                        color: orange,
                      ),
                      Spacer(),
                      Text(
                        '₱520',
                        style: TextStyle(
                          fontSize: 20,
                          color: green,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 18),
                  _RouteRow(
                    color: orange,
                    title: 'Pickup 2 of 3',
                    subtitle: 'Dela Cruz Farm • 1.8 km',
                  ),
                  _RouteLine(),
                  _RouteRow(
                    color: green,
                    title: '3 drop-offs',
                    subtitle: 'Cabanatuan commercial district',
                  ),
                  SizedBox(height: 16),
                  LinearProgressIndicator(
                    value: .42,
                    minHeight: 7,
                    borderRadius: BorderRadius.all(Radius.circular(10)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 26),
        const _SectionTitle(
            title: 'Nearby opportunities', action: 'Order pool'),
        const SizedBox(height: 12),
        const _MiniOpportunity(
          area: 'Gapan → Cabanatuan',
          orders: '4 orders • 3 farms',
          distance: '42 km',
          pay: '₱680',
        ),
        const SizedBox(height: 10),
        const _MiniOpportunity(
          area: 'Talavera → San Jose',
          orders: '3 orders • 2 farms',
          distance: '31 km',
          pay: '₱490',
        ),
      ],
    );
  }
}

class OrderPool extends StatelessWidget {
  const OrderPool({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      children: [
        const _PageHeader(
          eyebrow: 'SMART POOLING',
          title: 'Open Order Pool',
          subtitle: 'Group deliveries heading in the same direction.',
        ),
        const SizedBox(height: 18),
        const Row(
          children: [
            Expanded(child: _FilterChip(label: 'Near me', selected: true)),
            SizedBox(width: 8),
            Expanded(child: _FilterChip(label: 'Best pay')),
            SizedBox(width: 8),
            Expanded(child: _FilterChip(label: 'Shortest')),
          ],
        ),
        const SizedBox(height: 20),
        _PoolCard(
          route: 'Gapan → Cabanatuan',
          badge: 'BEST MATCH',
          orders: 4,
          farms: 3,
          distance: '42 km',
          pay: '₱680',
          capacity: .72,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PoolDetails()),
          ),
        ),
        const SizedBox(height: 14),
        _PoolCard(
          route: 'Talavera → San Jose',
          badge: 'NEARBY',
          orders: 3,
          farms: 2,
          distance: '31 km',
          pay: '₱490',
          capacity: .55,
          onTap: () {},
        ),
        const SizedBox(height: 14),
        _PoolCard(
          route: 'Zaragoza → Palayan',
          badge: 'NEW',
          orders: 2,
          farms: 2,
          distance: '27 km',
          pay: '₱380',
          capacity: .38,
          onTap: () {},
        ),
      ],
    );
  }
}

class PoolDetails extends StatefulWidget {
  const PoolDetails({super.key});

  @override
  State<PoolDetails> createState() => _PoolDetailsState();
}

class _PoolDetailsState extends State<PoolDetails> {
  final selected = [true, true, true, true];

  @override
  Widget build(BuildContext context) {
    final count = selected.where((value) => value).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Pooled route')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
        children: [
          const _LiveOsmMap(riderMode: true),
          const SizedBox(height: 18),
          const Text(
            'Gapan → Cabanatuan',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text(
            '3 pickups • 4 drop-offs • est. 2h 15m',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 20),
          const _SectionTitle(title: 'Select orders', action: '70% capacity'),
          const SizedBox(height: 10),
          ...List.generate(poolOrders.length, (index) {
            final item = poolOrders[index];
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: CheckboxListTile(
                  value: selected[index],
                  onChanged: (value) =>
                      setState(() => selected[index] = value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    item.$1,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(item.$2),
                  secondary: Text(
                    item.$3,
                    style: const TextStyle(
                      color: green,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: count == 0
                ? null
                : () {
                    showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        icon: const Icon(
                          Icons.check_circle,
                          color: green,
                          size: 48,
                        ),
                        title: const Text('Trip accepted!'),
                        content: Text(
                          '$count orders were added to your delivery trip.',
                          textAlign: TextAlign.center,
                        ),
                        actions: [
                          FilledButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ActiveTrip(),
                                ),
                              );
                            },
                            child: const Text('Start pickup'),
                          ),
                        ],
                      ),
                    );
                  },
            style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
            child: Text('Accept $count orders  •  ₱680'),
          ),
        ],
      ),
    );
  }
}

class ActiveTrip extends StatefulWidget {
  const ActiveTrip({super.key});

  @override
  State<ActiveTrip> createState() => _ActiveTripState();
}

class DeliveryStop {
  const DeliveryStop({
    required this.type,
    required this.name,
    required this.contact,
    required this.phone,
    required this.address,
    required this.items,
    required this.point,
  });

  final String type;
  final String name;
  final String contact;
  final String phone;
  final String address;
  final String items;
  final LatLng point;
}

class _ActiveTripState extends State<ActiveTrip> {
  static const stops = [
    DeliveryStop(
      type: 'PICKUP',
      name: 'Green Valley Farm',
      contact: 'Roberto Santos',
      phone: '+639171234501',
      address: 'Brgy. Esguerra, Talavera, Nueva Ecija',
      items: 'Red onions • 25 kg',
      point: LatLng(15.5883, 120.9192),
    ),
    DeliveryStop(
      type: 'PICKUP',
      name: 'Dela Cruz Farm',
      contact: 'Juan Dela Cruz',
      phone: '+639171234502',
      address: 'Brgy. San Roque, Gapan, Nueva Ecija',
      items: 'Tomatoes and pechay • 70 kg',
      point: LatLng(15.3072, 120.9464),
    ),
    DeliveryStop(
      type: 'DELIVERY',
      name: 'Maria’s Kitchen',
      contact: 'Maria Reyes',
      phone: '+639171234567',
      address: 'Maharlika Highway, Brgy. Zulueta, Cabanatuan City',
      items: 'Order #AG-1048 • 35 kg',
      point: LatLng(15.4865, 120.9734),
    ),
    DeliveryStop(
      type: 'DELIVERY',
      name: 'Bistro Lokal',
      contact: 'Paolo Mendoza',
      phone: '+639189876543',
      address: 'Burgos Avenue, Brgy. Kapitan Pepe, Cabanatuan City',
      items: 'Order #AG-1051 • 30 kg',
      point: LatLng(15.4938, 120.9681),
    ),
  ];

  int currentStop = 0;
  final completed = <int>{};

  DeliveryStop get activeStop => stops[currentStop];

  Future<void> _contact(String scheme) async {
    final uri = Uri(scheme: scheme, path: activeStop.phone);
    if (!await launchUrl(uri) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open $scheme on this device.')),
      );
    }
  }

  void _completeCurrentStop() {
    setState(() {
      completed.add(currentStop);
      if (currentStop < stops.length - 1) currentStop++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final progress = completed.length / stops.length;
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Active trip'),
            Text(
              'Batch #B-208 • 4 stops',
              style: TextStyle(color: muted, fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.support_agent)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        children: [
          _LiveOsmMap(
            riderMode: true,
            followGps: true,
            focusPoint: activeStop.point,
            focusLabel: activeStop.name,
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Pill(
                        icon: activeStop.type == 'PICKUP'
                            ? Icons.inventory_2
                            : Icons.flag,
                        text: activeStop.type,
                        color: activeStop.type == 'PICKUP' ? orange : green,
                      ),
                      const Spacer(),
                      Text(
                        'Stop ${currentStop + 1} of ${stops.length}',
                        style: const TextStyle(color: muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    activeStop.name,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    activeStop.address,
                    style: const TextStyle(color: muted, height: 1.4),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(Icons.person_outline, color: green, size: 18),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          activeStop.contact,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton.filledTonal(
                        tooltip: 'Call contact',
                        onPressed: () => _contact('tel'),
                        icon: const Icon(Icons.call, size: 20),
                      ),
                      const SizedBox(width: 5),
                      IconButton.filledTonal(
                        tooltip: 'Message contact',
                        onPressed: () => _contact('sms'),
                        icon: const Icon(Icons.message_outlined, size: 20),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        color: muted,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(activeStop.items),
                    ],
                  ),
                  const SizedBox(height: 14),
                  LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${completed.length} of ${stops.length} stops complete',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Route stops',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 10),
          ...List.generate(stops.length, (index) {
            final stop = stops[index];
            final isActive = index == currentStop;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  onTap: () => setState(() => currentStop = index),
                  title: Text(
                    stop.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle:
                      Text('${stop.type} • ${stop.contact}\n${stop.address}'),
                  isThreeLine: true,
                  leading: CircleAvatar(
                    backgroundColor: completed.contains(index)
                        ? green
                        : isActive
                            ? orange
                            : canvas,
                    foregroundColor: completed.contains(index) || isActive
                        ? Colors.white
                        : ink,
                    child: completed.contains(index)
                        ? const Icon(Icons.check, size: 20)
                        : Text('${index + 1}'),
                  ),
                  trailing: isActive
                      ? const Icon(Icons.navigation, color: green)
                      : const Icon(Icons.chevron_right),
                ),
              ),
            );
          }),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: completed.contains(currentStop) &&
                    currentStop == stops.length - 1
                ? null
                : _completeCurrentStop,
            icon: const Icon(Icons.check_circle_outline),
            label: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(
                activeStop.type == 'PICKUP'
                    ? 'Confirm pickup & continue'
                    : 'Confirm delivery & continue',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class RiderTrips extends StatelessWidget {
  const RiderTrips({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _PageHeader(
          eyebrow: 'DELIVERY HISTORY',
          title: 'My Trips',
          subtitle: 'Your completed pooled routes and earnings.',
        ),
        const SizedBox(height: 22),
        const _TripHistory(
          route: 'Gapan → Cabanatuan',
          date: 'Today • 9:10 AM',
          orders: '4 orders',
          amount: '₱720',
        ),
        const SizedBox(height: 12),
        const _TripHistory(
          route: 'Talavera → San Jose',
          date: 'Yesterday • 2:30 PM',
          orders: '3 orders',
          amount: '₱510',
        ),
        const SizedBox(height: 12),
        const _TripHistory(
          route: 'Palayan → Cabanatuan',
          date: 'Jul 18 • 10:20 AM',
          orders: '5 orders',
          amount: '₱830',
        ),
      ],
    );
  }
}

class RiderProfile extends StatelessWidget {
  const RiderProfile({super.key, required this.user});
  final MobileUser user;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _PageHeader(
          eyebrow: 'VERIFIED RIDER',
          title: user.name,
          subtitle: '${user.email} • ${user.phone}',
        ),
        const SizedBox(height: 24),
        const _ProfileTile(
          icon: Icons.badge_outlined,
          title: 'Rider documents',
          subtitle: 'License and vehicle verified',
        ),
        const _ProfileTile(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Wallet & payouts',
          subtitle: '₱2,460 available',
        ),
        const _ProfileTile(
          icon: Icons.bar_chart,
          title: 'Performance',
          subtitle: '98% completion rate',
        ),
        const _ProfileTile(
          icon: Icons.help_outline,
          title: 'Rider support',
          subtitle: 'Safety and delivery help',
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: () async {
            await authService.logout();
            if (!context.mounted) return;
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (_) => const AuthWelcomePage()),
              (_) => false,
            );
          },
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
        ),
      ],
    );
  }
}

class Crop {
  const Crop({
    required this.name,
    required this.emoji,
    required this.price,
    required this.farmer,
    required this.location,
    required this.distance,
    required this.tint,
  });
  final String name;
  final String emoji;
  final int price;
  final String farmer;
  final String location;
  final String distance;
  final Color tint;
}

const crops = [
  Crop(
    name: 'Fresh Pechay',
    emoji: '🥬',
    price: 42,
    farmer: 'Reyes Family Farm',
    location: 'Gapan',
    distance: '8.2 km',
    tint: Color(0xFFE4F3DB),
  ),
  Crop(
    name: 'Red Tomatoes',
    emoji: '🍅',
    price: 55,
    farmer: 'Dela Cruz Farm',
    location: 'Gapan',
    distance: '11 km',
    tint: Color(0xFFFFE7E2),
  ),
  Crop(
    name: 'Sweet Mango',
    emoji: '🥭',
    price: 80,
    farmer: 'Mendoza Orchard',
    location: 'San Jose',
    distance: '18 km',
    tint: Color(0xFFFFF1C7),
  ),
  Crop(
    name: 'Red Onions',
    emoji: '🧅',
    price: 75,
    farmer: 'Green Valley Farm',
    location: 'Talavera',
    distance: '14 km',
    tint: Color(0xFFF3E3ED),
  ),
];

const poolOrders = [
  ('Maria’s Kitchen', 'Pechay • 20 kg • Cabanatuan', '₱170'),
  ('Bistro Lokal', 'Tomatoes • 30 kg • Cabanatuan', '₱190'),
  ('FreshMart', 'Red onions • 25 kg • Sta. Rosa', '₱150'),
  ('Lola Nena Eatery', 'Mixed crops • 20 kg • Gapan', '₱170'),
];

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        CircleAvatar(
          backgroundColor: green,
          child: Icon(Icons.eco, color: Colors.white),
        ),
        SizedBox(width: 10),
        Text(
          'AgriLink',
          style: TextStyle(
            color: darkGreen,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });
  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: green,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        Text(subtitle, style: const TextStyle(color: muted, height: 1.4)),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.action});
  final String title;
  final String action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
        ),
        Text(
          action,
          style: const TextStyle(color: green, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.text,
    this.color = muted,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _Category extends StatelessWidget {
  const _Category({required this.emoji, required this.label});
  final String emoji;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE6EAE2)),
        ),
        child: Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 7),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

class _CropCard extends StatelessWidget {
  const _CropCard({required this.crop, required this.onTap});
  final Crop crop;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                color: crop.tint,
                alignment: Alignment.center,
                child: Text(crop.emoji, style: const TextStyle(fontSize: 62)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    crop.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '₱${crop.price}/kg',
                    style: const TextStyle(
                      color: green,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: muted, size: 13),
                      Expanded(
                        child: Text(
                          ' ${crop.distance}',
                          style: const TextStyle(color: muted, fontSize: 11),
                        ),
                      ),
                      const Icon(Icons.verified, color: green, size: 14),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineItem extends StatelessWidget {
  const _LineItem({
    required this.emoji,
    required this.name,
    required this.detail,
    required this.price,
  });
  final String emoji;
  final String name;
  final String detail;
  final String price;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: lightGreen,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(emoji, style: const TextStyle(fontSize: 27)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
              Text(detail, style: const TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
        Text(price, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _Money extends StatelessWidget {
  const _Money({required this.label, required this.value, this.strong = false});
  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: strong ? ink : muted,
                fontWeight: strong ? FontWeight.w900 : FontWeight.normal,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: strong ? 19 : 14,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PastOrder extends StatelessWidget {
  const _PastOrder({
    required this.id,
    required this.name,
    required this.detail,
    required this.price,
    required this.emoji,
  });
  final String id;
  final String name;
  final String detail;
  final String price;
  final String emoji;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _LineItem(emoji: emoji, name: name, detail: detail, price: price),
            const Divider(height: 26),
            Row(
              children: [
                const _Pill(
                  icon: Icons.check_circle,
                  text: 'DELIVERED',
                  color: green,
                ),
                const Spacer(),
                Text(id, style: const TextStyle(color: muted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveOsmMap extends StatefulWidget {
  const _LiveOsmMap({
    required this.riderMode,
    this.followGps = false,
    this.focusPoint,
    this.focusLabel,
  });
  final bool riderMode;
  final bool followGps;
  final LatLng? focusPoint;
  final String? focusLabel;

  @override
  State<_LiveOsmMap> createState() => _LiveOsmMapState();
}

class _LiveOsmMapState extends State<_LiveOsmMap> {
  static const _gapanFarm = LatLng(15.3072, 120.9464);
  static const _cabanatuanBuyer = LatLng(15.4865, 120.9734);
  static const _talaveraFarm = LatLng(15.5883, 120.9192);

  final _mapController = MapController();
  StreamSubscription<Position>? _positionSubscription;
  List<LatLng> _route = [];
  LatLng? _deviceLocation;
  double _heading = 0;
  double _accuracy = 0;
  late bool _followingRider;
  bool _loadingRoute = true;
  bool _requestingLocation = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _followingRider = widget.followGps;
    _loadRoute();
    if (widget.riderMode) _startLocationTracking();
  }

  @override
  void didUpdateWidget(covariant _LiveOsmMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_followingRider &&
        widget.focusPoint != null &&
        widget.focusPoint != oldWidget.focusPoint) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _mapController.move(widget.focusPoint!, 15.2);
      });
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  bool _isInCentralLuzon(LatLng point) =>
      point.latitude > 14.0 &&
      point.latitude < 17.0 &&
      point.longitude > 119.0 &&
      point.longitude < 122.5;

  Future<void> _loadRoute({LatLng? origin}) async {
    setState(() {
      _loadingRoute = true;
      _notice = null;
    });
    final start = origin != null && _isInCentralLuzon(origin)
        ? origin
        : (widget.riderMode ? _talaveraFarm : _gapanFarm);
    final stops = widget.riderMode
        ? [start, _gapanFarm, _cabanatuanBuyer]
        : [start, _cabanatuanBuyer];
    final coordinates =
        stops.map((point) => '${point.longitude},${point.latitude}').join(';');
    final uri = Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/$coordinates'
      '?overview=full&geometries=geojson&steps=true',
    );
    try {
      final response = await http.get(
        uri,
        headers: const {'User-Agent': 'AgriLinkMobile/1.0'},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw Exception('Routing service returned ${response.statusCode}.');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = payload['routes'] as List<dynamic>;
      if (routes.isEmpty) throw Exception('No driving route found.');
      final geometry = routes.first as Map<String, dynamic>;
      final geoJson = geometry['geometry'] as Map<String, dynamic>;
      final values = geoJson['coordinates'] as List<dynamic>;
      if (!mounted) return;
      setState(() {
        _route = values.map((value) {
          final pair = value as List<dynamic>;
          return LatLng(
              (pair[1] as num).toDouble(), (pair[0] as num).toDouble());
        }).toList();
      });
      if (!_followingRider) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _fitEntireRoute());
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _route = stops;
        _notice = 'Live routing is temporarily unavailable.';
      });
    } finally {
      if (mounted) setState(() => _loadingRoute = false);
    }
  }

  void _fitEntireRoute() {
    if (!mounted || _route.length < 2) return;
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: _route,
        padding: const EdgeInsets.fromLTRB(42, 54, 42, 50),
        maxZoom: 14,
      ),
    );
  }

  Future<void> _startLocationTracking() async {
    if (_requestingLocation) return;
    setState(() => _requestingLocation = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _notice = 'Turn on device location to track the rider.');
        return;
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() =>
            _notice = 'Location permission is required for live tracking.');
        return;
      }
      await _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((position) {
        final current = LatLng(position.latitude, position.longitude);
        if (!mounted) return;
        setState(() {
          _deviceLocation = current;
          _heading = position.heading.isFinite ? position.heading : 0;
          _accuracy = position.accuracy;
        });
        if (_followingRider) {
          _mapController.move(current, 17);
        }
      });
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      final current = LatLng(position.latitude, position.longitude);
      if (!mounted) return;
      setState(() {
        _deviceLocation = current;
        _heading = position.heading.isFinite ? position.heading : 0;
        _accuracy = position.accuracy;
      });
      if (_isInCentralLuzon(current)) {
        _mapController.move(current, _followingRider ? 17 : 13);
        await _loadRoute(origin: current);
      } else {
        setState(() {
          _notice =
              'GPS is outside the delivery area; showing the assigned route.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _notice = 'Unable to get the current GPS location.');
      }
    } finally {
      if (mounted) setState(() => _requestingLocation = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 270,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1E8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFDCE6D9)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: widget.riderMode
                  ? const LatLng(15.46, 120.94)
                  : const LatLng(15.40, 120.96),
              initialZoom: widget.riderMode ? 10.2 : 10.8,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'ph.agrilink.mobile',
                maxZoom: 19,
              ),
              if (_route.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _route,
                      strokeWidth: 6,
                      color: green,
                      borderStrokeWidth: 2,
                      borderColor: Colors.white,
                    ),
                  ],
                ),
              if (_deviceLocation != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _deviceLocation!,
                      radius: _accuracy.clamp(18, 55).toDouble(),
                      color: const Color(0x223A9618),
                      borderColor: const Color(0x663A9618),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  const Marker(
                    point: _gapanFarm,
                    width: 120,
                    height: 64,
                    child: _NamedMapPin(
                      label: 'Dela Cruz Farm',
                      icon: Icons.agriculture,
                      color: orange,
                    ),
                  ),
                  const Marker(
                    point: _cabanatuanBuyer,
                    width: 120,
                    height: 64,
                    child: _NamedMapPin(
                      label: 'Maria’s Kitchen',
                      icon: Icons.store,
                      color: green,
                    ),
                  ),
                  if (widget.riderMode)
                    const Marker(
                      point: _talaveraFarm,
                      width: 120,
                      height: 64,
                      child: _NamedMapPin(
                        label: 'Green Valley Farm',
                        icon: Icons.inventory_2,
                        color: orange,
                      ),
                    ),
                  if (widget.focusPoint != null &&
                      widget.focusPoint != _gapanFarm &&
                      widget.focusPoint != _cabanatuanBuyer &&
                      widget.focusPoint != _talaveraFarm)
                    Marker(
                      point: widget.focusPoint!,
                      width: 120,
                      height: 64,
                      child: _NamedMapPin(
                        label: widget.focusLabel ?? 'Next stop',
                        icon: Icons.flag,
                        color: green,
                      ),
                    ),
                  if (_deviceLocation != null)
                    Marker(
                      point: _deviceLocation!,
                      width: 58,
                      height: 58,
                      child: Transform.rotate(
                        angle: _heading * 3.141592653589793 / 180,
                        child: const _RiderNavigationMarker(),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (_loadingRoute)
            const Positioned(
              top: 12,
              left: 0,
              right: 0,
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Calculating route…'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (widget.riderMode)
            Positioned(
              right: 12,
              bottom: 40,
              child: Column(
                children: [
                  _MapControlButton(
                    icon: Icons.add,
                    onTap: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom + 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _MapControlButton(
                    icon: Icons.remove,
                    onTap: () => _mapController.move(
                      _mapController.camera.center,
                      _mapController.camera.zoom - 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  _MapControlButton(
                    icon: Icons.route,
                    onTap: _fitEntireRoute,
                  ),
                  const SizedBox(height: 6),
                  _MapControlButton(
                    icon:
                        _followingRider ? Icons.gps_fixed : Icons.gps_not_fixed,
                    loading: _requestingLocation,
                    active: _followingRider,
                    onTap: () {
                      setState(() => _followingRider = !_followingRider);
                      if (_followingRider && _deviceLocation != null) {
                        _mapController.move(_deviceLocation!, 17);
                      } else if (_deviceLocation == null) {
                        _startLocationTracking();
                      }
                    },
                  ),
                ],
              ),
            ),
          if (_notice != null)
            Positioned(
              left: 10,
              right: 10,
              top: 10,
              child: Material(
                color: const Color(0xEEFFFFFF),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(9),
                  child: Text(
                    _notice!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          Positioned(
            left: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                '© OpenStreetMap contributors • Route: OSRM',
                style: TextStyle(fontSize: 10, color: muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NamedMapPin extends StatelessWidget {
  const _NamedMapPin({
    required this.label,
    required this.icon,
    required this.color,
  });
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          constraints: const BoxConstraints(maxWidth: 116),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(7),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 5),
            ],
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900),
          ),
        ),
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
          ),
          child: Icon(icon, color: Colors.white, size: 18),
        ),
      ],
    );
  }
}

class _RiderNavigationMarker extends StatelessWidget {
  const _RiderNavigationMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: Color(0x44000000), blurRadius: 10),
        ],
      ),
      padding: const EdgeInsets.all(5),
      child: Container(
        decoration: BoxDecoration(
          color: darkGreen,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: const Icon(
          Icons.navigation_rounded,
          color: Colors.white,
          size: 30,
        ),
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  const _MapControlButton({
    required this.icon,
    required this.onTap,
    this.loading = false,
    this.active = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool loading;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: active ? green : Colors.white,
      elevation: 2,
      borderRadius: BorderRadius.circular(9),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 38,
          height: 38,
          child: loading
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, color: active ? Colors.white : green, size: 20),
        ),
      ),
    );
  }
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({
    required this.title,
    required this.subtitle,
    required this.done,
    this.active = false,
    this.last = false,
  });
  final String title;
  final String subtitle;
  final bool done;
  final bool active;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 26,
            child: Column(
              children: [
                Container(
                  width: active ? 18 : 14,
                  height: active ? 18 : 14,
                  decoration: BoxDecoration(
                    color: done ? green : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: done ? green : Colors.grey),
                  ),
                ),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: done ? green : const Color(0xFFD0D5DD),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: active ? green : muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: lightGreen,
          child: Icon(icon, color: green),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
    required this.color,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color tint;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: tint,
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 14),
            Text(label, style: const TextStyle(color: muted, fontSize: 12)),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.color,
    required this.title,
    required this.subtitle,
  });
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 13,
          height: 13,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(subtitle,
                  style: const TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteLine extends StatelessWidget {
  const _RouteLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      margin: const EdgeInsets.only(left: 6),
      alignment: Alignment.centerLeft,
      child: Container(width: 2, color: const Color(0xFFD0D5DD)),
    );
  }
}

class _MiniOpportunity extends StatelessWidget {
  const _MiniOpportunity({
    required this.area,
    required this.orders,
    required this.distance,
    required this.pay,
  });
  final String area;
  final String orders;
  final String distance;
  final String pay;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            const CircleAvatar(
              backgroundColor: Color(0xFFFFF1DD),
              child: Icon(Icons.route, color: orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(area,
                      style: const TextStyle(fontWeight: FontWeight.w900)),
                  Text(
                    '$orders • $distance',
                    style: const TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Text(
              pay,
              style: const TextStyle(color: green, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, this.selected = false});
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? green : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? green : const Color(0xFFD0D5DD)),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : muted,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _PoolCard extends StatelessWidget {
  const _PoolCard({
    required this.route,
    required this.badge,
    required this.orders,
    required this.farms,
    required this.distance,
    required this.pay,
    required this.capacity,
    required this.onTap,
  });
  final String route;
  final String badge;
  final int orders;
  final int farms;
  final String distance;
  final String pay;
  final double capacity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Pill(icon: Icons.auto_awesome, text: badge, color: orange),
                  const Spacer(),
                  Text(
                    pay,
                    style: const TextStyle(
                      color: green,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                route,
                style:
                    const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 6),
              Text(
                '$orders orders • $farms farms • $distance',
                style: const TextStyle(color: muted),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text(
                    'Vehicle capacity',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                  const Spacer(),
                  Text(
                    '${(capacity * 100).round()}%',
                    style: const TextStyle(
                      color: green,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              LinearProgressIndicator(
                value: capacity,
                minHeight: 7,
                borderRadius: BorderRadius.circular(8),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripHistory extends StatelessWidget {
  const _TripHistory({
    required this.route,
    required this.date,
    required this.orders,
    required this.amount,
  });
  final String route;
  final String date;
  final String orders;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: const CircleAvatar(
          backgroundColor: lightGreen,
          child: Icon(Icons.check, color: green),
        ),
        title: Text(route, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text('$date\n$orders'),
        isThreeLine: true,
        trailing: Text(
          amount,
          style: const TextStyle(color: green, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}
