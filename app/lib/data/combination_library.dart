import '../analysis/combination.dart';

/// The instructional combination library (brief §14).
///
/// Each entry is a target combination the user can pick, view and drill. The
/// canonical form is the number sequence ([numbers]); names and punch labels are
/// derived for display. `videoAsset` is null until instructional footage exists —
/// the detail screen degrades to the written sequence + coaching points.
enum CombinationDifficulty {
  beginner('Beginner'),
  intermediate('Intermediate'),
  advanced('Advanced');

  const CombinationDifficulty(this.label);
  final String label;
}

class CombinationDef {
  const CombinationDef({
    required this.id,
    required this.name,
    required this.numbers,
    required this.difficulty,
    required this.description,
    this.coachingPoints = const <String>[],
    this.videoAsset,
  });

  final String id;
  final String name;
  final List<int> numbers;
  final CombinationDifficulty difficulty;
  final String description;
  final List<String> coachingPoints;
  final String? videoAsset;

  /// "1-2-3" — the compact numeric label.
  String get numberLabel => numbers.join('-');

  /// Per-punch display names, e.g. ["Jab", "Cross", "Lead hook"].
  List<String> get punchNames =>
      numbers.map(punchNameForNumber).toList();
}

/// Display name for a punch number, using the default numbering (brief §7).
String punchNameForNumber(int number) => switch (number) {
  1 => 'Jab',
  2 => 'Cross',
  3 => 'Lead hook',
  4 => 'Rear hook',
  5 => 'Lead uppercut',
  6 => 'Rear uppercut',
  unknownPunchNumber => 'Unknown',
  _ => 'Punch $number',
};

/// The starter set (brief §14). Defensive actions (slips) are intentionally
/// excluded until they have their own event model — every entry here is punches
/// only, so detection can actually judge it.
class CombinationLibrary {
  const CombinationLibrary._();

  static const List<CombinationDef> all = <CombinationDef>[
    CombinationDef(
      id: 'combo_1_2',
      name: 'Jab → Cross',
      numbers: <int>[1, 2],
      difficulty: CombinationDifficulty.beginner,
      description:
          'The foundation. The jab sets it up, the cross lands behind it with '
          'the turn of the hips.',
      coachingPoints: <String>[
        'Snap the jab back before the cross leaves.',
        'Turn the rear hip and shoulder into the cross — power comes from the '
            'ground, not the arm.',
        'Chin down, lead hand back to guard as the cross recovers.',
      ],
    ),
    CombinationDef(
      id: 'combo_1_1_2',
      name: 'Double Jab → Cross',
      numbers: <int>[1, 1, 2],
      difficulty: CombinationDifficulty.beginner,
      description:
          'The second jab closes the distance or resets the opponent before the '
          'cross.',
      coachingPoints: <String>[
        'Keep both jabs long — don’t let the second one get lazy.',
        'Step in behind the jabs so the cross lands in range.',
      ],
    ),
    CombinationDef(
      id: 'combo_1_3',
      name: 'Jab → Lead Hook',
      numbers: <int>[1, 3],
      difficulty: CombinationDifficulty.beginner,
      description:
          'Straight then round off the same hand — the jab hides the hook that '
          'follows.',
      coachingPoints: <String>[
        'Don’t telegraph — the hook comes off the jab’s return.',
        'Pivot the lead foot as the hook turns over.',
      ],
    ),
    CombinationDef(
      id: 'combo_1_2_3',
      name: 'Jab → Cross → Lead Hook',
      numbers: <int>[1, 2, 3],
      difficulty: CombinationDifficulty.beginner,
      description:
          'The classic three-punch combination: straight, straight, then the '
          'hook to finish on the turn.',
      coachingPoints: <String>[
        'Each punch recovers to guard before the next.',
        'The hook lands as your weight comes back from the cross.',
        'Stay balanced — don’t fall in behind the hook.',
      ],
    ),
    CombinationDef(
      id: 'combo_1_3_2',
      name: 'Jab → Lead Hook → Cross',
      numbers: <int>[1, 3, 2],
      difficulty: CombinationDifficulty.intermediate,
      description:
          'Changes the angle: the hook turns them, the cross comes back down '
          'the middle.',
      coachingPoints: <String>[
        'Reset your base between the hook and the cross.',
        'Keep the rear hand home while the hook lands.',
      ],
    ),
    CombinationDef(
      id: 'combo_2_3_2',
      name: 'Cross → Lead Hook → Cross',
      numbers: <int>[2, 3, 2],
      difficulty: CombinationDifficulty.intermediate,
      description:
          'Opening on the cross — for when the jab has already done its work.',
      coachingPoints: <String>[
        'Don’t over-commit on the first cross or you’ll be off balance for the '
            'hook.',
        'The second cross is the finisher — sit down on it.',
      ],
    ),
    CombinationDef(
      id: 'combo_1_3_4',
      name: 'Jab → Lead Hook → Rear Hook',
      numbers: <int>[1, 3, 4],
      difficulty: CombinationDifficulty.intermediate,
      description:
          'Two hooks off the jab — a short-range combination that needs tight '
          'balance.',
      coachingPoints: <String>[
        'Both hooks stay short and turn over — no winding up.',
        'Guard stays high; you’re in the pocket for all three.',
      ],
    ),
    CombinationDef(
      id: 'combo_1_2_3_2',
      name: 'Jab → Cross → Lead Hook → Cross',
      numbers: <int>[1, 2, 3, 2],
      difficulty: CombinationDifficulty.intermediate,
      description:
          'The 1-2-3 with a cross on the end to bring you back to centre.',
      coachingPoints: <String>[
        'Rhythm matters — keep the four punches evenly spaced.',
        'The last cross re-centres you; recover to your stance.',
      ],
    ),
    CombinationDef(
      id: 'combo_1_2_5_2',
      name: 'Jab → Cross → Lead Uppercut → Cross',
      numbers: <int>[1, 2, 5, 2],
      difficulty: CombinationDifficulty.advanced,
      description:
          'Mixes levels: the uppercut splits the guard before the final cross.',
      coachingPoints: <String>[
        'Bend the knees for the uppercut — it comes from the legs.',
        'Don’t drop the hand to load the uppercut; keep it compact.',
      ],
    ),
  ];

  static CombinationDef? byId(String id) {
    for (final combo in all) {
      if (combo.id == id) return combo;
    }
    return null;
  }
}
