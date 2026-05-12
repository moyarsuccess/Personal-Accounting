import 'package:flutter/material.dart';
import 'package:personal_accounting/screens/login_screen.dart';
import 'package:personal_accounting/screens/main_navigation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Listens to Supabase auth state and routes to either the login screen
/// or the main app shell. Listening directly to the SDK's `onAuthStateChange`
/// stream means sign-in / sign-out reflects instantly without a manual
/// Navigator push.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        // First frame — fall back to the SDK's current cached session.
        final session = snapshot.hasData
            ? snapshot.data!.session
            : Supabase.instance.client.auth.currentSession;

        if (session == null) {
          return const LoginScreen();
        }
        return const MainNavigation();
      },
    );
  }
}
