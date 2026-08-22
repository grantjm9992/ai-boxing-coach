import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../analysis/round_analysis.dart';
import '../../domain/round_clip.dart';
import '../ai/coaching_prompt.dart';
import '../analysis_store.dart';
import '../debug_log.dart';
import '../frame_grabber.dart';

/// What a sync attempt did — enough to surface on-device so a release build can
/// tell "uploaded" from "signed out", "nothing to sync", and a real failure.
enum SyncStatus {
  /// Rows + blobs pushed (or re-pushed) to Supabase.
  uploaded,

  /// No signed-in user — nothing to sync to. Not an error.
  skippedSignedOut,

  /// No analysis on disk for this round yet — nothing worth syncing.
  skippedNoAnalysis,

  /// A Supabase/network call threw. See [SyncOutcome.error].
  failed,
}

/// The result of a sync attempt. Deliberately never thrown: sync is best-effort
/// and must not break a session, so callers inspect this instead.
class SyncOutcome {
  const SyncOutcome(this.status, {this.error, this.keyframeCount = 0});

  final SyncStatus status;

  /// Set only when [status] is [SyncStatus.failed].
  final Object? error;

  /// Keyframe images uploaded (when [status] is [SyncStatus.uploaded]).
  final int keyframeCount;

  bool get isFailure => status == SyncStatus.failed;
}

/// The round-upload operations the backfill queue drives. Abstracted so the
/// queue can be unit-tested with a fake, without a live Supabase client.
abstract interface class RoundSync {
  Future<SyncOutcome> syncRound(RoundClip clip, {String? title, String? mode});

  Future<SyncOutcome> finalizeSession(
    String clientSessionId, {
    DateTime? endedAt,
    String? title,
    Map<String, Object?>? rollup,
  });
}

/// Pushes a finished round up to Supabase: the session/round/analysis rows, the
/// pose sequence and the keyframe images to Storage.
///
/// It reads what to upload from the local [AnalysisStore] — which the analyzer
/// has already written — so the on-device copy stays the source of truth and
/// this is pure "upload when online". Everything is best-effort: not signed in,
/// offline, or a failed call simply means the round syncs later, never a broken
/// session. Idempotent via upserts, so re-running (a re-analyse, a backfill) is
/// safe.
class SupabaseRoundSync implements RoundSync {
  SupabaseRoundSync({
    SupabaseClient? client,
    AnalysisStore? store,
    FrameGrabber? grabber,
  }) : _client = client ?? Supabase.instance.client,
       _store = store ?? AnalysisStore(),
       _grabber = grabber ?? PluginFrameGrabber();

  final SupabaseClient _client;
  final AnalysisStore _store;
  final FrameGrabber _grabber;

