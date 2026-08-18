import '../analysis/analysis_mode.dart';
import '../analysis/drill.dart';
import '../analysis/landmarks.dart';
import '../analysis/school.dart';

/// Who the athlete is, for analysis. The spec's open question 3: the stance (and
/// now the style/school the round is coached against) has to come from
/// somewhere, and a profile field is the obvious answer — detecting it from the
/// pose is a nice touch and a needless dependency.
///
/// This turns straight into the [DrillContext] every round is analysed with, so
/// the now-fully-ported style/school coaching actually gets used.
class UserProfile {
  const UserProfile({
    this.stance = Stance.orthodox,
    this.style = Style.highGuard,
    this.school,
    this.analysisMode = AnalysisMode.offline,
  });

  final Stance stance;
  final Style style;

  /// The national/tactical school to coach toward. Null = no school feedback.
  final School? school;

  /// How rounds are analysed — offline rules only, or with an AI model layered
  /// on key frames / the whole round.
  final AnalysisMode analysisMode;

  DrillContext toDrill({Set<String> focus = const <String>{}, String notes = ''}) =>
      DrillContext(
        stance: stance,
        style: style,
        school: school,
        focus: focus,
        notes: notes,
      );

  UserProfile copyWith({
    Stance? stance,
    Style? style,
    School? school,
    bool clearSchool = false,
    AnalysisMode? analysisMode,
  }) => UserProfile(
    stance: stance ?? this.stance,
    style: style ?? this.style,
    school: clearSchool ? null : (school ?? this.school),
    analysisMode: analysisMode ?? this.analysisMode,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'stance': stance.name,
    'style': style.value,
    'school': school?.value,
    'analysisMode': analysisMode.value,
  };

  factory UserProfile.fromJson(Map<String, Object?> json) => UserProfile(
    stance: json['stance'] == 'southpaw' ? Stance.southpaw : Stance.orthodox,
    style: Style.values.firstWhere(
      (s) => s.value == json['style'],
      orElse: () => Style.highGuard,
    ),
    school: School.fromValue(json['school'] as String?),
    analysisMode: AnalysisMode.fromValue(json['analysisMode'] as String?),
  );
}
