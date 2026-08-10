import '../data/exercise_library.dart';
import '../domain/session_plan.dart';
import '../domain/session_settings.dart';
import '../domain/session_template.dart';

/// Expands a template plus a user configuration into the flat segment list the
/// timer runs.
///
/// Two structures collapse into one list here:
///
/// * continuous phases (warm-up, cool-down) share the phase's total time out
///   between their items in proportion to each item's natural length, so
///   stretching a warm-up from five minutes to ten stretches every step of it
///   rather than bolting extra time onto the end;
/// * round-based phases repeat work/rest pairs, cycling through the template's
///   items if the user asks for more rounds than the template names.
class SessionPlanBuilder {
  const SessionPlanBuilder._();

  /// Segments shorter than this are not worth announcing.
  static const int minimumSegmentSeconds = 20;

  static SessionPlan build(SessionTemplate template, SessionSettings settings) {
    final segments = <SessionSegment>[];
    var offset = Duration.zero;

    for (final templatePhase in template.phases) {
      final phaseSettings = settings.forPhase(templatePhase.phase);
      if (phaseSettings == null || !phaseSettings.enabled) continue;
      if (templatePhase.items.isEmpty) continue;

      final phaseSegments = templatePhase.phase.isRoundBased
          ? _buildRounds(templatePhase, phaseSettings, segments.length, offset)
          : _buildContinuous(
              templatePhase,
              phaseSettings,
              segments.length,
              offset,
            );

      for (final segment in phaseSegments) {
        offset += segment.duration;
      }
      segments.addAll(phaseSegments);
    }

    return SessionPlan(
      template: template,
      settings: settings,
      segments: segments,
    );
  }

  static List<SessionSegment> _buildContinuous(
    TemplatePhase templatePhase,
    PhaseSettings settings,
    int startIndex,
    Duration startOffset,
  ) {
    final durations = _shareOut(
      total: settings.totalSeconds,
      weights: <int>[
        for (final item in templatePhase.items)
          ExerciseLibrary.byKey(item.exerciseKey).defaultDurationSeconds,
      ],
    );

    final segments = <SessionSegment>[];
    var offset = startOffset;
    for (var i = 0; i < templatePhase.items.length; i++) {
      if (durations[i] <= 0) continue;
      final item = templatePhase.items[i];
      final segment = SessionSegment(
        index: startIndex + segments.length,
        phase: templatePhase.phase,
        kind: SegmentKind.work,
        duration: Duration(seconds: durations[i]),
        exercise: ExerciseLibrary.byKey(item.exerciseKey),
        startOffset: offset,
        theme: item.theme,
        note: item.note,
        isFirstOfPhase: segments.isEmpty,
        isLastOfPhase: false,
      );
      segments.add(segment);
      offset += segment.duration;
    }
    return _markLastOfPhase(segments);
  }

  static List<SessionSegment> _buildRounds(
    TemplatePhase templatePhase,
    PhaseSettings settings,
    int startIndex,
    Duration startOffset,
  ) {
    final segments = <SessionSegment>[];
    var offset = startOffset;

    for (var round = 0; round < settings.rounds; round++) {
      final item = templatePhase.items[round % templatePhase.items.length];
      final exercise = ExerciseLibrary.byKey(item.exerciseKey);

      final work = SessionSegment(
        index: startIndex + segments.length,
        phase: templatePhase.phase,
        kind: SegmentKind.work,
        duration: Duration(seconds: settings.workSeconds),
        exercise: exercise,
        startOffset: offset,
        theme: item.theme,
        note: item.note,
        roundNumber: round + 1,
        roundsInPhase: settings.rounds,
        isFirstOfPhase: round == 0,
        isLastOfPhase: false,
      );
      segments.add(work);
      offset += work.duration;

      if (settings.restSeconds <= 0) continue;
      final rest = SessionSegment(
        index: startIndex + segments.length,
        phase: templatePhase.phase,
        kind: SegmentKind.rest,
        duration: Duration(seconds: settings.restSeconds),
        exercise: exercise,
        startOffset: offset,
        roundNumber: round + 1,
        roundsInPhase: settings.rounds,
        isFirstOfPhase: false,
        isLastOfPhase: false,
      );
      segments.add(rest);
      offset += rest.duration;
    }

    return _markLastOfPhase(segments);
  }

  static List<SessionSegment> _markLastOfPhase(List<SessionSegment> segments) {
    if (segments.isEmpty) return segments;
    final last = segments.last;
    segments[segments.length - 1] = SessionSegment(
      index: last.index,
      phase: last.phase,
      kind: last.kind,
      duration: last.duration,
      exercise: last.exercise,
      startOffset: last.startOffset,
      theme: last.theme,
      note: last.note,
      roundNumber: last.roundNumber,
      roundsInPhase: last.roundsInPhase,
      isFirstOfPhase: last.isFirstOfPhase,
      isLastOfPhase: true,
    );
    return segments;
  }

  /// Splits [total] seconds across [weights], keeping the sum exact and never
  /// producing a segment too short to be worth announcing.
  ///
  /// Items are dropped from the end until the survivors all clear the minimum,
  /// which is what a coach does when the clock is short: the last few steps go,
  /// the first ones keep enough time to be useful.
  static List<int> _shareOut({required int total, required List<int> weights}) {
    var count = weights.length;
    while (count > 1 && total ~/ count < minimumSegmentSeconds) {
      count--;
    }

    final kept = weights.take(count).toList();
    final weightSum = kept.fold<int>(0, (sum, weight) => sum + weight);
    final result = List<int>.filled(weights.length, 0);
    if (weightSum <= 0 || total <= 0) return result;

    var allocated = 0;
    for (var i = 0; i < count; i++) {
      final share = (total * kept[i] / weightSum).round();
      result[i] = share;
      allocated += share;
    }
    // Push any rounding drift onto the longest segment so the phase lasts
    // exactly as long as configured.
    var longest = 0;
    for (var i = 1; i < count; i++) {
      if (result[i] > result[longest]) longest = i;
    }
    result[longest] += total - allocated;
    return result;
  }
}
