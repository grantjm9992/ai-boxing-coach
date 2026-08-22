import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// App-wide, on-device diagnostic log.
///
/// Everything routed through here is kept in a rolling in-memory buffer (for the
/// in-app viewer) *and* appended to a file so it survives the session — the only
/// way to see what a release APK is doing on a device with no logcat. [init]
/// also hijacks Flutter's [debugPrint], so the diagnostics already scattered
/// through the app (analysis/sync/store failures) are captured for free.
class DebugLog extends ChangeNotifier {
  DebugLog._();

  /// The one instance the app logs through.
  static final DebugLog instance = DebugLog._();

  /// Cap the buffer + rewritten file so a long-running session can't grow it
  /// without bound.
  static const int _maxLines = 2000;

  final List<String> _lines = <String>[];
  File? _file;
  bool _initialised = false;
  // Serialises file appends so concurrent log() calls can't interleave writes.
  Future<void> _writeChain = Future<void>.value();

  /// Newest last. A copy — callers must not mutate the buffer.
  List<String> get lines => List<String>.unmodifiable(_lines);

  /// The whole log as one string, for copy / share.
  String get text => _lines.join('\n');

  /// The backing file, once [init] has run (null if storage was unavailable).
  File? get file => _file;

  /// Load anything from a previous run and route [debugPrint] through here.
  /// Idempotent; safe to call before the first frame.
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/debug.log');
      if (await file.exists()) {
        final existing = await file.readAsLines();
        _lines.addAll(
          existing.length > _maxLines
              ? existing.sublist(existing.length - _maxLines)
              : existing,
        );
      }
      _file = file;
    } on Object catch (_) {
      // No file storage — in-memory logging still works.
    }

    // Capture every debugPrint in the app without touching each call site.
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) _append('[print] $message');
      original(message, wrapWidth: wrapWidth);
    };

    log('debug log ready (${_lines.length} lines from previous runs)',
        tag: 'log');
  }

  /// Append one entry. [tag] groups related lines (e.g. 'sync', 'analysis').
  void log(String message, {String tag = 'app'}) => _append('[$tag] $message');

  void _append(String body) {
    final line = '${DateTime.now().toIso8601String()} $body';
    _lines.add(line);
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    final file = _file;
    if (file != null) {
      _writeChain = _writeChain.then((_) async {
        try {
          await file.writeAsString('$line\n', mode: FileMode.append);
        } on Object catch (_) {
          // A failed write must never break the thing being logged.
        }
      });
    }
    notifyListeners();
  }

  /// Wipe the buffer and the file.
  Future<void> clear() async {
    _lines.clear();
    final file = _file;
    if (file != null) {
      _writeChain = _writeChain.then((_) async {
        try {
          await file.writeAsString('');
        } on Object catch (_) {}
      });
    }
    notifyListeners();
  }
}
