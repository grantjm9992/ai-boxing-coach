/// National / tactical school — an axis orthogonal to the guard [Style]. Mirror
/// of `src/boxing_coach/domain/school.py`.
///
/// [Style] is the defensive *shape* (high guard, Philly shell, …). A [School] is
/// the tactical *game* a fighter plays, read off the round-level tendencies
/// ([RoundProfile]). Optional and orthogonal to Style.
enum School {
  soviet('soviet'),
  mexican('mexican'),
  european('european'),
  american('american');

  const School(this.value);

  final String value;

  static School? fromValue(String? value) {
    if (value == null) return null;
    for (final s in School.values) {
      if (s.value == value) return s;
    }
    return null;
  }
}
