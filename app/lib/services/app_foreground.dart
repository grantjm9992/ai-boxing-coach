import 'package:flutter/widgets.dart';

import 'debug_log.dart';

/// Tracks whether the app is in the foreground, and since when, so long-running
/// work can tell a genuine stall from the OS pausing the app.
///
/// While the app is backgrounded or the screen is off, Android may throttle or
/// freeze it; a native stream then goes quiet for reasons that have nothing to
/// do with the work itself. Watchdogs ask [foregroundFor] before giving up.
/// Also logs every lifecycle change to the debug log, so a stalled run's trace
/// shows whether the app left the foreground.
class AppForeground with WidgetsBindingObserver {
  AppForeground._();

  static final AppForeground instance = AppForeground._();

  bool _started = false;
  bool _foreground = true;
  DateTime _since = DateTime.now();

  /// Starts observing. Idempotent; call once the binding exists (from main).
  void start() {
    if (_started) return;
    _started = true;
    final binding = WidgetsBinding.instance;
    final state = binding.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
    _since = DateTime.now();
    binding.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    DebugLog.instance.log('lifecycle → ${state.name}', tag: 'app');
    if (foreground != _foreground) {
      _foreground = foreground;
      _since = DateTime.now();
    }
  }

  bool get isForeground => _foreground;

  /// How long the app has been continuously in the foreground; zero while it
  /// isn't. Before [start] (unit tests) the app is treated as always foreground.
  Duration foregroundFor([DateTime? now]) {
    if (!_started) return const Duration(days: 1);
    if (!_foreground) return Duration.zero;
    return (now ?? DateTime.now()).difference(_since);
  }
}
