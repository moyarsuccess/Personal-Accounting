import 'package:flutter/material.dart';
import 'package:personal_accounting/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Two parallel auth paths:
///   1. **Password** (primary, no rate limit) — straightforward email/password
///      sign-in.
///   2. **Magic link** (fallback, rate-limited on the free tier) — Supabase
///      emails a one-time link; on Windows the `personalaccounting://` scheme
///      registered by [DeeplinkService] routes the click back into the app.
///
/// If the user has never set a password for their account, they can sign in
/// once via magic link and then use "Set password" from the in-app menu to
/// add one (see `import_qfx_button.dart`). After that, password mode works.
enum _Mode { password, magicLink }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _codeController = TextEditingController();

  _Mode _mode = _Mode.password;
  bool _busy = false;
  bool _verifying = false;
  bool _linkSent = false;
  bool _obscurePassword = true;
  String? _statusMessage;
  bool _isError = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // ─── Password sign-in ──────────────────────────────────────────────────────

  Future<void> _signInWithPassword() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _statusMessage = 'Enter a valid email address.';
        _isError = true;
      });
      return;
    }
    if (password.isEmpty) {
      setState(() {
        _statusMessage = 'Enter your password.';
        _isError = true;
      });
      return;
    }
    setState(() {
      _busy = true;
      _statusMessage = null;
      _isError = false;
    });
    try {
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      // AuthGate's stream picks up the new session and routes us in.
    } on AuthException catch (e) {
      // Common cases: "Invalid login credentials" (wrong pw or no password
      // set yet for this account), "Email not confirmed", etc.
      if (mounted) {
        setState(() {
          _statusMessage = _explainAuthError(e);
          _isError = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Something went wrong: $e';
          _isError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  String _explainAuthError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials')) {
      return 'Wrong email or password. If you signed up with a magic link '
          'and never set a password, sign in with a magic link first, then '
          'use "Set password" from the FAB menu inside the app.';
    }
    return e.message;
  }

  // ─── Magic link ────────────────────────────────────────────────────────────

  Future<void> _sendMagicLink() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _statusMessage = 'Enter a valid email address.';
        _isError = true;
      });
      return;
    }

    setState(() {
      _busy = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      await Supabase.instance.client.auth.signInWithOtp(
        email: email,
        emailRedirectTo: SupabaseConfig.authRedirect,
      );
      if (mounted) {
        setState(() {
          _linkSent = true;
          _statusMessage =
              'Magic link sent to $email. Check your email and tap the link — '
              'the app will open automatically.';
          _isError = false;
        });
      }
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = e.message;
          _isError = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Something went wrong: $e';
          _isError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  /// Handles every flavour of paste the user is likely to throw at us:
  ///
  ///   1. **Post-redirect URL** — `http://localhost:3000/?code=<uuid>`.
  ///      Goes through `exchangeCodeForSession` (PKCE flow). Requires the
  ///      verifier saved during the matching `signInWithOtp` call, so this
  ///      only works if the same app session sent the email.
  ///   2. **Raw email URL** — the link in the inbox itself, e.g.
  ///      `https://<proj>.supabase.co/auth/v1/verify?token=<hex>&type=magiclink&redirect_to=...`.
  ///      Goes through `verifyOTP(token, type, email)`. Stateless — no PKCE
  ///      verifier required, so this works across cold-starts and rate
  ///      limits alike (as long as the link itself hasn't been consumed).
  ///   3. **Bare PKCE code** — just `<uuid>`. Treated like (1).
  Future<void> _verifyCode() async {
    final raw = _codeController.text.trim();
    if (raw.isEmpty) return;

    setState(() {
      _verifying = true;
      _statusMessage = null;
      _isError = false;
    });

    try {
      final uri = Uri.tryParse(raw);
      final params = uri?.queryParameters ?? const <String, String>{};

      if (params.containsKey('token') && params.containsKey('type')) {
        // Path (2) — verify the OTP token directly. Need email.
        final email = _emailController.text.trim();
        if (email.isEmpty) {
          setState(() {
            _statusMessage =
                'Enter your email above before pasting the verification link.';
            _isError = true;
          });
          return;
        }
        final type = _otpTypeFor(params['type']!);
        await Supabase.instance.client.auth.verifyOTP(
          token: params['token']!,
          type: type,
          email: email,
        );
        return;
      }

      // Path (1) / (3) — PKCE code exchange.
      final code = params.containsKey('code') ? params['code']! : raw;
      await Supabase.instance.client.auth.exchangeCodeForSession(code);
    } on AuthException catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Verification failed: ${e.message}';
          _isError = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Verification failed: $e';
          _isError = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _verifying = false;
        });
      }
    }
  }

  /// Maps the `type=` query param from the Supabase verify URL to the
  /// matching `OtpType` enum. Defaults to `magiclink` for anything unknown.
  OtpType _otpTypeFor(String raw) {
    switch (raw.toLowerCase()) {
      case 'signup':
        return OtpType.signup;
      case 'recovery':
        return OtpType.recovery;
      case 'invite':
        return OtpType.invite;
      case 'email_change':
        return OtpType.emailChange;
      case 'magiclink':
      default:
        return OtpType.magiclink;
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Personal Accounting',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SegmentedButton<_Mode>(
                  segments: const [
                    ButtonSegment(
                      value: _Mode.password,
                      label: Text('Password'),
                      icon: Icon(Icons.lock_outline),
                    ),
                    ButtonSegment(
                      value: _Mode.magicLink,
                      label: Text('Magic link'),
                      icon: Icon(Icons.email_outlined),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _busy
                      ? null
                      : (s) => setState(() {
                          _mode = s.first;
                          _statusMessage = null;
                          _linkSent = false;
                        }),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _emailController,
                  enabled: !_busy,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: _mode == _Mode.password
                      ? TextInputAction.next
                      : TextInputAction.go,
                  onSubmitted: (_) {
                    if (_mode == _Mode.magicLink) _sendMagicLink();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_mode == _Mode.password) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _passwordController,
                    enabled: !_busy,
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.go,
                    onSubmitted: (_) => _signInWithPassword(),
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : (_mode == _Mode.password
                            ? _signInWithPassword
                            : _sendMagicLink),
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Icon(
                          _mode == _Mode.password ? Icons.login : Icons.send,
                        ),
                  label: Text(
                    _busy
                        ? (_mode == _Mode.password
                              ? 'Signing in…'
                              : 'Sending…')
                        : (_mode == _Mode.password
                              ? 'Sign in'
                              : 'Send magic link'),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
                if (_mode == _Mode.magicLink) ...[
                  const SizedBox(height: 16),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    initiallyExpanded: _linkSent,
                    title: Text(
                      'Already have a link or code? Paste it',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    children: [
                      const SizedBox(height: 4),
                      Text(
                        'If you have a magic-link email from a previous send, '
                        'copy the link URL (or the `code` value) and paste it '
                        'below. This bypasses the rate limit because no new '
                        'email is sent.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _codeController,
                        enabled: !_verifying,
                        textInputAction: TextInputAction.go,
                        onSubmitted: (_) => _verifyCode(),
                        decoration: const InputDecoration(
                          labelText: 'Paste URL or code',
                          prefixIcon: Icon(Icons.link),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.tonalIcon(
                          onPressed: _verifying ? null : _verifyCode,
                          icon: _verifying
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.check),
                          label: Text(_verifying ? 'Verifying…' : 'Verify'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                if (_statusMessage != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (_isError ? Colors.red : Colors.green).withAlpha(
                        30,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _statusMessage!,
                      style: TextStyle(
                        color: _isError
                            ? Colors.red.shade900
                            : Colors.green.shade900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
