/// Supabase project configuration.
///
/// The publishable key (sb_publishable_…) is intentionally embedded here —
/// Supabase designs this key to be safe in client code. Row-Level Security
/// policies in `supabase/migrations/001_init.sql` enforce per-user data
/// isolation. The SECRET key (sb_secret_…) must never appear in this file.
class SupabaseConfig {
  static const String url = 'https://edojyivcsindlsocuvwo.supabase.co';

  /// Publishable / anon key — safe to ship in client binaries.
  static const String publishableKey =
      'sb_publishable_sKFxp1r3FNcxZLg94H3MKw_nPWCr-2G';

  /// Custom URL scheme used by magic-link auth.
  ///
  /// The Supabase dashboard must list this EXACT URL under
  /// Authentication → URL Configuration → Redirect URLs (the "Additional
  /// Redirect URLs" section). On Windows/Linux the app self-registers the
  /// scheme on first launch (see `DeeplinkService`); on iOS/Android/macOS it
  /// must be declared in the platform manifest (Info.plist / AndroidManifest
  /// / Info.plist respectively).
  static const String authScheme = 'personalaccounting';
  static const String authRedirect = '$authScheme://login-callback/';
}
