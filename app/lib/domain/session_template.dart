import 'session_phase.dart';
import 'skill_category.dart';

/// One item inside a phase.
///
/// For round-based phases it is a round: an exercise plus the theme announced
/// at the top of the round. For continuous phases it is a step in the sequence.
class PhaseItem {
  const PhaseItem(this.exerciseKey, {this.theme, this.note});

  /// References [Exercise.key] in the library.
  final String exerciseKey;

  /// Announced with the round — "footwork focus", "power combinations".
  final String? theme;

  /// Extra drill setup detail for this specific use of the exercise.
  final String? note;
}

/// A phase as a template defines it: the intent, the default configuration and
/// the ordered items.
class TemplatePhase {
  const TemplatePhase({
    required this.phase,
    required this.items,
    this.intent,
    this.defaultRounds = 0,
    this.defaultWorkSeconds = 0,
    this.defaultRestSeconds = 0,
    this.defaultTotalSeconds = 0,
  });

  final SessionPhase phase;

  /// Template-specific intent. Falls back to the phase's own intent.
  final String? intent;

  /// Ordered items. For round-based phases the list is cycled if the user
  /// configures more rounds than the template names.
  final List<PhaseItem> items;

  final int defaultRounds;
  final int defaultWorkSeconds;
  final int defaultRestSeconds;

  /// Continuous phases only.
  final int defaultTotalSeconds;

  String get intentText => intent ?? phase.intent;
}

/// A pre-built session the user picks from.
///
/// The spec's open question 5 recommends templates for the MVP, so v0.1 ships
/// templates only — no custom builder, no generation.
class SessionTemplate {
  const SessionTemplate({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.focus,
    required this.phases,
    required this.difficulty,
  });

  final String id;
  final String name;

  /// One line for the template card.
  final String tagline;

  /// What this session is for and who it suits.
  final String description;

  /// The categories this session emphasises, most first.
  final List<SkillCategory> focus;

  /// 1 (accessible) .. 5 (demanding).
  final int difficulty;

  /// In arc order: warm-up → conditioning → shadow → technical → cool-down.
  final List<TemplatePhase> phases;

  TemplatePhase? phaseFor(SessionPhase phase) {
    for (final templatePhase in phases) {
      if (templatePhase.phase == phase) return templatePhase;
    }
    return null;
  }
}
