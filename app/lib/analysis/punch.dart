import 'landmarks.dart';

/// Punch type — the motion class of a detected punch. Mirror of
/// `src/boxing_coach/domain/punch.py`.
///
/// Deliberately the *motion* class (straight / hook / uppercut), not the named
/// punch: whether a straight is a "jab" or a "cross" depends on which hand threw
/// it relative to the stance, so [punchName] is a separate step.
enum PunchType {
  straight('straight'),
  hook('hook'),
  uppercut('uppercut'),
  unknown('unknown');

  const PunchType(this.value);

  /// The wire value, matching the Python `PunchType` enum values.
  final String value;
}

/// The common name for a punch, e.g. 'jab', 'cross', 'lead hook'.
String punchName(PunchType type, Side side, Stance stance) {
  final lead = side == stance.lead;
  if (type == PunchType.straight) return lead ? 'jab' : 'cross';
  final hand = lead ? 'lead' : 'rear';
  if (type == PunchType.hook) return '$hand hook';
  if (type == PunchType.uppercut) return '$hand uppercut';
  return 'punch';
}
