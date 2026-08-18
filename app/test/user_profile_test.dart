import 'package:boxing_coach/analysis/analysis_mode.dart';
import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/landmarks.dart';
import 'package:boxing_coach/analysis/school.dart';
import 'package:boxing_coach/domain/user_profile.dart';
import 'package:boxing_coach/services/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('UserProfile', () {
    test('defaults to orthodox high-guard, no school', () {
      const p = UserProfile();
      expect(p.stance, Stance.orthodox);
      expect(p.style, Style.highGuard);
      expect(p.school, isNull);
    });

    test('toDrill carries stance, style and school', () {
      const p = UserProfile(
        stance: Stance.southpaw,
        style: Style.phillyShell,
        school: School.soviet,
      );
      final drill = p.toDrill(notes: 'jab work');
      expect(drill.stance, Stance.southpaw);
      expect(drill.style, Style.phillyShell);
      expect(drill.school, School.soviet);
      expect(drill.notes, 'jab work');
    });

    test('copyWith can set and clear the school', () {
      const p = UserProfile(school: School.mexican);
      expect(p.copyWith(school: School.european).school, School.european);
      expect(p.copyWith(clearSchool: true).school, isNull);
      // clearSchool wins over a passed school.
      expect(p.copyWith(school: School.european, clearSchool: true).school, isNull);
    });

    test('JSON round-trips, including a null school', () {
      const withSchool = UserProfile(
        stance: Stance.southpaw,
        style: Style.outBoxer,
        school: School.american,
        analysisMode: AnalysisMode.keyframe,
      );
      final backA = UserProfile.fromJson(withSchool.toJson());
      expect(backA.stance, Stance.southpaw);
      expect(backA.style, Style.outBoxer);
      expect(backA.school, School.american);
      expect(backA.analysisMode, AnalysisMode.keyframe);

      const noSchool = UserProfile(style: Style.peekABoo);
      final backB = UserProfile.fromJson(noSchool.toJson());
      expect(backB.school, isNull);
      expect(backB.style, Style.peekABoo);
    });

    test('fromJson tolerates unknown values by falling back', () {
      final p = UserProfile.fromJson(<String, Object?>{
        'stance': 'nonsense',
        'style': 'nonsense',
        'school': 'nonsense',
      });
      expect(p.stance, Stance.orthodox);
      expect(p.style, Style.highGuard);
      expect(p.school, isNull);
    });
  });

  group('ProfileStore', () {
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('load returns the neutral default when nothing is saved', () async {
      final profile = await const ProfileStore().load();
      expect(profile.stance, Stance.orthodox);
      expect(profile.school, isNull);
    });

    test('save then load round-trips the profile', () async {
      const store = ProfileStore();
      await store.save(const UserProfile(
        stance: Stance.southpaw,
        style: Style.phillyShell,
        school: School.soviet,
      ));
      final loaded = await store.load();
      expect(loaded.stance, Stance.southpaw);
      expect(loaded.style, Style.phillyShell);
      expect(loaded.school, School.soviet);
    });
  });
}
