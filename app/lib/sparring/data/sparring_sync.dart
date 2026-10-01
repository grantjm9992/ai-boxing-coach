import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/debug_log.dart';
import '../model/fighter.dart';
import 'sparring_store.dart';

/// Pushes analysed sparring rounds to Supabase — its own tables
/// (`sparring_sessions`, `sparring_rounds`, `sparring_fighters`) and its own
/// Storage bucket (`sparring`), via its own queue. Nothing here touches the
/// single-person sync or its tables.
///
/// Best-effort and idempotent (upserts): signed out or offline just leaves the
/// round queued for next time.
abstract interface class SparringUploader {
  /// True when uploaded; false when it should be retried later.
  Future<bool> upload(String sessionId, int round);
}

class SupabaseSparringUploader implements SparringUploader {
  SupabaseSparringUploader({SupabaseClient? client, SparringStore? store})
    : _client = client,
      _store = store ?? SparringStore();

  final SupabaseClient? _client;
  final SparringStore _store;

  SupabaseClient? get _supabase {
    if (_client != null) return _client;
    try {
      return Supabase.instance.client;
    } on Object {
      return null;
    }
  }

  @override
  Future<bool> upload(String sessionId, int round) async {
    void trace(String s) => DebugLog.instance.log('$sessionId/r$round $s', tag: 'sparring-sync');
    final client = _supabase;
    final userId = client?.auth.currentUser?.id;
    if (client == null || userId == null) {
      trace('skipped — signed out');
      return false;
    }
    final session = await _store.loadSession(sessionId);
    final analysis = await _store.loadAnalysis(sessionId, round);
    final roundInfo = session?.round(round);
    if (session == null || analysis == null || roundInfo == null) {
      trace('skipped — nothing analysed');
      return true; // nothing to do; don't keep retrying
    }
    try {
      final sessionRow = await client
          .from('sparring_sessions')
          .upsert(<String, Object?>{
            'user_id': userId,
            'client_session_id': session.id,
            'started_at': session.createdAt.toUtc().toIso8601String(),
            'settings': session.settings.toJson(),
            'partner_name': session.partnerName,
            'identified': session.identified,
          }, onConflict: 'user_id,client_session_id')
          .select('id')
          .single();
      final sessionRowId = sessionRow['id'] as String;

      // Pose sequences per fighter, for re-analysis later.
      final paths = <FighterLabel, String>{};
      for (final label in FighterLabel.values) {
        final file = await _store.fighterFile(sessionId, round, label);
        if (file == null) continue;
        final path = '$userId/${session.id}/r$round/fighter_${label.value}.json';
        await client.storage.from('sparring').uploadBinary(
          path,
          await file.readAsBytes(),
          fileOptions: const FileOptions(upsert: true, contentType: 'application/json'),
        );
        paths[label] = path;
      }

      final roundRow = await client
          .from('sparring_rounds')
          .upsert(<String, Object?>{
            'user_id': userId,
            'session_id': sessionRowId,
            'round_number': round,
            'recorded_at': roundInfo.recordedAt.toUtc().toIso8601String(),
            'duration_ms': analysis.durationMs.round(),
            'unresolved_ms': <String, int>{
              for (final e in analysis.unresolvedMs.entries) e.key.value: e.value.round(),
            },
            'interaction': jsonSafe(analysis.interaction.toJson()),
            'ai_report': jsonSafe(analysis.ai?.toJson()),
            'mode': analysis.ai == null ? 'offline' : 'full_frame',
          }, onConflict: 'session_id,round_number')
          .select('id')
          .single();
      final roundRowId = roundRow['id'] as String;

      for (final label in FighterLabel.values) {
        final f = analysis.fighter(label);
        await client.from('sparring_fighters').upsert(<String, Object?>{
          'user_id': userId,
          'round_id': roundRowId,
          'label': label.value,
          'is_user': session.identified && label == FighterLabel.a,
          'display_name': session.nameOf(label),
          'metrics': jsonSafe(<String, Object?>{
            'stance': f.stance.name,
            'analysedSeconds': f.analysedSeconds,
            'punches': f.punchCount,
            'punchesPerMinute': f.punchesPerMinute,
            'punchMix': f.punchMix,
          }),
          'findings': jsonSafe(<Object?>[for (final x in f.findings) x.toJson()]),
          'strengths': f.strengths,
          'summary': f.summary,
          'pose_path': paths[label],
        }, onConflict: 'round_id,label');
      }
      trace('uploaded');
      return true;
    } on Object catch (error) {
      trace('failed: $error');
      return false;
    }
  }
}

/// A durable queue of rounds waiting to upload (SharedPreferences), drained
/// after each round finishes and whenever sparring screens open.
class SparringSyncQueue {
  SparringSyncQueue._({SparringUploader? uploader}) : _uploader = uploader;

  static final SparringSyncQueue instance = SparringSyncQueue._();

  /// A queue with an injected uploader, for tests.
  factory SparringSyncQueue.forTesting(SparringUploader uploader) =>
      SparringSyncQueue._(uploader: uploader);

  static const String _key = 'sparring_sync_queue';

  SparringUploader? _uploader;
  SparringUploader get _up => _uploader ??= SupabaseSparringUploader();
  Future<void>? _running;

  Future<void> enqueue(String sessionId, int round) async {
    final prefs = await SharedPreferences.getInstance();
    final items = prefs.getStringList(_key) ?? <String>[];
    final item = '$sessionId#$round';
    if (!items.contains(item)) {
      items.add(item);
      await prefs.setStringList(_key, items);
    }
  }

  Future<List<String>> pending() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_key) ?? <String>[];
  }

  /// Tries every queued round once. Concurrent calls share one run.
  Future<void> process() => _running ??= _process().whenComplete(() => _running = null);

  Future<void> _process() async {
    final prefs = await SharedPreferences.getInstance();
    final items = List<String>.of(prefs.getStringList(_key) ?? <String>[]);
    final remaining = <String>[];
    for (final item in items) {
      final hash = item.lastIndexOf('#');
      final round = hash < 0 ? null : int.tryParse(item.substring(hash + 1));
      if (round == null) continue;
      final ok = await _up.upload(item.substring(0, hash), round);
      if (!ok) remaining.add(item);
    }
    // Keep anything enqueued while we were running.
    final now = prefs.getStringList(_key) ?? <String>[];
    final next = <String>[
      ...remaining,
      for (final item in now)
        if (!items.contains(item) && !remaining.contains(item)) item,
    ];
    await prefs.setStringList(_key, next);
  }
}

