import 'package:boxing_coach/services/app_foreground.dart';
import 'package:boxing_coach/services/keep_awake.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeepAwake', () {
    late List<bool> toggles;
    late KeepAwake awake;

    setUp(() {
      toggles = <bool>[];
      awake = KeepAwake.forTesting((on) async => toggles.add(on));
    });

    test('turns on with the first hold and off with the last', () {
      final session = awake.acquire('session');
      final analysis = awake.acquire('analysis');
      expect(toggles, <bool>[true]);

      // A background analysis finishing mid-session must not let the screen
      // lock under the session.
      analysis();
      expect(toggles, <bool>[true]);
      expect(awake.isHeld, isTrue);

      session();
      expect(toggles, <bool>[true, false]);
      expect(awake.isHeld, isFalse);
    });

    test('releasing twice is harmless', () {
      final release = awake.acquire('analysis');
      final other = awake.acquire('session');
      release();
      release();
      expect(awake.isHeld, isTrue);
      other();
      expect(toggles, <bool>[true, false]);
    });

    test('a failing wakelock toggle does not throw', () async {
      final failing = KeepAwake.forTesting((_) async => throw StateError('no plugin'));
      expect(() => failing.acquire('x')(), returnsNormally);
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('AppForeground', () {
    testWidgets('counts foreground time only since the last resume', (tester) async {
      final fg = AppForeground.instance..start();

      fg.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(fg.isForeground, isFalse);
      expect(fg.foregroundFor(), Duration.zero);

      fg.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(fg.isForeground, isTrue);
      final later = DateTime.now().add(const Duration(seconds: 50));
      expect(fg.foregroundFor(later), greaterThanOrEqualTo(const Duration(seconds: 49)));
      // Just resumed: nowhere near a 45 s stall window yet.
      expect(fg.foregroundFor(), lessThan(const Duration(seconds: 45)));
    });
  });
}
