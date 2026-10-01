import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Sparring runs in landscape — the camera is ringside and both fighters need
/// the width — while the rest of the app stays portrait.
///
/// Reference-counted, because sparring screens stack (session → round → check
/// who's who) and a replacement route starts before the one it replaces is
/// disposed: landscape holds while any sparring screen is alive and portrait
/// comes back when the last one goes.
class SparringOrientation {
  const SparringOrientation._();

  static int _holds = 0;

  /// Overridable for tests (no platform channel there).
  static Future<void> Function(List<DeviceOrientation>) apply =
      SystemChrome.setPreferredOrientations;

  static const List<DeviceOrientation> landscape = <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  /// The app's normal orientation (as set in main.dart).
  static const List<DeviceOrientation> portrait = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ];

  static bool get isLandscape => _holds > 0;

  static void enter() {
    _holds++;
    if (_holds == 1) _set(landscape);
  }

  static void exit() {
    if (_holds == 0) return;
    _holds--;
    if (_holds == 0) _set(portrait);
  }

  static void _set(List<DeviceOrientation> orientations) {
    apply(orientations).catchError((Object _) {});
  }
}

/// Mix into a sparring screen's [State] to hold landscape while it's alive.
mixin SparringLandscape<T extends StatefulWidget> on State<T> {
  @override
  void initState() {
    super.initState();
    SparringOrientation.enter();
  }

  @override
  void dispose() {
    SparringOrientation.exit();
    super.dispose();
  }
}
