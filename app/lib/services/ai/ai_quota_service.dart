import 'package:supabase_flutter/supabase_flutter.dart';

/// The free-tier weekly AI-analysis allowance. Mirrors the server default in
/// migration 0003 (`consume_ai_quota` / `ai_quota_remaining`) and the website
/// copy — keep the three in step.
const int kWeeklyAiLimit = 3;

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
