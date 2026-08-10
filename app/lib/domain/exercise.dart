import 'session_phase.dart';
import 'skill_category.dart';

/// A single exercise or drill from the library.
///
/// Mirrors `exercises_catalog` + `exercise_category_map` in the spec's schema.
/// The category weights are what make category-based progress tracking work:
/// a round of skipping is mostly cardio, a round of slip-rope is defence and
/// head movement in roughly equal measure.
class Exercise {
  const Exercise({
    required this.key,
    required this.label,
    required this.description,
    required this.phase,
    required this.defaultDurationSeconds,
    required this.categoryWeights,
    required this.difficulty,
    this.requiresEquipment = false,
    this.equipmentNotes,
    this.cues = const <String>[],
    this.setupCue,
  });

  /// Stable identifier used by templates to reference this exercise.
  final String key;
  final String label;
  final String description;

  /// The phase this exercise belongs to.
  final SessionPhase phase;

  /// Duration when the exercise is used at its natural length. For continuous
  /// phases this also acts as the weight used to share out the phase's time.
  final int defaultDurationSeconds;

  /// How much this exercise develops each category, 0..1.
  final Map<SkillCategory, double> categoryWeights;

  /// 1 (accessible) .. 5 (demanding).
  final int difficulty;

  final bool requiresEquipment;
  final String? equipmentNotes;

  /// Technique reminders the coach drops mid-round. Kept short — these are
  /// spoken over a working athlete.
  final List<String> cues;

  /// One line describing how to set the drill up, spoken before it starts.
  final String? setupCue;

  List<SkillCategory> get categories {
    final sorted = categoryWeights.keys.toList()
      ..sort((a, b) => categoryWeights[b]!.compareTo(categoryWeights[a]!));
    return sorted;
  }

  SkillCategory get primaryCategory => categories.first;
}
