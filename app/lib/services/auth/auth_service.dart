import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_config.dart';

/// Thrown for a failed auth action, with a message fit to show the user.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
  @override
  String toString() => 'AuthFailure: $message';
}

/// The app's front door to Supabase auth. Wraps the SDK so the UI depends on a
/// small, testable surface rather than the client directly.
class AuthService {
  AuthService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// Initialise the Supabase SDK. Call once, before `runApp`.
  static Future<void> initialize() async {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      publishableKey: SupabaseConfig.publishableKey,
    );
  }

  /// The signed-in user, or null.
  User? get currentUser => _client.auth.currentUser;

  bool get isSignedIn => currentUser != null;

  /// Emits on every sign-in / sign-out / token refresh, so an auth gate can
  /// rebuild.
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<void> signUpWithEmail(String email, String password) async {
    try {
      await _client.auth.signUp(email: email.trim(), password: password);
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    } on Object catch (e) {
      throw AuthFailure('Could not sign up: $e');
    }
  }

  Future<void> signInWithEmail(String email, String password) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    } on Object catch (e) {
      throw AuthFailure('Could not sign in: $e');
    }
  }

  /// Google sign-in via Supabase OAuth. Requires the Google provider to be
  /// enabled in the Supabase dashboard and the app's deep-link redirect
  /// registered (see docs/backend-setup.md). Opens a browser tab; the app is
  /// re-entered via the redirect and [authStateChanges] fires.
  Future<void> signInWithGoogle() async {
    try {
      await _client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: _oauthRedirect,
      );
    } on AuthException catch (e) {
      throw AuthFailure(e.message);
    } on Object catch (e) {
      throw AuthFailure('Could not start Google sign-in: $e');
    }
  }

  Future<void> signOut() => _client.auth.signOut();

  /// The signed-in user's email, if any (for the account UI).
  String? get currentEmail => currentUser?.email;

  /// Permanently deletes the account and all its data (Storage + DB rows), then
  /// signs out. Backed by the `delete-account` edge function (deleting an auth
  /// user needs the service role, which can't live on the device). Google Play
  /// requires an in-app deletion path for apps with accounts.
  Future<void> deleteAccount() async {
    try {
      final res = await _client.functions.invoke('delete-account');
      if (res.status != 200) {
        final data = res.data;
        final message = data is Map && data['error'] is Map
            ? (data['error'] as Map)['message']?.toString()
            : null;
        throw AuthFailure(message ?? 'Could not delete your account.');
      }
      await _client.auth.signOut();
    } on AuthFailure {
      rethrow;
    } on FunctionException catch (e) {
      throw AuthFailure('Could not delete your account: ${e.reasonPhrase}');
    } on Object catch (e) {
      throw AuthFailure('Could not delete your account: $e');
    }
  }

  /// Deep link the OAuth flow returns to. Matches the scheme registered in the
  /// Android manifest / iOS Info.plist and the Supabase redirect allow-list.
  static const String _oauthRedirect =
      'com.aiboxingcoach.boxing_coach://login-callback';
}
