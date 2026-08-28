import 'package:boxing_coach/analysis/regression_dataset.dart';
import 'package:boxing_coach/services/analytics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Phase 7 (brief §23, §26): analytics events + the regression-dataset scoring.
void main() {
  group('Analytics', () {
    test('event wire names are unique and stable', () {
      final names = AnalyticsEvent.values.map((e) => e.name).toList();
      expect(names.toSet().length, names.length);
      // A couple of anchors so a rename is caught.
      expect(AnalyticsEvent.combinationMatchSuccess.name,
          'combination_match_success');
      expect(AnalyticsEvent.analysisFailed.name, 'analysis_failed');
    });

    test('FakeAnalytics records events and properties', () {
      final analytics = FakeAnalytics();
      analytics.log(AnalyticsEvent.sessionStarted);
      analytics.log(AnalyticsEvent.combinationSelected, {'id': 'combo_1_2'});
      expect(analytics.count(AnalyticsEvent.sessionStarted), 1);
      expect(analytics.events.last.$2['id'], 'combo_1_2');
    });
  });

  group('RegressionDataset', () {
    test('round-trips through JSON', () {
      const dataset = RegressionDataset(<RegressionCase>[
        RegressionCase(
          video: 'test_001.mp4',
          expectedPunches: <int>[1, 2, 3],
          knownIssues: <String>['GUARD_003'],
        ),
      ]);
      final back = RegressionDataset.fromJson(dataset.toJson());
      expect(back.cases.single.video, 'test_001.mp4');
      expect(back.cases.single.expectedPunches, <int>[1, 2, 3]);
      expect(back.cases.single.knownIssues, <String>['GUARD_003']);
    });
  });

  group('classification accuracy', () {
    final pairs = <(List<int>, List<int>)>[
      (<int>[1, 2, 3], <int>[1, 2, 3]), // exact
      (<int>[1, 3, 4], <int>[1, 3, 2]), // last punch wrong
      (<int>[1, 2], <int>[1, 2]), // exact
    ];

    test('sequence match accuracy is the exact-match fraction', () {
      expect(sequenceMatchAccuracy(pairs), closeTo(2 / 3, 1e-9));
      expect(sequenceMatchAccuracy(const []), 0);
    });

    test('token accuracy scores per-punch', () {
      // 3/3 + 2/3 + 2/2 correct = 7 of 8 punches.
      expect(punchTokenAccuracy(pairs), closeTo(7 / 8, 1e-9));
      expect(punchTokenAccuracy(const []), 0);
    });
  });
}
