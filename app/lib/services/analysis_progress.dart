import '../analysis/analysis_mode.dart';

/// The stages a round's analysis goes through, in order. Which of them a round
/// passes through depends on its [AnalysisMode] — see [stagesFor].
enum AnalysisStage {
  tracking('Tracking your movement'),
  uploading('Uploading the round'),
  reviewing('AI coach reviewing'),
  saving('Saving your feedback');

  const AnalysisStage(this.label);

  /// Short, user-facing name of the stage.
  final String label;

  /// The stages a round analysed in [mode] goes through, in order.
  static List<AnalysisStage> stagesFor(AnalysisMode mode) => switch (mode) {
    AnalysisMode.offline => const <AnalysisStage>[tracking, saving],
    AnalysisMode.keyframe => const <AnalysisStage>[tracking, reviewing, saving],
    AnalysisMode.fullFrame =>
      const <AnalysisStage>[tracking, uploading, reviewing, saving],
  };
}

/// Reports a stage change or progress within a stage. [fraction] is 0..1 when
/// the stage can measure itself (tracking, uploading) and null when it can't
/// (the model reviewing, saving).
typedef AnalysisProgressCallback = void Function(
  AnalysisStage stage,
  double? fraction,
);

/// A snapshot of one running analysis, for the progress UI.
class AnalysisProgress {
  const AnalysisProgress({
    required this.mode,
    required this.stage,
    required this.startedAt,
    required this.stageStartedAt,
    this.fraction,
  });

  /// A fresh analysis in [mode], starting at [stage] — tracking for a new
  /// round; a later stage when the earlier ones already ran (a drill's AI
  /// review reuses the pose it tracked on the spot).
  factory AnalysisProgress.start(
    AnalysisMode mode, {
    AnalysisStage stage = AnalysisStage.tracking,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    return AnalysisProgress(
      mode: mode,
      stage: stage,
      startedAt: at,
      stageStartedAt: at,
      fraction: stage == AnalysisStage.uploading ||
              stage == AnalysisStage.tracking
          ? 0
          : null,
    );
  }

  final AnalysisMode mode;
  final AnalysisStage stage;
  final double? fraction;
  final DateTime startedAt;
  final DateTime stageStartedAt;

  /// The stages this analysis goes through, in order.
  List<AnalysisStage> get stages => AnalysisStage.stagesFor(mode);

  /// This snapshot moved on to [next] (same stage: just a new fraction).
  AnalysisProgress advance(AnalysisStage next, double? fraction, {DateTime? now}) =>
      AnalysisProgress(
        mode: mode,
        stage: next,
        fraction: fraction,
        startedAt: startedAt,
        stageStartedAt: next == stage ? stageStartedAt : (now ?? DateTime.now()),
      );

  /// Rough time left in the current stage, extrapolated from its own pace.
  /// Null until there's enough progress to extrapolate from, or when the stage
  /// can't measure itself.
  Duration? stageRemaining({DateTime? now}) {
    final f = fraction;
    if (f == null || f < 0.05 || f >= 1) return null;
    final elapsed = (now ?? DateTime.now()).difference(stageStartedAt);
    final total = elapsed.inMilliseconds / f;
    return Duration(milliseconds: (total - elapsed.inMilliseconds).round());
  }
}
