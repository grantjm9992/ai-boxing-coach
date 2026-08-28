import 'dart:math' as math;

import 'combination.dart';
import 'error_codes.dart';
import 'features.dart';
import 'geometry.dart' as geo;
import 'landmarks.dart';
import 'pose.dart';
import 'round_analysis.dart';

/// Combination-execution analysis (brief §10): turning "the punches were thrown"
/// into "here is how well the combination was executed".
///
/// Reuses the same frontal-honest signals as the round analyzers, scoped to one
/// combination's window: did the hand recover between punches, did the guard
/// hand stay up during each shot, and did the boxer keep their base at the end.
/// Depth-dependent judgements (weight transfer, forward lean) are deliberately
/// left out — same reliability rule as the Phase 2 rules (brief §12, §35).

/// A single execution fault within a combination.
class CombinationIssue {
  const CombinationIssue({
    required this.code,
    required this.severity,
    required this.confidence,
    this.timestampMs,
  });

  final String code;
  final Severity severity;
  final double confidence;
  final double? timestampMs;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'severity': severity.value,
    'confidence': confidence,
    'timestampMs': timestampMs,
  };

  factory CombinationIssue.fromJson(Map<String, Object?> json) =>
      CombinationIssue(
        code: json['code'] as String,
        severity: Severity.fromValue(json['severity'] as String),
        confidence: (json['confidence'] as num?)?.toDouble() ?? 1.0,
        timestampMs: (json['timestampMs'] as num?)?.toDouble(),
      );
}

/// The execution verdict for one combination: its detection [combination], a
/// 0–100 [score], the [issues] found, and the raw [metrics] behind them.
class CombinationAnalysis {
  const CombinationAnalysis({
    required this.combination,
    required this.score,
    this.issues = const <CombinationIssue>[],
    this.metrics = const <String, double>{},
  });

  final Combination combination;
  final int score;
  final List<CombinationIssue> issues;
  final Map<String, double> metrics;

  Map<String, Object?> toJson() => <String, Object?>{
    'combination': combination.toJson(),
    'score': score,
    'issues': issues.map((i) => i.toJson()).toList(),
    'metrics': metrics,
  };

  factory CombinationAnalysis.fromJson(Map<String, Object?> json) =>
      CombinationAnalysis(
        combination: Combination.fromJson(
          (json['combination'] as Map).cast<String, Object?>(),
        ),
        score: (json['score'] as num).toInt(),
        issues: <CombinationIssue>[
          for (final i in (json['issues'] as List<Object?>? ?? const []))
            CombinationIssue.fromJson((i as Map).cast<String, Object?>()),
        ],
        metrics: <String, double>{
          for (final e
              in (json['metrics'] as Map<String, Object?>? ?? const {}).entries)
            e.key: (e.value as num).toDouble(),
        },
      );
}

class CombinationExecutionConfig {
  const CombinationExecutionConfig({
    this.recoveredReach = 0.6,
    this.guardDropBelow = 0.35,
    this.endBalanceMaxOffset = 0.55,
    this.recoveryMarginFrames = 6,
    this.recoveryConfidence = 0.75,
    this.guardConfidence = 0.7,
    this.balanceConfidence = 0.7,
  });

  /// Reach (torso-lengths) below which a punching hand counts as recovered to
  /// guard. Above this at the next punch's start = it didn't come back.
  final double recoveredReach;

  /// How far below the shoulder (torso-lengths) the guard hand's wrist may sit
  /// before it counts as dropped.
  final double guardDropBelow;

  /// Hip-over-base offset (torso-lengths) tolerated at the end of the combo.
  final double endBalanceMaxOffset;

  final int recoveryMarginFrames;
  final double recoveryConfidence;
  final double guardConfidence;
  final double balanceConfidence;
}

/// Penalty applied to the 0–100 score per issue severity.
int _penalty(Severity s) => switch (s) {
  Severity.major => 25,
  Severity.moderate => 15,
  Severity.minor => 8,
  Severity.positive => 0,
};

