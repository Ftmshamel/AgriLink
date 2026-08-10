import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../app.dart';
import '../models/mobile_user.dart';
import '../services/cloud_database.dart';
import '../services/local_auth_service.dart';
import '../utils/app_colors.dart';

class VerificationPendingPage extends StatelessWidget {
  const VerificationPendingPage({super.key, required this.user});
  final MobileUser user;

  @override
  Widget build(BuildContext context) {
    final isRider = user.role == MobileRole.rider;
    final status = user.verificationStatus;
    final (title, message) = switch (status) {
      'rejected' => (
          'Application not approved',
          'A superadmin reviewed your requirements and could not approve them. '
              'Contact AgriLink support to resubmit clearer documents.',
        ),
      'suspended' => (
          'Account suspended',
          'Your access is paused while AgriLink reviews recent activity. '
              'Contact support to have your account restored.',
        ),
      _ => (
          'Application under review',
          isRider
              ? 'We are checking your professional license, vehicle OR/CR, clearance, and public-service authorization.'
              : 'We are checking your farm location and Barangay Certificate. Your RSBSA number remains optional.',
        ),
    };
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  color: lightGreen,
                  borderRadius: BorderRadius.circular(26),
                ),
                child: const Icon(
                  Icons.fact_check_outlined,
                  color: green,
                  size: 42,
                ),
              ),
              const SizedBox(height: 22),
              Text(
                title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted, height: 1.5),
              ),
              const SizedBox(height: 22),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active_outlined,
                          color: orange),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          status == 'pending_review'
                              ? 'We will notify ${user.phone} when your account is approved.'
                              : 'AgriLink support will reach you at ${user.phone}.',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await authService.logout();
                    if (!context.mounted) return;
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AuthWelcomePage(),
                      ),
                      (_) => false,
                    );
                  },
                  icon: const Icon(Icons.logout),
                  label: const Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('Log out'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    if (_failed) setState(() => _failed = false);
    try {
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
    } catch (_) {
      // Firestore is the only source of truth, so a failed restore means the
      // device cannot reach it. Offer a retry instead of spinning forever.
      if (mounted) setState(() => _failed = true);
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
              if (!_failed)
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 3),
                )
              else ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 40),
                  child: Text(
                    'Cannot reach AgriLink. Check your internet connection.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted, height: 1.45),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.refresh),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Text('Try again'),
                  ),
                ),
              ],
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
                          'Buy in bulk, sell fresh harvests, or deliver pooled farm orders.',
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
                        'For Consumers, Farmers, and Riders',
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
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ForgotPasswordPage(
                        initialEmail: _email.text.trim(),
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
            const Divider(height: 34),
            Center(
              child: TextButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SuperadminLoginPage(),
                  ),
                ),
                icon: const Icon(Icons.admin_panel_settings_outlined, size: 18),
                label: const Text('Platform staff access'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Email → emailed code → new password, all on one page.
class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key, this.initialEmail = ''});

  final String initialEmail;

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

