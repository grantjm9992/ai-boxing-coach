import 'dart:io';
import 'dart:math' as math;

import 'package:boxing_coach/sparring/analysis/sparring_analyzer.dart';
import 'package:boxing_coach/sparring/data/sparring_store.dart';
import 'package:boxing_coach/sparring/model/sparring_session.dart';
import 'package:boxing_coach/sparring/pose/multi_pose.dart';
import 'package:boxing_coach/sparring/tracking/fighter_tracker.dart';
import 'package:boxing_coach/sparring/ui/sparring_orientation.dart';
import 'package:boxing_coach/sparring/ui/sparring_round_screen.dart';
import 'package:boxing_coach/sparring/ui/sparring_setup_screen.dart';
import 'package:boxing_coach/ui/screens/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'synthetic.dart';

void main() {
  late List<List<DeviceOrientation>> applied;

  setUp(() {
    applied = <List<DeviceOrientation>>[];
    SparringOrientation.apply = (o) async => applied.add(o);
  });

  void landscapeView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  test('landscape holds while any sparring screen is alive', () {
    SparringOrientation.enter();
    SparringOrientation.enter(); // a pushed screen
    SparringOrientation.exit(); // the first one goes
    expect(SparringOrientation.isLandscape, isTrue);
    SparringOrientation.exit();
    expect(SparringOrientation.isLandscape, isFalse);
    expect(applied, <List<DeviceOrientation>>[
      SparringOrientation.landscape,
      SparringOrientation.portrait,
    ]);
    SparringOrientation.exit(); // extra exits are harmless
    expect(applied, hasLength(2));
  });

  testWidgets('home has a Sparring section leading to setup', (tester) async {
    tester.view.physicalSize = const Size(500, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Sparring'), findsOneWidget);
    await tester.tap(find.text('Sparring'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Set up sparring'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Past sparring'), findsOneWidget);
  });

  testWidgets('setup is landscape and offers rounds, lengths and the AI review', (tester) async {
    landscapeView(tester);
    await tester.pumpWidget(const MaterialApp(home: SparringSetupScreen()));
    await tester.pump();
    expect(applied.single, SparringOrientation.landscape);
    expect(find.text('Rounds'), findsOneWidget);
    expect(find.text('Round length'), findsOneWidget);
    expect(find.text('AI coach reviews each round'), findsOneWidget);
    expect(find.text('Set up the camera'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(applied.last, SparringOrientation.portrait);
  });

  testWidgets('round review shows both fighters and the Together tab', (tester) async {
    landscapeView(tester);
    late Directory dir;
    late SparringStore store;
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('sparring_ui');
      store = SparringStore(baseDir: dir);
      final rnd = math.Random(1);
      const red = Person(1, topBin: 8, shortsBin: 0);
      const blue = Person(2, topBin: 10, shortsBin: 5);
      final round = roundOf(<List<PoseCandidate>>[
        for (var i = 0; i < 80; i++)
          <PoseCandidate>[
            body(red, x: 0.25, facing: 1, jitter: rnd),
            body(blue, x: 0.75, facing: -1, jitter: rnd),
          ],
      ]);
      final tracked = const FighterTracker().track(round);
      await store.saveSession(
        SparringSession(id: 's', createdAt: DateTime(2026, 10, 1), identified: true, partnerName: 'Dani')
            .withRound(SparringRound(number: 1, recordedAt: DateTime(2026, 10, 1), status: SparringRoundStatus.done)),
      );
      await store.saveTracked('s', 1, tracked);
      await store.saveAnalysis('s', 1, const SparringAnalyzer().analyse(tracked));
    });
    addTearDown(() async => tester.runAsync(() => dir.delete(recursive: true)));

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(home: SparringRoundScreen(sessionId: 's', round: 1, store: store)));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await tester.pump();
    expect(find.text('You'), findsWidgets);
    expect(find.text('Dani'), findsWidgets);
    expect(find.text('Together'), findsOneWidget);
    expect(find.text('Punches'), findsOneWidget);
    expect(find.textContaining('Video not available'), findsOneWidget);

    await tester.tap(find.text('Together'));
    await tester.pumpAndSettle();
    expect(find.text('Range'), findsOneWidget);
    expect(find.text('Counters'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