/// Analyses one [combo]'s execution. [punches] is the full round punch list;
/// [combo.punchIndices] selects this combination's punches from it.
CombinationAnalysis analyzeCombination(
  PoseSequence sequence,
  List<PunchEvent> punches,
  Combination combo,
  Stance stance,
  double bodyScale, {
  CombinationExecutionConfig config = const CombinationExecutionConfig(),
}) {
  final comboPunches = <PunchEvent>[
    for (final i in combo.punchIndices)
      if (i >= 0 && i < punches.length) punches[i],
  ];
  final issues = <CombinationIssue>[];
  final metrics = <String, double>{};

  double reachAt(int frameIndex, Side side) {
    final frame = sequence.frames[frameIndex];
    final wrist = geo.framePoint(frame, side.wrist);
    final shoulder = geo.framePoint(frame, side.shoulder);
    if (wrist.any((v) => v.isNaN) || shoulder.any((v) => v.isNaN)) {
      return double.nan;
    }
    return geo.distance(wrist, shoulder) / bodyScale;
  }

  // (A) Recovery between punches: the earlier punch's hand should be back near
  // guard by the time the next punch starts.
  for (var k = 0; k + 1 < comboPunches.length; k++) {
    final a = comboPunches[k];
    final b = comboPunches[k + 1];
    final reach = reachAt(b.startIndex, a.side);
    if (!reach.isNaN && reach > config.recoveredReach) {
      issues.add(CombinationIssue(
        code: FaultCode.recHandNotReturned,
        severity: Severity.moderate,
        confidence: config.recoveryConfidence,
        timestampMs: sequence.frames[b.startIndex].timestampMs,
      ));
    }
  }

  // (B) Guard hand during each punch: the non-punching hand should stay up.
  for (final p in comboPunches) {
    final other = p.side == Side.left ? Side.right : Side.left;
    final frame = sequence.frames[p.peakIndex];
    final wrist = geo.framePoint(frame, other.wrist);
    final shoulder = geo.framePoint(frame, other.shoulder);
    if (wrist.any((v) => v.isNaN) || shoulder.any((v) => v.isNaN)) continue;
    final drop = (wrist[1] - shoulder[1]) / bodyScale; // +ve = below shoulder
    if (drop > config.guardDropBelow) {
      // If the rear hand is punching, it's the lead guard that dropped.
      final punchIsRear = p.side == stance.rear;
      issues.add(CombinationIssue(
        code: punchIsRear
            ? FaultCode.guardLeadDropsDuringRear
            : FaultCode.guardRearDropsDuringLead,
        severity: Severity.moderate,
        confidence: config.guardConfidence,
        timestampMs: frame.timestampMs,
      ));
    }
  }

  // (C) Balance at the end of the combination: hips back over the base.
  if (comboPunches.isNotEmpty) {
    final last = comboPunches.last;
    final to = (last.endIndex + config.recoveryMarginFrames)
        .clamp(0, sequence.frames.length - 1);
    double worst = 0;
    double? worstMs;
    for (var i = last.peakIndex; i <= to; i++) {
      final frame = sequence.frames[i];
      final hips = geo.hipCenter(frame);
      final ankles = geo.ankleCenter(frame);
      if (hips.any((v) => v.isNaN) || ankles.any((v) => v.isNaN)) continue;
      final offset = (hips[0] - ankles[0]).abs() / bodyScale;
      if (offset > worst) {
        worst = offset;
        worstMs = frame.timestampMs;
      }
    }
    metrics['worst_end_hip_offset'] = worst;
    if (worst > config.endBalanceMaxOffset) {
      issues.add(CombinationIssue(
        code: FaultCode.balOffAfterCombination,
        severity: Severity.moderate,
        confidence: config.balanceConfidence,
        timestampMs: worstMs,
      ));
    }
  }

  // (D) Rhythm: coefficient of variation of the peak-to-peak intervals. A
  // descriptive metric, not a fault — uneven rhythm is context, not a defect.
  if (comboPunches.length >= 3) {
    final intervals = <double>[
      for (var k = 1; k < comboPunches.length; k++)
        sequence.frames[comboPunches[k].peakIndex].timestampMs -
            sequence.frames[comboPunches[k - 1].peakIndex].timestampMs,
    ];
    final mean =
        intervals.fold<double>(0, (a, b) => a + b) / intervals.length;
    if (mean > 0) {
      final variance = intervals
              .map((x) => (x - mean) * (x - mean))
              .fold<double>(0, (a, b) => a + b) /
          intervals.length;
      metrics['rhythm_cv'] = variance <= 0 ? 0 : math.sqrt(variance) / mean;
    }
  }

  var score = 100;
  for (final issue in issues) {
    score -= _penalty(issue.severity);
  }
  score = score.clamp(0, 100);

  return CombinationAnalysis(
    combination: combo,
    score: score,
    issues: issues,
    metrics: metrics,
  );
}
