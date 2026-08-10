import 'session_phase.dart';

/// A recorded technical round, sitting on disk and waiting to be reviewed.
///
/// v0.5 stage 0.2 records these but reads nothing out of them — pose analysis
/// arrives in 0.3. What matters here is that every clip knows which round it
/// belongs to (so the review screen can label it) and when it was recorded (so
/// the retention sweep can delete it after seven days).
class RoundClip {
  const RoundClip({
    required this.sessionId,
    required this.segmentIndex,
    required this.phase,
    required this.path,
    required this.recordedAt,
    this.roundNumber,
    this.roundsInPhase,
    this.durationMs,
    this.title,
  });

  /// Identifies the session run this clip came from — a timestamp-based id
  /// minted when the session starts, so a review screen can gather one
  /// session's clips without a database (that lands in 0.5).
  final String sessionId;

  /// The [SessionSegment.index] this clip records. Unique within a session.
  final int segmentIndex;

  final SessionPhase phase;

  /// Absolute path to the video file in the app's clips directory.
  final String path;

  final DateTime recordedAt;

  /// 1-based round number within its phase, mirroring [SessionSegment].
  final int? roundNumber;
  final int? roundsInPhase;

  /// Wall-clock length of the recording, once stop is known.
  final int? durationMs;

  /// The round's headline (theme or exercise label) for the review list.
  final String? title;

  /// "Round 3 of 5" style label, matching the session UI.
  String get positionLabel {
    if (roundNumber == null) return phase.label;
    return 'Round $roundNumber of $roundsInPhase';
  }

  RoundClip copyWith({int? durationMs}) => RoundClip(
    sessionId: sessionId,
    segmentIndex: segmentIndex,
    phase: phase,
    path: path,
    recordedAt: recordedAt,
    roundNumber: roundNumber,
    roundsInPhase: roundsInPhase,
    durationMs: durationMs ?? this.durationMs,
    title: title,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'segmentIndex': segmentIndex,
    'phase': phase.key,
    'path': path,
    'recordedAt': recordedAt.toIso8601String(),
    'roundNumber': roundNumber,
    'roundsInPhase': roundsInPhase,
    'durationMs': durationMs,
    'title': title,
  };

  static RoundClip? fromJson(Map<String, Object?> json) {
    final phase = SessionPhase.fromKey(json['phase'] as String? ?? '');
    final path = json['path'] as String?;
    final recordedAtRaw = json['recordedAt'] as String?;
    final sessionId = json['sessionId'] as String?;
    final recordedAt =
        recordedAtRaw == null ? null : DateTime.tryParse(recordedAtRaw);
    // A clip that cannot say where it lives or when it was made is useless to
    // both the review screen and the retention sweep — drop it rather than
    // surface a half-broken entry.
    if (phase == null ||
        path == null ||
        sessionId == null ||
        recordedAt == null) {
      return null;
    }
    return RoundClip(
      sessionId: sessionId,
      segmentIndex: (json['segmentIndex'] as num?)?.toInt() ?? 0,
      phase: phase,
      path: path,
      recordedAt: recordedAt,
      roundNumber: (json['roundNumber'] as num?)?.toInt(),
      roundsInPhase: (json['roundsInPhase'] as num?)?.toInt(),
      durationMs: (json['durationMs'] as num?)?.toInt(),
      title: json['title'] as String?,
    );
  }
}
