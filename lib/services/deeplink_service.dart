import 'dart:async';
import 'dart:io';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:personal_accounting/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Owns:
///  1. **Windows/Linux scheme registration** — writes the registry/.desktop
///     entries that tell the OS to launch this exe when a
///     `personalaccounting://` URL is opened.
///  2. **App-link listener** — when the OS hands a URL to the running app
///     (or to a cold-start), parses the `?code=` param and finishes the
///     Supabase PKCE session so the user lands signed-in with no copy/paste.
///
/// `init()` is called once from `main.dart` BEFORE `runApp` so that:
///  - the scheme is registered ASAP on first launch (one-shot, idempotent);
///  - the cold-start link (passed via `argv` on Windows) is drained
///    immediately, otherwise the URL would silently disappear.
class DeeplinkService {
  static final DeeplinkService instance = DeeplinkService._();
  DeeplinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    // Step 1: register OS-level scheme handler (idempotent — safe every launch).
    await _registerSchemeIfNeeded();

    // Step 2: drain cold-start link (the URL the app was launched WITH).
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        await _handleLink(initial);
      }
    } catch (e) {
      // Non-fatal — user can still paste-URL fall back.
      debugPrint('DeeplinkService: getInitialLink failed: $e');
    }

    // Step 3: listen for hot links (subsequent magic-link clicks while the
    // app is running).
    _sub = _appLinks.uriLinkStream.listen(
      _handleLink,
      onError: (e) => debugPrint('DeeplinkService: link stream error: $e'),
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
  }

  /// Called for every incoming `personalaccounting://...` URL. Extracts the
  /// `code` query param (PKCE) and asks Supabase to swap it for a session.
  /// The auth-state stream is already wired into [AuthGate], so a successful
  /// exchange flips the UI to the main screen automatically.
  Future<void> _handleLink(Uri uri) async {
    debugPrint('DeeplinkService: received $uri');
    final code = uri.queryParameters['code'];
    if (code == null || code.isEmpty) {
      debugPrint('DeeplinkService: no `code` param, ignoring.');
      return;
    }
    try {
      await Supabase.instance.client.auth.exchangeCodeForSession(code);
      debugPrint('DeeplinkService: session created.');
    } catch (e) {
      debugPrint('DeeplinkService: exchangeCodeForSession failed: $e');
    }
  }

  // ─── Scheme registration ───────────────────────────────────────────────────

  Future<void> _registerSchemeIfNeeded() async {
    if (kIsWeb) return;
    try {
      if (Platform.isWindows) {
        await _registerWindowsScheme();
      } else if (Platform.isLinux) {
        await _registerLinuxScheme();
      }
      // macOS / iOS / Android need manifest entries — handled at build time,
      // not runtime.
    } catch (e) {
      debugPrint('DeeplinkService: scheme registration failed: $e');
    }
  }

  /// Writes three registry keys under `HKCU\Software\Classes` so that
  /// clicking a `personalaccounting://` URL launches this exe. HKCU = per-user,
  /// no admin elevation needed. Idempotent — `reg add /f` overwrites silently.
  Future<void> _registerWindowsScheme() async {
    final exe = Platform.resolvedExecutable;
    final scheme = SupabaseConfig.authScheme;
    final base = r'HKCU\Software\Classes\' + scheme;

    // Quoting matters: the registry value must be exactly:  "<exe>" "%1"
    // including the literal %1, which Windows replaces with the URL.
    final command = '"$exe" "%1"';

    await Process.run('reg.exe', [
      'add',
      base,
      '/ve',
      '/t',
      'REG_SZ',
      '/d',
      'URL:Personal Accounting',
      '/f',
    ]);
    await Process.run('reg.exe', [
      'add',
      base,
      '/v',
      'URL Protocol',
      '/t',
      'REG_SZ',
      '/d',
      '',
      '/f',
    ]);
    await Process.run('reg.exe', [
      'add',
      '$base\\shell\\open\\command',
      '/ve',
      '/t',
      'REG_SZ',
      '/d',
      command,
      '/f',
    ]);
    debugPrint('DeeplinkService: registered Windows scheme $scheme:// → $exe');
  }

  /// Writes a `~/.local/share/applications/<app>.desktop` file with a
  /// MimeType=x-scheme-handler/<scheme> line, then asks xdg to refresh
  /// its mime cache.
  Future<void> _registerLinuxScheme() async {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return;

    final exe = Platform.resolvedExecutable;
    final scheme = SupabaseConfig.authScheme;
    final dir = Directory('$home/.local/share/applications');
    if (!await dir.exists()) await dir.create(recursive: true);

    final file = File('${dir.path}/personal_accounting.desktop');
    await file.writeAsString('''
[Desktop Entry]
Name=Personal Accounting
Exec="$exe" %u
Type=Application
NoDisplay=true
MimeType=x-scheme-handler/$scheme;
''');

    await Process.run('xdg-mime', [
      'default',
      'personal_accounting.desktop',
      'x-scheme-handler/$scheme',
    ]);
    await Process.run('update-desktop-database', [dir.path]);
    debugPrint('DeeplinkService: registered Linux scheme $scheme://');
  }
}
