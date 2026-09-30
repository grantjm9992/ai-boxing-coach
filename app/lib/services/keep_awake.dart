import 'package:wakelock_plus/wakelock_plus.dart';

import 'debug_log.dart';

/// Keeps the screen on while something long-running needs the app in the
/// foreground — a live session, or a round's analysis.
///
/// Reference-counted, because the holders overlap: a round's background
/// analysis can still be running when the user starts the next session, and
/// either one finishing must not switch the screen timeout back on under the
/// other. [acquire] returns a release callback; the wakelock is on while at
/// least one hold is outstanding.
///
/// Why analysis needs it: pose estimation on a 2–3 minute round takes a few
/// minutes of CPU. If the phone auto-locks meanwhile, Android (and MIUI /
/// HyperOS battery management especially) throttles or freezes the app and
/// cuts its network, so the run stalls and any AI upload fails.
class KeepAwake {
  KeepAwake._({Future<void> Function(bool enabled)? toggle})
    : _toggle = toggle ?? ((on) => WakelockPlus.toggle(enable: on));

  static final KeepAwake instance = KeepAwake._();

  /// A separate instance with an injected toggle, for tests.
  factory KeepAwake.forTesting(Future<void> Function(bool enabled) toggle) =>
      KeepAwake._(toggle: toggle);

  final Future<void> Function(bool enabled) _toggle;
  final Map<int, String> _holds = <int, String>{};
  int _nextId = 0;

  bool get isHeld => _holds.isNotEmpty;

  /// Keeps the screen on until the returned callback is called. Calling the
  /// callback more than once is harmless.
  void Function() acquire(String reason) {
    final id = _nextId++;
    _holds[id] = reason;
    if (_holds.length == 1) _set(true, reason);
    return () {
      if (_holds.remove(id) == null) return;
      if (_holds.isEmpty) _set(false, reason);
    };
  }

  void _set(bool on, String reason) {
    DebugLog.instance.log('screen keep-awake ${on ? 'on' : 'off'} ($reason)',
        tag: 'app');
    void failed(Object error) =>
        DebugLog.instance.log('wakelock toggle failed: $error', tag: 'app');
    // Best effort: no wakelock (no plugin in tests, an unsupported platform)
    // must never break the work that asked for it.
    try {
      _toggle(on).catchError(failed);
    } on Object catch (error) {
      failed(error);
    }
  }
}