enum _ResetStep { email, code, password }

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailKey = GlobalKey<FormState>();
  final _codeKey = GlobalKey<FormState>();
  final _passwordKey = GlobalKey<FormState>();
  late final _email = TextEditingController(text: widget.initialEmail);
  final _code = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  _ResetStep _step = _ResetStep.email;
  PasswordResetTicket? _ticket;
  String? _ticketId;
  bool _showPassword = false;
  bool _loading = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = error.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendCode({bool resend = false}) async {
    if (!resend && !_emailKey.currentState!.validate()) return;
    await _run(() async {
      final ticket = await authService.requestPasswordReset(_email.text.trim());
      if (!mounted) return;
      setState(() {
        _ticket = ticket;
        _step = _ResetStep.code;
        _code.clear();
        _notice = ticket.delivered
            ? 'We sent a 6-digit code to ${ticket.email}.'
            : null;
      });
    });
  }

  Future<void> _verifyCode() async {
    if (!_codeKey.currentState!.validate()) return;
    await _run(() async {
      final ticketId = await authService.verifyPasswordResetCode(
        _email.text.trim(),
        _code.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _ticketId = ticketId;
        _step = _ResetStep.password;
        _notice = null;
      });
    });
  }

  Future<void> _savePassword() async {
    if (!_passwordKey.currentState!.validate()) return;
    await _run(() async {
      await authService.completePasswordReset(
        emailAddress: _email.text.trim(),
        ticketId: _ticketId!,
        newPassword: _password.text,
      );
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginPage()),
        (route) => route.isFirst,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Password updated. Log in with your new password.'),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return _AuthScaffold(
      child: switch (_step) {
        _ResetStep.email => _buildEmailStep(),
        _ResetStep.code => _buildCodeStep(),
        _ResetStep.password => _buildPasswordStep(),
      },
    );
  }

  Widget _buildEmailStep() {
    return Form(
      key: _emailKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        children: [
          const _AuthIcon(icon: Icons.lock_reset),
          const SizedBox(height: 16),
          const Text(
            'Forgot password',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text(
            'Enter your email and we will send a verification code.',
            style: TextStyle(color: muted, fontSize: 15, height: 1.4),
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
            validator: (value) => value == null || !value.contains('@')
                ? 'Enter a valid email address.'
                : null,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _loading ? null : () => _sendCode(),
            icon: _loading ? const _ButtonSpinner() : const Icon(Icons.send),
            label: Padding(
              padding: const EdgeInsets.all(15),
              child: Text(_loading ? 'Sending code…' : 'Send reset code'),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Remembered it?', style: TextStyle(color: muted)),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Back to log in'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCodeStep() {
    final ticket = _ticket;
    return Form(
      key: _codeKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        children: [
          const _AuthIcon(icon: Icons.mark_email_read_outlined),
          const SizedBox(height: 16),
          const Text(
            'Check your email',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Text(
            'We sent a 6-digit code to ${_email.text.trim()}. It expires in '
            '${CloudDatabase.resetCodeLifetime.inMinutes} minutes.',
            style: const TextStyle(color: muted, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 20),
          if (_error != null) ...[
            _AuthError(message: _error!),
            const SizedBox(height: 16),
          ],
          if (_notice != null) ...[
            _AuthNotice(message: _notice!),
            const SizedBox(height: 16),
          ],
          if (ticket != null && ticket.previewCode != null) ...[
            _AuthNotice(
              icon: Icons.construction_outlined,
              message: 'Email delivery is not configured in this build, so the '
                  'code was not sent. Development code: '
                  '${ticket.previewCode}',
            ),
            const SizedBox(height: 16),
          ],
          _AuthField(
            controller: _code,
            label: 'Verification code',
            hint: '6-digit code',
            icon: Icons.pin_outlined,
            keyboardType: TextInputType.number,
            validator: (value) => value == null || value.trim().length != 6
                ? 'Enter the 6-digit code.'
                : null,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _loading ? null : _verifyCode,
            icon: _loading
                ? const _ButtonSpinner()
                : const Icon(Icons.verified_outlined),
            label: Padding(
              padding: const EdgeInsets.all(15),
              child: Text(_loading ? 'Verifying…' : 'Verify code'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text("Didn't get it?", style: TextStyle(color: muted)),
              TextButton(
                onPressed: _loading ? null : () => _sendCode(resend: true),
                child: const Text('Resend code'),
              ),
            ],
          ),
          Center(
            child: TextButton(
              onPressed: _loading
                  ? null
                  : () => setState(() {
                        _step = _ResetStep.email;
                        _error = null;
                        _notice = null;
                      }),
              child: const Text('Use a different email'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordStep() {
    return Form(
      key: _passwordKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        children: [
          const _AuthIcon(icon: Icons.password_outlined),
          const SizedBox(height: 16),
          const Text(
            'Set a new password',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          const Text(
            'Choose a password you have not used on AgriLink before.',
            style: TextStyle(color: muted, fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 24),
          if (_error != null) ...[
            _AuthError(message: _error!),
            const SizedBox(height: 16),
          ],
          const Text(
            'New password',
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
                onPressed: () => setState(() => _showPassword = !_showPassword),
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
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _loading ? null : _savePassword,
            icon: _loading ? const _ButtonSpinner() : const Icon(Icons.check),
            label: Padding(
              padding: const EdgeInsets.all(15),
              child: Text(_loading ? 'Saving…' : 'Save new password'),
            ),
          ),
        ],
      ),
    );
  }
}

class SuperadminLoginPage extends StatefulWidget {
  const SuperadminLoginPage({super.key});

  @override
  State<SuperadminLoginPage> createState() => _SuperadminLoginPageState();
}

class _SuperadminLoginPageState extends State<SuperadminLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _showPassword = false;
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
      final user =
          await authService.loginSuperadmin(_email.text, _password.text);
      if (mounted) openUserHome(context, user);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error.toString().replaceFirst('Exception: ', ''),
        );
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
            const _AuthIcon(icon: Icons.admin_panel_settings_outlined),
            const SizedBox(height: 16),
            const Text(
              'Platform staff',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Restricted access for authorized AgriLink superadmins.',
              style: TextStyle(color: muted, height: 1.4),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFFD99A)),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, color: orange, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Superadmin accounts are issued internally and cannot be created through public registration.',
                      style: TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              _AuthError(message: _error!),
              const SizedBox(height: 14),
            ],
            _AuthField(
              controller: _email,
              label: 'Staff email',
              hint: 'name@agrilink.ph',
              icon: Icons.alternate_email,
              keyboardType: TextInputType.emailAddress,
              validator: (value) => value == null || !value.contains('@')
                  ? 'Enter your staff email.'
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
              validator: (value) => value == null || value.isEmpty
                  ? 'Enter your password.'
                  : null,
              decoration: _fieldDecoration(
                hint: '••••••••',
                icon: Icons.key_outlined,
                suffix: IconButton(
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: const Icon(Icons.shield_outlined),
              label: Padding(
                padding: const EdgeInsets.all(15),
                child: Text(_loading ? 'Verifying…' : 'Access admin console'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Firestore keeps documents inline as base64, so attachments stay small.
const _maxDocumentBytes = 750000;

/// One requirement on the signup form, and the file picked for it.
class _DocumentSlot {
  const _DocumentSlot({
    required this.type,
    required this.label,
    required this.file,
    this.required = true,
  });

  final String type;
  final String label;
  final XFile? file;
  final bool required;
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
  final _location = TextEditingController();
  final _secondaryId = TextEditingController();
  final _payout = TextEditingController();
  final _vehicle = TextEditingController();
  final _publicServiceCode = TextEditingController();
  MobileRole _role = MobileRole.consumer;
  XFile? _primaryDocument;
  XFile? _secondaryDocument;
  XFile? _clearanceDocument;
  bool _showPassword = false;
  bool _agreed = false;
  bool _loading = false;
  String? _error;
  double? _selectedLatitude;
  double? _selectedLongitude;

  void _selectRole(MobileRole role) {
    setState(() {
      _role = role;
      _primaryDocument = null;
      _secondaryDocument = null;
      _clearanceDocument = null;
      _error = null;
    });
  }

  Future<void> _pickDocument(void Function(XFile file) save) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 55,
      maxWidth: 1400,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (bytes.length > _maxDocumentBytes) {
      setState(() => _error = 'Upload an image below 750 KB.');
      return;
    }
    setState(() {
      save(file);
      _error = null;
    });
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.push<LocationSelection>(
      context,
      MaterialPageRoute(builder: (_) => const LocationPickerPage()),
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedLatitude = result.point.latitude;
      _selectedLongitude = result.point.longitude;
      _location.text = result.address;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _location.dispose();
    _secondaryId.dispose();
    _payout.dispose();
    _vehicle.dispose();
    _publicServiceCode.dispose();
    super.dispose();
  }

  /// The requirements this role has to submit, in review order.
  ///
  /// Consumers are approved on the spot, so their permit stays optional;
  /// farmers and riders cannot trade until a superadmin has seen these files.
  List<_DocumentSlot> get _documentSlots => switch (_role) {
        MobileRole.consumer => [
            _DocumentSlot(
              type: 'business_permit',
              label: 'Business Permit',
              file: _primaryDocument,
              required: false,
            ),
          ],
        MobileRole.farmer => [
            _DocumentSlot(
              type: 'barangay_certificate',
              label: 'Barangay Certificate',
              file: _primaryDocument,
            ),
          ],
        MobileRole.rider => [
            _DocumentSlot(
              type: 'professional_license',
              label: 'Professional Driver’s License',
              file: _primaryDocument,
            ),
            _DocumentSlot(
              type: 'vehicle_or_cr',
              label: 'Vehicle OR/CR',
              file: _secondaryDocument,
            ),
            _DocumentSlot(
              type: 'nbi_or_police_clearance',
              label: 'NBI or Police Clearance',
              file: _clearanceDocument,
            ),
          ],
        MobileRole.superadmin => const [],
      };

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedLatitude == null || _selectedLongitude == null) {
      setState(() => _error = 'Pin your location on the map.');
      return;
    }
    final slots = _documentSlots;
    final missing = slots
        .where((slot) => slot.required && slot.file == null)
        .map((slot) => slot.label)
        .toList();
    if (missing.isNotEmpty) {
      setState(() => _error = 'Attach your ${_join(missing)}.');
      return;
    }
    if (!_agreed) {
      setState(() => _error = 'Please accept the Terms and Privacy Policy.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Read every attachment first: a file that cannot be loaded should fail
      // here, not after the applicant already exists with nothing to review.
      final attachments = <({String type, String filename, Uint8List bytes})>[];
      for (final slot in slots) {
        final file = slot.file;
        if (file == null) continue;
        final bytes = await file.readAsBytes();
        if (bytes.length > _maxDocumentBytes) {
          throw Exception('${slot.label} must be smaller than 750 KB.');
        }
        attachments.add((type: slot.type, filename: file.name, bytes: bytes));
      }

      final requiredCount = slots.where((slot) => slot.required).length;
      final user = await authService.signup(
        MobileUser(
          name: _name.text.trim(),
          email: _email.text.trim(),
          password: _password.text,
          phone: _phone.text.trim(),
          role: _role,
          verification: {
            'location': _location.text.trim(),
            'secondaryId': _secondaryId.text.trim(),
            'payoutNumber': _payout.text.trim(),
            'vehicle': _vehicle.text.trim(),
            'publicServiceCode': _publicServiceCode.text.trim(),
            'latitude': '${_selectedLatitude ?? ''}',
            'longitude': '${_selectedLongitude ?? ''}',
            // Recorded so the review queue can show whether everything the
            // role owes actually arrived.
            'requiredDocuments': '$requiredCount',
            'submittedDocuments': '${attachments.length}',
            'status':
                _role == MobileRole.consumer ? 'active' : 'pending_review',
          },
        ),
      );
      for (final attachment in attachments) {
        await authService.database.uploadVerificationFile(
          userId: user.id,
          type: attachment.type,
          filename: attachment.filename,
          bytes: attachment.bytes,
        );
      }
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

  String _join(List<String> values) => values.length == 1
      ? values.single
      : '${values.take(values.length - 1).join(', ')} and ${values.last}';

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
              'Join AgriLink using the role that fits your work.',
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
                    onTap: () => _selectRole(MobileRole.consumer),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SignupRoleCard(
                    icon: Icons.agriculture_outlined,
                    title: 'Farmer',
                    subtitle: 'Crop producer',
                    selected: _role == MobileRole.farmer,
                    onTap: () => _selectRole(MobileRole.farmer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _SignupRoleCard(
              icon: Icons.local_shipping_outlined,
              title: 'Rider',
              subtitle: 'Verified logistics partner',
              selected: _role == MobileRole.rider,
              onTap: () => _selectRole(MobileRole.rider),
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
            const SizedBox(height: 24),
            _VerificationHeader(role: _role),
            const SizedBox(height: 14),
            _LocationPickerField(
              label: _role == MobileRole.farmer ? 'Farm location' : 'Location',
              address: _location.text,
              selected: _selectedLatitude != null,
              onTap: _pickLocation,
            ),
            if (_role == MobileRole.consumer) ...[
              const SizedBox(height: 12),
              _DocumentUploadCard(
                icon: Icons.business_center_outlined,
                title: 'Business Permit',
                subtitle: 'Optional proof for registered restaurants',
                attached: _primaryDocument != null,
                onTap: () => _pickDocument((file) => _primaryDocument = file),
              ),
            ],
            if (_role == MobileRole.farmer) ...[
              const SizedBox(height: 12),
              _AuthField(
                controller: _payout,
                label: 'GCash / Maya payout number',
                hint: '09XX XXX XXXX',
                icon: Icons.account_balance_wallet_outlined,
                keyboardType: TextInputType.phone,
                validator: (value) => value == null || value.trim().length < 10
                    ? 'Enter a valid payout number.'
                    : null,
              ),
              const SizedBox(height: 12),
              _DocumentUploadCard(
                icon: Icons.description_outlined,
                title: 'Barangay Certificate',
                subtitle: 'Proof of farm-area operation or residence',
                attached: _primaryDocument != null,
                required: true,
                onTap: () => _pickDocument((file) => _primaryDocument = file),
              ),
              const SizedBox(height: 12),
              _AuthField(
                controller: _secondaryId,
                label: 'RSBSA number (optional)',
                hint: 'Registry System for Basic Sectors in Agriculture',
                icon: Icons.badge_outlined,
              ),
            ],
            if (_role == MobileRole.rider) ...[
              const SizedBox(height: 12),
              _VehicleField(
                value: _vehicle.text.isEmpty ? null : _vehicle.text,
                onChanged: (value) =>
                    setState(() => _vehicle.text = value ?? ''),
              ),
              const SizedBox(height: 12),
              _AuthField(
                controller: _publicServiceCode,
                label: 'Public-service license code',
                hint: 'Restriction/code authorizing the vehicle service',
                icon: Icons.verified_outlined,
                validator: _required('Enter the public-service code.'),
              ),
              const SizedBox(height: 12),
              _DocumentUploadCard(
                icon: Icons.badge_outlined,
                title: 'Professional Driver’s License',
                subtitle: 'Must show the applicable public-service code',
                attached: _primaryDocument != null,
                required: true,
                onTap: () => _pickDocument((file) => _primaryDocument = file),
              ),
              const SizedBox(height: 10),
              _DocumentUploadCard(
                icon: Icons.directions_car_outlined,
                title: 'Vehicle OR/CR',
                subtitle: 'Registration for the declared delivery vehicle',
                attached: _secondaryDocument != null,
                required: true,
                onTap: () => _pickDocument((file) => _secondaryDocument = file),
              ),
              const SizedBox(height: 10),
              _DocumentUploadCard(
                icon: Icons.policy_outlined,
                title: 'NBI or Police Clearance',
                subtitle: 'Required for product and network security',
                attached: _clearanceDocument != null,
                required: true,
                onTap: () => _pickDocument((file) => _clearanceDocument = file),
              ),
            ],
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

class LocationSelection {
  const LocationSelection({required this.point, required this.address});
  final LatLng point;
  final String address;
}

class _LocationPickerField extends StatelessWidget {
  const _LocationPickerField({
    required this.label,
    required this.address,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String address;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 7),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? lightGreen : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? green : const Color(0xFFD8DED5),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected
                      ? Icons.location_on
                      : Icons.add_location_alt_outlined,
                  color: green,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    selected ? address : 'Pin your exact location on the map',
                    style: TextStyle(
                      color: selected ? ink : muted,
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.normal,
                    ),
                  ),
                ),
                const Icon(Icons.chevron_right, color: muted),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class LocationPickerPage extends StatefulWidget {
  const LocationPickerPage({super.key});

  @override
  State<LocationPickerPage> createState() => _LocationPickerPageState();
}

class _LocationPickerPageState extends State<LocationPickerPage> {
  static const _fallback = LatLng(15.4865, 120.9734);
  final _mapController = MapController();
  LatLng? _selected;
  String _address = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _useCurrentLocation();
  }

  Future<void> _useCurrentLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      final point = LatLng(position.latitude, position.longitude);
      _mapController.move(point, 17);
      await _select(point);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(LatLng point) async {
    setState(() {
      _selected = point;
      _loading = true;
      _address = 'Finding address…';
    });
    var address =
        '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}';
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': '${point.latitude}',
        'lon': '${point.longitude}',
        'zoom': '18',
      });
      final response = await http.get(uri, headers: {
        'User-Agent': 'AgriLink-Mobile/1.0 (agrilink.ph)',
      });
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        address = '${data['display_name'] ?? address}';
      }
    } catch (_) {}
    if (!mounted || _selected != point) return;
    setState(() {
      _address = address;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pin your location')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _fallback,
              initialZoom: 12,
              onTap: (_, point) => _select(point),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.agrilink_mobile',
              ),
              if (_selected != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selected!,
                      width: 54,
                      height: 54,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 50,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 18,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Selected address',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _selected == null
                          ? 'Tap the map or use your current location.'
                          : _address,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: muted, height: 1.35),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: _useCurrentLocation,
                          icon: const Icon(Icons.my_location),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: _selected == null || _loading
                                ? null
                                : () => Navigator.pop(
                                      context,
                                      LocationSelection(
                                        point: _selected!,
                                        address: _address,
                                      ),
                                    ),
                            child: Padding(
                              padding: const EdgeInsets.all(13),
                              child: Text(
                                _loading ? 'Finding address…' : 'Use this pin',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationHeader extends StatelessWidget {
  const _VerificationHeader({required this.role});
  final MobileRole role;

  @override
  Widget build(BuildContext context) {
    final (title, message) = switch (role) {
      MobileRole.consumer => (
          'Buyer information',
          'Tell farms and riders where your bulk orders should be delivered.',
        ),
      MobileRole.farmer => (
          'Farm verification',
          'Simple requirements for safe payouts and trusted farm listings.',
        ),
      MobileRole.rider => (
          'Logistics verification',
          'Rider applications are reviewed before order-pool access is enabled.',
        ),
      MobileRole.superadmin => ('', ''),
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: lightGreen,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFCFE5C5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined, color: green),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 3),
                Text(
                  message,
                  style:
                      const TextStyle(color: muted, fontSize: 12, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentUploadCard extends StatelessWidget {
  const _DocumentUploadCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.attached,
    required this.onTap,
    this.required = false,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final bool attached;
  final VoidCallback onTap;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: attached ? lightGreen : Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: attached ? green : const Color(0xFFD8DED5),
            width: attached ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: attached ? green : canvas,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: attached ? Colors.white : green),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      if (required)
                        const Text(' *',
                            style: TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w900)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    attached ? 'Document attached' : subtitle,
                    style: TextStyle(
                      color: attached ? green : muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              attached ? Icons.check_circle : Icons.upload_file_outlined,
              color: attached ? green : muted,
            ),
          ],
        ),
      ),
    );
  }
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

/// Vehicle picker limited to [deliveryVehicles].
///
/// This was a free-text field, which could not stop a rider registering a
/// tricycle that a pooled bulk order will never fit in.
class _VehicleField extends StatelessWidget {
  const _VehicleField({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vehicle type',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 7),
        DropdownButtonFormField<String>(
          initialValue: deliveryVehicles.contains(value) ? value : null,
          isExpanded: true,
          items: [
            for (final vehicle in deliveryVehicles)
              DropdownMenuItem(value: vehicle, child: Text(vehicle)),
          ],
          onChanged: onChanged,
          validator: (selected) => selected == null || selected.isEmpty
              ? 'Choose your delivery vehicle.'
              : null,
          decoration: _fieldDecoration(
            hint: 'Select a 4-wheel vehicle',
            icon: Icons.local_shipping_outlined,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Bulk farm orders need four wheels. Motorcycles, tricycles, and '
          'kolong-kolong cannot be registered.',
          style: TextStyle(color: muted, fontSize: 11, height: 1.35),
        ),
      ],
    );
  }
}

/// Neutral counterpart to [_AuthError] for progress and setup messages.
class _AuthNotice extends StatelessWidget {
  const _AuthNotice({required this.message, this.icon = Icons.info_outline});
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: lightGreen,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFCFE5C5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: green, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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

