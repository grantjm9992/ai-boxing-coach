import 'exercise.dart';
import 'session_phase.dart';
import 'session_settings.dart';
import 'session_template.dart';
import 'skill_category.dart';

enum SegmentKind {
  /// Working: a round, or a step of the warm-up / cool-down sequence.
  work,

  /// Between rounds.
  rest,
}

/// One timed block of a session. The engine walks a flat list of these; the
/// phase structure lives in their metadata rather than in a nested tree, which
/// keeps the timer and the cue scheduler simple.
class SessionSegment {
  const SessionSegment({
    required this.index,
    required this.phase,
    required this.kind,
    required this.duration,
    required this.exercise,
    required this.startOffset,
    this.theme,
    this.note,
    this.roundNumber,
    this.roundsInPhase,
    required this.isFirstOfPhase,
    required this.isLastOfPhase,
  });

  /// Position in the session's flat segment list.
  final int index;

  final SessionPhase phase;
  final SegmentKind kind;
  final Duration duration;

  /// The exercise being worked. Rest segments carry the exercise just finished
  /// so the UI can keep showing context; the next-up preview comes from the
  /// following segment.
  final Exercise exercise;

  /// Time from the start of the session to the start of this segment.
  final Duration startOffset;

  final String? theme;
  final String? note;

  /// 1-based round number within its phase. Null for continuous phases.
  final int? roundNumber;
  final int? roundsInPhase;

  final bool isFirstOfPhase;
  final bool isLastOfPhase;

  bool get isWork => kind == SegmentKind.work;
  bool get isRest => kind == SegmentKind.rest;

  /// What the UI shows as the segment's headline.
  String get title => theme ?? exercise.label;

  /// "Round 3 of 5" / "Warm-up".
  String get positionLabel {
    if (roundNumber == null) return phase.label;
    return 'Round $roundNumber of $roundsInPhase';
  }
}

/// A template plus a configuration, expanded into the exact list of segments
/// that will be run.
class SessionPlan {
  SessionPlan({
    required this.template,
    required this.settings,
    required List<SessionSegment> segments,
  }) : segments = List<SessionSegment>.unmodifiable(segments);

  final SessionTemplate template;
  final SessionSettings settings;
  final List<SessionSegment> segments;

  Duration get totalDuration => segments.fold(
    Duration.zero,
    (total, segment) => total + segment.duration,
  );

  /// Total working time, rest excluded.
  Duration get workDuration => segments
      .where((segment) => segment.isWork)
      .fold(Duration.zero, (total, segment) => total + segment.duration);

  int get roundCount => segments
      .where((segment) => segment.isWork && segment.roundNumber != null)
      .length;

  List<SessionPhase> get activePhases {
    final phases = <SessionPhase>[];
    for (final segment in segments) {
      if (phases.isEmpty || phases.last != segment.phase) {
        phases.add(segment.phase);
      }
    }
    return phases;
  }

  List<SessionSegment> segmentsFor(SessionPhase phase) =>
      segments.where((segment) => segment.phase == phase).toList();

  Duration durationOf(SessionPhase phase) => segmentsFor(
    phase,
  ).fold(Duration.zero, (total, segment) => total + segment.duration);

  SessionSegment? segmentAt(int index) =>
      index >= 0 && index < segments.length ? segments[index] : null;

  /// Working minutes attributed to each category, weighted by how much the
  /// exercise develops it. This is the input to the balance view — rest time is
  /// deliberately excluded so the numbers mean training load, not wall clock.
  Map<SkillCategory, Duration> get categoryBreakdown {
    final totals = <SkillCategory, double>{};
    for (final segment in segments) {
      if (!segment.isWork) continue;
      segment.exercise.categoryWeights.forEach((category, weight) {
        totals[category] =
            (totals[category] ?? 0) + segment.duration.inSeconds * weight;
      });
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return <SkillCategory, Duration>{
      for (final entry in entries)
        entry.key: Duration(seconds: entry.value.round()),
    };
  }
}
