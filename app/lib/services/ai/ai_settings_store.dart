import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'vision_model_config.dart';

/// Persists the AI model endpoint/key/model between runs, like the other stores.
///
/// Note: the API key lives in shared_preferences (app-private storage). Fine for
/// a single-athlete app; a multi-user product would move secrets server-side and
/// proxy the model calls rather than shipping keys to the device.
class AiSettingsStore {
  const AiSettingsStore();

  static const String _key = 'vision_model_config';

  Future<VisionModelConfig> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return const VisionModelConfig();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const VisionModelConfig();
      return VisionModelConfig.fromJson(decoded.cast<String, Object?>());
    } on Object catch (error) {
      debugPrint('Could not load AI settings: $error');
      return const VisionModelConfig();
    }
  }

  Future<void> save(VisionModelConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(config.toJson()));
    } on Object catch (error) {
      debugPrint('Could not save AI settings: $error');
    }
  }
}
