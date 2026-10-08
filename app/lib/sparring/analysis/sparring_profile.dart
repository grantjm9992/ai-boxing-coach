import '../../analysis/drill.dart';
import '../../analysis/landmarks.dart';
import '../../analysis/pose.dart';
import '../../analysis/rule.dart';
import '../../analysis/rules/balance.dart';
import '../../analysis/rules/guard_return.dart';
import '../../analysis/rules/hands_up.dart';
import '../../analysis/rules/hip_rotation.dart';
import '../../analysis/school.dart';
import '../../analysis/style.dart';
import '../../analysis/style_profiles.dart';

/// Which of the existing rules sparring runs, and how — sparring is filmed
/// side-on, so only rules whose geometry holds in profile run. The rules
/// themselves are used as they are; sparring only picks instances and configs.
///
/// Off in sparring (front-on geometry, not yet re-validated side-on):
/// `head_movement` (lateral nose spread — a slip side-on is mostly depth),
/// `footwork` (stance width / feet crossing read left-right), `body_lean`
/// (lateral lean), and `school_adherence`.
const Set<String> kSparringRuleIds = <String>{
  'guard_return',
  'hands_up',
  'hip_rotation',
  'balance',
};

const Set<String> _offInSparring = <String>{
  'head_movement',
  'footwork',
  'body_lean',
  'school_adherence',
};

/// Fresh instances of the side-view-valid rules.
List<Rule> sparringRules() => <Rule>[
  GuardReturnRule(),
  HandsUpRule(),
  HipRotationRule(),
  BalanceRule(),
];

/// The [StyleProfile] one fighter's track is analysed with: their style and
/// school's tuning, the front-on rules switched off, and hands-up excused
/// while moving (sparring is constant movement; a hand dropping mid-step isn't
/// the habit the rule is for).
StyleProfile sparringProfile({Style style = Style.highGuard, School? school}) {
  final base = resolveProfile(style, school);
  final configs = Map<String, Object>.of(base.ruleConfigs);
  final hands = (configs['hands_up'] as HandsUpConfig?) ?? const HandsUpConfig();
  configs['hands_up'] = hands.copyWith(excuseWhileMoving: true);
  return StyleProfile(
    style: base.style,
    label: '${base.label} (sparring)',
    summary: '${base.summary} Filmed side-on in sparring: only rules valid in '
        'profile run.',
    disabledRules: <String>{...base.disabledRules, ..._offInSparring},
    ruleConfigs: configs,
  );
}

/// Infers a fighter's stance from the side-on footage: the lead foot is the
/// one nearer the opponent. Null when there isn't enough clear evidence.
Stance? inferStance(PoseSequence self, PoseSequence opponent, {int minVotes = 15}) {
  var orthodox = 0, southpaw = 0;
  final n = self.frames.length < opponent.frames.length
      ? self.frames.length
      : opponent.frames.length;
  for (var i = 0; i < n; i++) {
    final me = self.frames[i];
    final them = opponent.frames[i];
    final myHip = _mid(me, Landmark.leftHip, Landmark.rightHip);
    final theirHip = _mid(them, Landmark.leftHip, Landmark.rightHip);
    final myShoulders = _mid(me, Landmark.leftShoulder, Landmark.rightShoulder);
    final left = me.get(Landmark.leftAnkle);
    final right = me.get(Landmark.rightAnkle);
    if (myHip == null || theirHip == null || myShoulders == null) continue;
    if (left == null || right == null) continue;
    if (left.visibility < 0.5 || right.visibility < 0.5) continue;
    final torso = (myShoulders[1] - myHip[1]).abs();
    if (torso <= 0) continue;
    final towards = theirHip[0] >= myHip[0] ? 1.0 : -1.0;
    final split = (left.x - right.x) * towards;
    if (split.abs() < 0.15 * torso) continue; // feet level: no evidence
    if (split > 0) {
      orthodox++; // left foot nearer the opponent
    } else {
      southpaw++;
    }
  }
  if (orthodox + southpaw < minVotes) return null;
  return orthodox >= southpaw ? Stance.orthodox : Stance.southpaw;
}

List<double>? _mid(PoseFrame frame, Landmark a, Landmark b) {
  final ka = frame.get(a);
  final kb = frame.get(b);
  if (ka == null || kb == null) return null;
  return <double>[(ka.x + kb.x) / 2, (ka.y + kb.y) / 2];
}
