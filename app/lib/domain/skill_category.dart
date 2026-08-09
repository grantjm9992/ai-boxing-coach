/// The skill areas every exercise, drill and round is tagged with.
///
/// Taken from the "Category tracking" section of `boxing-coach-spec.md`.
/// `mobility` is an addition: the spec's list covers the boxing work but leaves
/// warm-up and cool-down exercises untaggable, and an untagged exercise breaks
/// the category-based tracking principle.
///
/// The keys deliberately match `SkillCategory` in the Python analysis engine
/// (`src/boxing_coach/domain/analysis.py`) so that from v0.5, an observation
/// coming out of the rule engine maps onto a tracked category without a
/// translation table in between.
enum SkillCategory {
  cardio('cardiovascular_endurance', 'Cardio', 'Cardiovascular endurance'),
  muscularEndurance(
    'muscular_endurance',
    'Muscular endurance',
    'Sustained output under fatigue',
  ),
  power('power', 'Power', 'Explosive force generation'),
  footwork('footwork', 'Footwork', 'Movement, angles, ring cutting'),
  defence('defence', 'Defence', 'Slipping, rolling, blocking, parrying'),
  jab('offence_jab', 'Jab', 'Offence — the jab'),
  straight(
    'offence_straight',
    'Straight',
    'Offence — cross and straight shots',
  ),
  hooks('offence_hooks', 'Hooks', 'Offence — lead and rear hooks'),
  uppercuts('offence_uppercuts', 'Uppercuts', 'Offence — uppercuts'),
  combinations('combinations', 'Combinations', 'Multi-punch sequences'),
  headMovement('head_movement', 'Head movement', 'Getting off the centre line'),
  distanceManagement(
    'distance_management',
    'Distance',
    'In-out, cutting angles, controlling range',
  ),
  rhythmTiming('rhythm_timing', 'Rhythm & timing', 'Broken tempo, feints'),
  mobility('mobility', 'Mobility', 'Joint mobility, activation, recovery');

  const SkillCategory(this.key, this.label, this.description);

  /// Stable identifier — matches `skill_categories.key` in the spec's schema.
  final String key;

  /// Short label for chips and dashboards.
  final String label;

  /// One-line explanation shown in the exercise library.
  final String description;

  static SkillCategory? fromKey(String key) {
    for (final category in SkillCategory.values) {
      if (category.key == key) return category;
    }
    return null;
  }
}
