import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/session_settings.dart';
import '../domain/session_template.dart';

/// Remembers how the athlete configured each template last time.
///
/// Boxers do not re-tune their round lengths every session; they set them once
/// and then live with them. Anything that fails here falls back to the
/// template's defaults rather than surfacing an error — a lost slider position
/// is not worth a dialog.
class SettingsStore {
  const SettingsStore();

  static String _key(String templateId) => 'session_settings.$templateId';

  Future<SessionSettings> load(SessionTemplate template) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key(template.id));
      if (raw == null) return SessionSettings.fromTemplate(template);
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return SessionSettings.fromTemplate(template);
      return SessionSettings.fromJson(
        decoded.cast<String, Object?>(),
        template,
      );
    } on Object catch (error) {
      debugPrint('Could not load settings for ${template.id}: $error');
      return SessionSettings.fromTemplate(template);
    }
  }

  Future<void> save(SessionTemplate template, SessionSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(template.id), jsonEncode(settings.toJson()));
    } on Object catch (error) {
      debugPrint('Could not save settings for ${template.id}: $error');
    }
  }
}