  /// Sync one round. [title] labels the session (the template name); [mode] is
  /// the analysis mode value ('offline' | 'keyframe' | 'full_frame').
  @override
  Future<SyncOutcome> syncRound(
    RoundClip clip, {
    String? title,
    String? mode,
  }) async {
    final ref = '${clip.sessionId}/seg${clip.segmentIndex}';
    void trace(String step) => DebugLog.instance.log('$ref $step', tag: 'sync');

    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      trace('skipped — signed out');
      return const SyncOutcome(SyncStatus.skippedSignedOut); // nothing to sync to
    }
    trace('start (mode=$mode, user=${userId.substring(0, 8)}…)');
    try {
      final analysis =
          await _store.loadAnalysis(clip.sessionId, clip.segmentIndex);
      if (analysis == null) {
        trace('skipped — no analysis on disk');
        return const SyncOutcome(SyncStatus.skippedNoAnalysis);
      }
      final sequence = await _store.loadPose(clip.sessionId, clip.segmentIndex);

      // 1. Session row (idempotent on user + the app's session id).
      final session = await _client
          .from('sessions')
          .upsert(<String, Object?>{
            'user_id': userId,
            'client_session_id': clip.sessionId,
            'title': ?title,
            ..._startedAt(clip.sessionId),
          }, onConflict: 'user_id,client_session_id')
          .select('id')
          .single();
      final sessionId = session['id'] as String;
      trace('session row ok');

      // 2. Round row.
      final posePath =
          '$userId/${clip.sessionId}/${clip.segmentIndex}.pose.json';
      final round = await _client
          .from('rounds')
          .upsert(<String, Object?>{
            'user_id': userId,
            'session_id': sessionId,
            'segment_index': clip.segmentIndex,
            'phase': clip.phase.key,
            'round_number': clip.roundNumber,
            'rounds_in_phase': clip.roundsInPhase,
            'title': clip.title,
            'duration_ms': clip.durationMs,
            'recorded_at': clip.recordedAt.toIso8601String(),
            if (sequence != null) 'pose_path': posePath,
          }, onConflict: 'session_id,segment_index')
          .select('id')
          .single();
      final roundId = round['id'] as String;
      trace('round row ok');

      // 3. Pose sequence to Storage.
      if (sequence != null) {
        await _client.storage.from('pose').uploadBinary(
              posePath,
              utf8.encode(jsonEncode(sequence.toJson())),
              fileOptions: const FileOptions(
                upsert: true,
                contentType: 'application/json',
              ),
            );
        trace('pose uploaded');
      }

      // 4. Analysis row.
      await _client.from('analyses').upsert(<String, Object?>{
        'user_id': userId,
        'round_id': roundId,
        'mode': mode ?? (analysis.modelCoaching != null ? 'ai' : 'offline'),
        'summary': analysis.overallSummary,
        'metrics': analysis.metrics.toJson(),
        'corrections':
            analysis.correctionPriorities.map((c) => c.toJson()).toList(),
        'positive_notes': analysis.positiveNotes,
        'ai_coaching': analysis.modelCoaching,
      }, onConflict: 'round_id');
      trace('analysis row ok');

      // 5. Keyframe images (a burst per flagged moment) to Storage + rows.
      final keyframes = await _syncKeyframes(
        userId,
        roundId,
        clip,
        analysis,
        sequence?.durationMs.toDouble() ?? 0,
      );
      trace('done — $keyframes keyframes');
      return SyncOutcome(SyncStatus.uploaded, keyframeCount: keyframes);
    } on Object catch (error) {
      trace('FAILED: $error');
      debugPrint(
        'Round sync failed for ${clip.sessionId}/${clip.segmentIndex}: $error',
      );
      return SyncOutcome(SyncStatus.failed, error: error);
    }
  }

  /// Mark a session finished. Safe to call even if no round synced (updates 0
  /// rows). [rollup] is the session-level summary (total/work seconds, round
  /// count, category seconds) stored so the history list + weekly balance can be
  /// rebuilt from the cloud on a fresh install or another device.
  @override
  Future<SyncOutcome> finalizeSession(
    String clientSessionId, {
    DateTime? endedAt,
    String? title,
    Map<String, Object?>? rollup,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const SyncOutcome(SyncStatus.skippedSignedOut);
    try {
      await _client
          .from('sessions')
          .update(<String, Object?>{
            'ended_at': (endedAt ?? DateTime.now()).toIso8601String(),
            'title': ?title,
            'plan': ?rollup,
          })
          .eq('user_id', userId)
          .eq('client_session_id', clientSessionId);
      return const SyncOutcome(SyncStatus.uploaded);
    } on Object catch (error) {
      debugPrint('Session finalize failed for $clientSessionId: $error');
      return SyncOutcome(SyncStatus.failed, error: error);
    }
  }

  /// Uploads a burst of frames around each flagged moment — the same frames the
  /// model reviews — grouped by moment (correction_index + the correction text
  /// in correction_ref), so the review/history view can show them moment by
  /// moment. Returns how many frames landed.
  Future<int> _syncKeyframes(
    String userId,
    String roundId,
    RoundClip clip,
    RoundAnalysis analysis,
    double durationMs,
  ) async {
    final bursts = CoachingPrompt.keyframeBursts(analysis, durationMs: durationMs);
    if (bursts.isEmpty) return 0;

    // Flatten to (moment index, label, timestamp) so grabbed images map back to
    // their moment. One grab call for the whole round.
    final requests = <({int moment, String label, int ts})>[];
    for (var m = 0; m < bursts.length; m++) {
      final burst = bursts[m];
      final label = burst.label ?? 'Flagged moment';
      for (final ts in burst.timestamps) {
        requests.add((moment: m, label: label, ts: ts.round()));
      }
    }
    final images =
        await _grabber.grab(clip.path, <double>[for (final r in requests) r.ts.toDouble()]);
    if (images.isEmpty) return 0;

    // Replace any existing frames for this round so a re-sync doesn't dupe.
    await _client.from('keyframes').delete().eq('round_id', roundId);
    final rows = <Map<String, Object?>>[];
    for (var i = 0; i < images.length && i < requests.length; i++) {
      final req = requests[i];
      final path =
          '$userId/${clip.sessionId}/${clip.segmentIndex}/${req.moment}_${req.ts}.jpg';
      await _client.storage.from('keyframes').uploadBinary(
            path,
            images[i].bytes,
            fileOptions: FileOptions(upsert: true, contentType: images[i].mime),
          );
      rows.add(<String, Object?>{
        'user_id': userId,
        'round_id': roundId,
        'storage_path': path,
        'timestamp_ms': req.ts,
        'correction_ref': req.label,
        'correction_index': req.moment,
        'mime': images[i].mime,
      });
    }
    if (rows.isNotEmpty) await _client.from('keyframes').insert(rows);
    return rows.length;
  }

  /// The app's session id is epoch-millis at session start; use it for a real
  /// started_at when we can parse it, else let the column default to now().
  Map<String, Object?> _startedAt(String clientSessionId) {
    final millis = int.tryParse(clientSessionId);
    if (millis == null) return const <String, Object?>{};
    return <String, Object?>{
      'started_at':
          DateTime.fromMillisecondsSinceEpoch(millis).toIso8601String(),
    };
  }
}
