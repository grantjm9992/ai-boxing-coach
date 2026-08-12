import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/user_profile.dart';

/// Remembers the athlete's profile (stance, style, school) between runs, the
/// same way [SettingsStore] remembers session configuration. Anything that fails
/// falls back to the neutral default rather than surfacing an error.
class ProfileStore {
  const ProfileStore();

  static const String _key = 'user_profile';

  Future<UserProfile> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const UserProfile();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const UserProfile();
      return UserProfile.fromJson(decoded.cast<String, Object?>());
    } on Object catch (error) {
      debugPrint('Could not load profile: $error');
      return const UserProfile();
    }
  }

  Future<void> save(UserProfile profile) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(profile.toJson()));
    } on Object catch (error) {
      debugPrint('Could not save profile: $error');
    }
  }
}
