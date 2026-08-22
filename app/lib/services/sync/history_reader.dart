import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../debug_log.dart';

/// One keyframe image for a past round: a short-lived signed URL into the
/// private `keyframes` bucket, plus where in the round it was grabbed.
class HistoryKeyframe {
  const HistoryKeyframe({required this.url, required this.timestampMs});

  final String url;
  final int timestampMs;
}

/// One flagged moment: the correction's text and the burst of frames the model
/// reviewed for it.
class HistoryMoment {
  const HistoryMoment({required this.label, required this.keyframes});

  final String label;
  final List<HistoryKeyframe> keyframes;
}

/// A round's analysis as read back from Supabase — the full feedback (not the
/// one-line rollup kept locally) plus its keyframes, grouped moment by moment.
class HistoryRound {
  const HistoryRound({
    required this.segmentIndex,
    required this.title,
    this.roundNumber,
    this.summary,
    this.aiCoaching,
    this.corrections = const <String>[],
    this.positiveNotes = const <String>[],
    this.moments = const <HistoryMoment>[],
  });

  final int segmentIndex;
  final String title;
  final int? roundNumber;
  final String? summary;
  final String? aiCoaching;
  final List<String> corrections;
  final List<String> positiveNotes;

  /// Frames grouped by flagged moment (each ~7 frames). Empty for rounds synced
  /// before grouping, or offline rounds with no flagged frames.
  final List<HistoryMoment> moments;
}

/// A past session's full detail, read back from the cloud.
class HistorySession {
  const HistorySession({required this.rounds});

  final List<HistoryRound> rounds;
}

/// Reads a completed session back from Supabase for the history detail view:
/// the full per-round analysis and signed URLs for its keyframe images. This is
/// what lets old feedback (and the frames it points at) survive the 7-day sweep
/// of the local video + analysis.
///
/// Best-effort: signed out, offline, or any failed call returns null, and the
/// caller falls back to the thin local rollup.
class SupabaseHistoryReader {
  SupabaseHistoryReader({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// How long the keyframe image URLs stay valid — long enough to browse.
  static const int _signedUrlTtlSeconds = 3600;

  Future<HistorySession?> loadSession(String clientSessionId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;
    void trace(String step) =>
        DebugLog.instance.log('$clientSessionId $step', tag: 'history');
    try {
      final session = await _client
          .from('sessions')
          .select('id')
          .eq('user_id', userId)
          .eq('client_session_id', clientSessionId)
          .maybeSingle();
      if (session == null) {
        trace('no cloud session row');
        return null;
      }
      final sessionId = session['id'] as String;

      final rows = await _client
          .from('rounds')
          .select(
            'id, segment_index, round_number, title, '
            'analyses(summary, ai_coaching, corrections, positive_notes), '
            'keyframes(storage_path, timestamp_ms, correction_ref, correction_index)',
          )
          .eq('session_id', sessionId)
          .order('segment_index');

      final rounds = <HistoryRound>[];
      for (final row in rows) {
        final analysis = _one(row['analyses']);
        final moments = await _signMoments(_list(row['keyframes']));
        rounds.add(
          HistoryRound(
            segmentIndex: (row['segment_index'] as num).toInt(),
            title: row['title'] as String? ?? 'Round',
            roundNumber: (row['round_number'] as num?)?.toInt(),
            summary: analysis?['summary'] as String?,
            aiCoaching: analysis?['ai_coaching'] as String?,
            corrections: _corrections(analysis?['corrections']),
            positiveNotes: _strings(analysis?['positive_notes']),
            moments: moments,
          ),
        );
      }
      trace('loaded ${rounds.length} rounds');
      return HistorySession(rounds: rounds);
    } on Object catch (error) {
      DebugLog.instance
          .log('$clientSessionId read failed: $error', tag: 'history');
      debugPrint('History read failed for $clientSessionId: $error');
      return null;
    }
  }

  /// Group keyframe rows into moments (by correction_index), order the frames in
  /// each by time, and sign every URL. Moments are ordered by index; rows with
  /// no index (pre-grouping data) fall into a single trailing group.
  Future<List<HistoryMoment>> _signMoments(List<Object?> rows) async {
    final frames = rows
        .whereType<Map<String, Object?>>()
        .map((r) => (
              path: r['storage_path'] as String?,
              ts: (r['timestamp_ms'] as num?)?.toInt() ?? 0,
              index: (r['correction_index'] as num?)?.toInt() ?? -1,
              label: r['correction_ref'] as String?,
            ))
        .where((f) => f.path != null)
        .toList();
    if (frames.isEmpty) return const <HistoryMoment>[];

    final byIndex = <int, List<({String? path, int ts, int index, String? label})>>{};
    for (final f in frames) {
      byIndex.putIfAbsent(f.index, () => []).add(f);
    }
    final orderedKeys = byIndex.keys.toList()..sort();

    final moments = <HistoryMoment>[];
    for (final key in orderedKeys) {
      final group = byIndex[key]!..sort((a, b) => a.ts.compareTo(b.ts));
      final keyframes = <HistoryKeyframe>[];
      for (final f in group) {
        final url = await _client.storage
            .from('keyframes')
            .createSignedUrl(f.path!, _signedUrlTtlSeconds);
        keyframes.add(HistoryKeyframe(url: url, timestampMs: f.ts));
      }
      final label = group
              .map((f) => f.label)
              .firstWhere((l) => l != null && l.isNotEmpty, orElse: () => null) ??
          'Flagged moment';
      moments.add(HistoryMoment(label: label, keyframes: keyframes));
    }
    return moments;
  }

  // Supabase returns an embedded to-one relation as a Map (or a single-element
  // list depending on the client); normalise both.
  Map<String, Object?>? _one(Object? value) {
    if (value is Map) return value.cast<String, Object?>();
    if (value is List && value.isNotEmpty && value.first is Map) {
      return (value.first as Map).cast<String, Object?>();
    }
    return null;
  }

  List<Object?> _list(Object? value) => value is List ? value : const <Object?>[];

  List<String> _corrections(Object? value) {
    if (value is! List) return const <String>[];
    return value
        .whereType<Map>()
        .map((m) => m['description'] as String?)
        .whereType<String>()
        .toList();
  }

  List<String> _strings(Object? value) {
    if (value is! List) return const <String>[];
    return value.whereType<String>().toList();
  }
}
