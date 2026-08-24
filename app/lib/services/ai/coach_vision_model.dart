import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_config.dart';
import 'openai_compatible_vision_model.dart';
import 'vision_model.dart';
import 'vision_model_config.dart';

/// The shipped coaching model. Calls the Supabase `analyze` edge function, which
/// holds the real provider key server-side and enforces the free-tier weekly cap
/// (see docs/AI_PROXY.md). No API key lives on the device — the bearer is the
/// signed-in user's Supabase access token, read fresh on each call because
/// tokens refresh.
///
/// It reuses [OpenAiCompatibleVisionModel] for the actual HTTP: the proxy speaks
/// the same OpenAI chat-completions shape, so only the base URL + bearer differ.
class CoachVisionModel implements VisionModel {
  CoachVisionModel({String? Function()? accessToken, this.httpClient})
    : _accessToken =
          accessToken ??
          (() => Supabase.instance.client.auth.currentSession?.accessToken);

  final String? Function() _accessToken;
  final http.Client? httpClient;

  /// The function's base; [OpenAiCompatibleVisionModel] appends
  /// `/chat/completions`.
  static String get endpointBaseUrl =>
      '${SupabaseConfig.url}/functions/v1/analyze';

  @override
  String get label => 'AI Coach';

  @override
  Future<String> complete(VisionRequest request) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const VisionModelException('Sign in to get AI coaching.');
    }
    final model = OpenAiCompatibleVisionModel(
      // `model` is non-empty only to satisfy isConfigured — the server picks the
      // real model and ignores this value.
      VisionModelConfig(baseUrl: endpointBaseUrl, apiKey: token, model: 'coach'),
      client: httpClient,
    );
    try {
      return await model.complete(request);
    } on VisionModelException catch (e) {
      if (e.message.contains('429') || e.message.contains('ai_quota_exceeded')) {
        throw const VisionModelException(
          "You've used all your free AI analyses this week — resets Monday.",
        );
      }
      rethrow;
    } finally {
      model.close();
    }
  }
}

/// Picks the coaching model for a round:
///  - the user's own OpenAI-compatible endpoint when they've enabled the
///    advanced "use my endpoint" option and filled it in (dev / self-host);
///  - otherwise the hosted proxy, when signed in;
///  - otherwise null — no AI, the round stays on offline pose+rules.
VisionModel? resolveCoachVisionModel({required VisionModelConfig config}) {
  if (config.useCustomEndpoint && config.isConfigured) {
    return OpenAiCompatibleVisionModel(config);
  }
  try {
    if (Supabase.instance.client.auth.currentSession != null) {
      return CoachVisionModel();
    }
  } on Object {
    // Supabase not initialised (e.g. unit tests) — no hosted AI available.
  }
  return null;
}
