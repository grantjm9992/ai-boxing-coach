import 'drill.dart';
import 'rules/footwork.dart';
import 'rules/guard_return.dart';
import 'rules/hands_up.dart';
import 'rules/head_movement.dart';
import 'school.dart';
import 'style.dart';

/// The built-in StyleProfiles — how each fighting [Style] tunes the rules.
/// Mirror of `src/boxing_coach/analysis/style_profiles.py`. Starting points to
/// calibrate, not gospel.

const Map<Style, StyleProfile> _profiles = <Style, StyleProfile>{
  Style.highGuard: defaultStyleProfile,
  Style.phillyShell: StyleProfile(
    style: Style.phillyShell,
    label: 'Philly shell',
    summary: 'Lead hand low across the body, rear hand high, chin tucked behind '
        'the lead shoulder. The lead hand is meant to be low, so the guard '
        'checks apply to the rear hand only.',
    ruleConfigs: <String, Object>{
      'hands_up': HandsUpConfig(checkLead: false),
      'guard_return': GuardReturnConfig(checkLead: false),
    },
  ),
  Style.peekABoo: StyleProfile(
    style: Style.peekABoo,
    label: 'Peek-a-boo',
    summary: 'Hands high by the cheeks with constant head movement. Demands more '
        "head movement than the default before it's satisfied.",
    ruleConfigs: <String, Object>{
      'head_movement': HeadMovementConfig(minLateralStd: 0.15),
    },
  ),
  Style.outBoxer: StyleProfile(
    style: Style.outBoxer,
    label: 'Out-boxer',
    summary: 'Defends with range and footwork rather than head movement. The '
        'head-movement rule is off; footwork is held to a higher bar.',
    disabledRules: <String>{'head_movement'},
    ruleConfigs: <String, Object>{
      'footwork': FootworkConfig(minTravelPerSecond: 0.30),
    },
  ),
};

StyleProfile profileForStyle(Style style) =>
    _profiles[style] ?? defaultStyleProfile;

/// The StyleProfile for [style], with any [school] guard-rule tuning layered on.
/// Style sets the base rule configs; a School (Soviet, …) adjusts the guard
/// rules whose notion of "correct" its game changes, field-wise.
StyleProfile resolveProfile(Style style, [School? school]) {
  final profile = profileForStyle(style);
  // Only the Soviet school changes guard-rule expectations (in-and-out range
  // game); every other school leaves the guard rules as the Style set them.
  if (school != School.soviet) return profile;

  final configs = Map<String, Object>.of(profile.ruleConfigs);
  final handsBase =
      (configs['hands_up'] as HandsUpConfig?) ?? const HandsUpConfig();
  configs['hands_up'] = handsBase.copyWith(
    relativeToBaseline: true,
    excuseWhileMoving: true,
  );
  final guardBase =
      (configs['guard_return'] as GuardReturnConfig?) ?? const GuardReturnConfig();
  configs['guard_return'] = guardBase.copyWith(excuseWhileMoving: true);

  return StyleProfile(
    style: profile.style,
    label: profile.label,
    summary: profile.summary,
    disabledRules: profile.disabledRules,
    ruleConfigs: configs,
  );
}
