import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/auth/auth_service.dart';
import 'home_screen.dart';
import 'sign_in_screen.dart';

/// Decides what the app shows based on auth state: the sign-in screen when
/// signed out, the app when signed in. Rebuilds on every auth change.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key, this.auth});

  final AuthService? auth;

  @override
  Widget build(BuildContext context) {
    final auth = this.auth ?? AuthService();
    return StreamBuilder<AuthState>(
      stream: auth.authStateChanges,
      builder: (context, _) {
        // currentUser is the source of truth; the stream just triggers rebuilds.
        return auth.isSignedIn ? const HomeScreen() : SignInScreen(auth: auth);
      },
    );
  }
}
