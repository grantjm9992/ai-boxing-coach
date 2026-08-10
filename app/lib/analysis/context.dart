import 'drill.dart';
import 'features.dart';
import 'landmarks.dart';
import 'pose.dart';
import 'style.dart';

/// AnalysisContext — the single object every rule receives. Mirror of
/// `src/boxing_coach/analysis/context.py`.
///
/// It carries the raw pose sequence, the drill context, and the shared derived
/// features (body scale, punches, stance speed) so each rule pulls exactly what
/// it needs and the expensive work happens once, not per rule. The derived
/// features are computed lazily and cached, matching Python's `cached_property`.
class AnalysisContext {
  AnalysisContext({
    required this.sequence,
    required this.drill,
    PunchDetectorConfig? punchConfig,
    this.styleProfile = defaultStyleProfile,
  }) : punchConfig = punchConfig ?? const PunchDetectorConfig();

  final PoseSequence sequence;
  final DrillContext drill;
  final PunchDetectorConfig punchConfig;

  /// Tunes/gates the rules for this round's style. Defaults to the neutral
  /// high-guard profile so callers that don't care are unaffected.
  final StyleProfile styleProfile;

  double? _bodyScale;
  List<PunchEvent>? _punches;
  List<double>? _stanceSpeed;

  double get bodyScale => _bodyScale ??= computeBodyScale(sequence);

  List<PunchEvent> get punches =>
      _punches ??= PunchDetector(config: punchConfig).detect(sequence, bodyScale);

  /// Per-frame stance-centre speed (torso-lengths/sec); the in/out signal,
  /// index-aligned to `sequence.frames`.
  List<double> get stanceSpeed =>
      _stanceSpeed ??= stanceSpeedSeries(sequence, bodyScale);

  List<PunchEvent> punchesBy(Side side) =>
      punches.where((p) => p.side == side).toList();
}
