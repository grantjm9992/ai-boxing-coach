import 'dart:convert';

import 'package:boxing_coach/analysis/drill.dart';
import 'package:boxing_coach/analysis/error_codes.dart';
import 'package:boxing_coach/analysis/round_analysis.dart';
import 'package:boxing_coach/analysis/session_type.dart';
import 'package:boxing_coach/domain/session_phase.dart';
import 'package:boxing_coach/domain/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 1 (brief §4, §12, §21, §25): the session-type + data-model spine.
void main() {
  group('SessionType', () {
    test('wire values round-trip and default to free training', () {
      for (final type in SessionType.values) {
        expect(SessionType.fromValue(type.value), type);
      }
      expect(SessionType.fromValue(null), SessionType.freeTraining);
      expect(SessionType.fromValue('NONSENSE'), SessionType.freeTraining);
    });
  });

  group('SessionPhase.sessionType derivation', () {
    test('maps recordable phases to the right intent', () {
      expect(SessionPhase.shadow.sessionType, SessionType.shadowBoxing);
      expect(SessionPhase.technical.sessionType, SessionType.technicalWork);
      expect(SessionPhase.conditioning.sessionType, SessionType.heavyBag);
    });

    test('non-boxing phases fall back to free training', () {
      expect(SessionPhase.warmUp.sessionType, SessionType.freeTraining);
      expect(SessionPhase.coolDown.sessionType, SessionType.freeTraining);
    });
  });

  group('DrillContext', () {
    test('defaults to free training', () {
      expect(const DrillContext().sessionType, SessionType.freeTraining);
    });

    test('UserProfile.toDrill carries the session type through', () {
      final drill = const UserProfile()
          .toDrill(sessionType: SessionType.shadowBoxing);
      expect(drill.sessionType, SessionType.shadowBoxing);
    });
  });

  group('Observation confidence + code', () {
    test('default to full confidence and no code', () {
      const obs = Observation(
        ruleId: 'r',
        category: SkillCategory.defence,
        severity: Severity.minor,
        coachingText: 'x',
      );
      expect(obs.confidence, 1.0);
      expect(obs.code, '');
    });

    test('round-trip through JSON', () {
      const obs = Observation(
        ruleId: 'guard_return',
        code: FaultCode.recHandNotReturned,
        category: SkillCategory.defence,
        severity: Severity.moderate,
        coachingText: 'hand back',
        confidence: 0.75,
      );
      final back = Observation.fromJson(
        jsonDecode(jsonEncode(obs.toJson())) as Map<String, Object?>,
      );
      expect(back.code, FaultCode.recHandNotReturned);
      expect(back.confidence, 0.75);
    });

    test('legacy JSON without code/confidence loads with defaults', () {
      final legacy = <String, Object?>{
        'ruleId': 'r',
        'category': 'defence',
        'severity': 'minor',
        'coachingText': 'x',
        'metrics': <String, Object?>{},
        'highlight': <Object?>[],
      };
      final obs = Observation.fromJson(legacy);
      expect(obs.confidence, 1.0);
      expect(obs.code, '');
    });
  });

  group('RoundAnalysis metadata', () {
    test('carries analysis version + session type through JSON', () {
      final analysis = RoundAnalysis(
        overallSummary: 'summary',
        sessionType: SessionType.shadowBoxing,
      );
      expect(analysis.analysisVersion, RoundAnalysis.currentAnalysisVersion);

      final back = RoundAnalysis.fromJson(
        jsonDecode(jsonEncode(analysis.toJson())) as Map<String, Object?>,
      );
      expect(back.analysisVersion, RoundAnalysis.currentAnalysisVersion);
      expect(back.sessionType, SessionType.shadowBoxing);
    });

    test('legacy analysis JSON (pre-2.0) loads as 1.0.0 / free training', () {
      final legacy = <String, Object?>{'overallSummary': 'old'};
      final back = RoundAnalysis.fromJson(legacy);
      expect(back.analysisVersion, '1.0.0');
      expect(back.sessionType, SessionType.freeTraining);
    });

    test('withModelCoaching preserves version + session type', () {
      final analysis = RoundAnalysis(
        overallSummary: 's',
        sessionType: SessionType.technicalWork,
      ).withModelCoaching('coach');
      expect(analysis.sessionType, SessionType.technicalWork);
      expect(analysis.analysisVersion, RoundAnalysis.currentAnalysisVersion);
      expect(analysis.modelCoaching, 'coach');
    });
  });
}
