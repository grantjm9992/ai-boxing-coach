import 'package:boxing_coach/analysis/combination.dart';
import 'package:boxing_coach/analysis/features.dart';
import 'package:boxing_coach/analysis/landmarks.dart';
import 'package:boxing_coach/analysis/pose.dart';
import 'package:boxing_coach/analysis/punch.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 3 (brief §9, §34): grouping classified punches into numbered
/// combinations, and telling 1-2-3 from 1-3-4 from an unknown sequence.
///
/// Punch events are constructed directly with explicit types + indices so the
/// grouping logic is tested independently of the detector/classifier. Frames
/// carry only timestamps (index * 100ms), which is all detection reads.
void main() {
  // Orthodox: lead hand is the left.
  const stance = Stance.orthodox;

  test('1-2-3: jab, cross, lead hook', () {
    final combos = detectCombinations(
      _frames(9),
      <PunchEvent>[
        _punch(PunchType.straight, Side.left, 0), // jab
        _punch(PunchType.straight, Side.right, 3), // cross
        _punch(PunchType.hook, Side.left, 6), // lead hook
      ],
      stance,
    );
    expect(combos, hasLength(1));
    expect(combos.single.sequence, <int>[1, 2, 3]);
    expect(combos.single.label, '1-2-3');
    expect(combos.single.confidence, 1.0);
  });

  test('1-3-4: jab, lead hook, rear hook — distinct from 1-2-3', () {
    final combos = detectCombinations(
      _frames(9),
      <PunchEvent>[
        _punch(PunchType.straight, Side.left, 0),
        _punch(PunchType.hook, Side.left, 3),
        _punch(PunchType.hook, Side.right, 6),
      ],
      stance,
    );
    expect(combos.single.sequence, <int>[1, 3, 4]);
    expect(combos.single.label, '1-3-4');
  });

  test('an unclassified punch becomes 0 and lowers confidence', () {
    final combos = detectCombinations(
      _frames(9),
      <PunchEvent>[
        _punch(PunchType.straight, Side.left, 0),
        _punch(PunchType.unknown, Side.right, 3),
        _punch(PunchType.straight, Side.left, 6),
      ],
      stance,
    );
    expect(combos.single.sequence, <int>[1, unknownPunchNumber, 1]);
    expect(combos.single.label, '1-?-1');
    expect(combos.single.confidence, closeTo(2 / 3, 1e-9));
  });

  test('southpaw flips lead/rear numbering', () {
    // Same motions as 1-2-3 but southpaw: lead is the right hand.
    final combos = detectCombinations(
      _frames(9),
      <PunchEvent>[
        _punch(PunchType.straight, Side.right, 0), // lead straight = jab
        _punch(PunchType.straight, Side.left, 3), // rear straight = cross
        _punch(PunchType.hook, Side.right, 6), // lead hook
      ],
      Stance.southpaw,
    );
    expect(combos.single.sequence, <int>[1, 2, 3]);
  });

  test('a gap over the threshold splits into two combinations', () {
    final combos = detectCombinations(
      _frames(26),
      <PunchEvent>[
        _punch(PunchType.straight, Side.left, 0), // ends at 200ms
        _punch(PunchType.straight, Side.right, 3), // starts 300ms — same combo
        _punch(PunchType.straight, Side.left, 20), // starts 2000ms — new combo
        _punch(PunchType.straight, Side.right, 23),
      ],
      stance,
    );
    expect(combos, hasLength(2));
    expect(combos[0].sequence, <int>[1, 2]);
    expect(combos[1].sequence, <int>[1, 2]);
  });

  test('isolated single punches are not combinations', () {
    expect(
      detectCombinations(_frames(3), <PunchEvent>[
        _punch(PunchType.straight, Side.left, 0),
      ], stance),
      isEmpty,
    );
    // Two punches too far apart are two singles, not a combo.
    expect(
      detectCombinations(_frames(26), <PunchEvent>[
        _punch(PunchType.straight, Side.left, 0),
        _punch(PunchType.straight, Side.right, 20),
      ], stance),
      isEmpty,
    );
  });

  test('a wider max gap groups punches that would otherwise split', () {
    final punches = <PunchEvent>[
      _punch(PunchType.straight, Side.left, 0),
      _punch(PunchType.straight, Side.right, 20), // 1800ms gap
    ];
    expect(detectCombinations(_frames(26), punches, stance), isEmpty);
    expect(
      detectCombinations(_frames(26), punches, stance, maxGapMs: 2000),
      hasLength(1),
    );
  });

  test('round-trips through JSON', () {
    final combo = detectCombinations(_frames(9), <PunchEvent>[
      _punch(PunchType.straight, Side.left, 0),
      _punch(PunchType.hook, Side.left, 3),
    ], stance).single;
    final back = Combination.fromJson(combo.toJson());
    expect(back.sequence, combo.sequence);
    expect(back.types, combo.types);
    expect(back.confidence, combo.confidence);
    expect(back.punchIndices, combo.punchIndices);
  });
}

PoseSequence _frames(int n, {double stepMs = 100}) => PoseSequence(
  frames: <PoseFrame>[
    for (var i = 0; i <= n; i++)
      PoseFrame(
        index: i,
        timestampMs: i * stepMs,
        keypoints: const <Landmark, Keypoint>{},
      ),
  ],
  fps: 1000 / stepMs,
);

PunchEvent _punch(PunchType type, Side side, int start) => PunchEvent(
  side: side,
  startIndex: start,
  peakIndex: start + 1,
  endIndex: start + 2,
  peakReach: 1.0,
  punchType: type,
);
