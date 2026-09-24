import 'package:supabase_flutter/supabase_flutter.dart';

/// The weekly AI-analysis allowance shown in-app and passed to
/// `ai_quota_remaining` for the badge.
///
/// ALPHA: bumped 3 -> 50 for alpha testing. Server enforcement is driven by the
/// `AI_WEEKLY_LIMIT` env var on the `analyze` edge function — set it to 50 to
/// match, or the app will show "50 left" but the server still cuts off at its
/// env value. Revert this to 3 (and unset/lower the env) when alpha ends. The
/// public website/terms copy is deliberately left at 3 (the real free tier).
const int kWeeklyAiLimit = 50;

/// Reads how many AI analyses the signed-in user has left this week, via the
/// `ai_quota_remaining` SQL function.
///
/// Returns null whenever an indicator shouldn't show — signed out, offline, an
/// error, or Supabase not initialised (unit tests) — so the UI can simply hide
/// it rather than guess.
class AiQuotaService {
  AiQuotaService({SupabaseClient? client, this.weeklyLimit = kWeeklyAiLimit})
    : _injected = client;

  final SupabaseClient? _injected;
  final int weeklyLimit;

  SupabaseClient? get _client {
    if (_injected != null) return _injected;
    try {
      return Supabase.instance.client;
    } on Object {
      return null;
    }
  }

  Future<int?> remaining() async {
    final client = _client;
    if (client == null || client.auth.currentSession == null) return null;
    try {
      final data = await client.rpc(
        'ai_quota_remaining',
        params: <String, Object?>{'p_weekly_limit': weeklyLimit},
      );
      if (data is num) return data.toInt();
      return null;
    } on Object {
      return null;
    }
  }
}
