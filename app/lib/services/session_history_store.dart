import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/session_record.dart';

/// Persists completed sessions and rolls them up into the weekly category
/// balance. One JSON file per session under `<appDocs>/history/`.
class SessionHistoryStore {
  SessionHistoryStore({Directory? baseDir, DateTime Function()? now})
    : _injectedBase = baseDir,
      _now = now ?? DateTime.now;

  final Directory? _injectedBase;
  final DateTime Function() _now;

  Directory? _cache;

  Future<Directory> _dir() async {
    final cached = _cache;
    if (cached != null) return cached;
    final base = _injectedBase ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/history');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _cache = dir;
  }

  Future<void> save(SessionRecord record) async {
    try {
      final dir = await _dir();
      await File('${dir.path}/${record.sessionId}.json')
          .writeAsString(jsonEncode(record.toJson()));
    } on Object catch (error) {
      debugPrint('Could not save session ${record.sessionId}: $error');
    }
  }

  /// All completed sessions, newest first.
  Future<List<SessionRecord>> list() async {
    try {
      final dir = await _dir();
      final records = <SessionRecord>[];
      await for (final entity in dir.list()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map) continue;
        final record = SessionRecord.fromJson(decoded.cast<String, Object?>());
        if (record != null) records.add(record);
      }
      records.sort((a, b) => b.completedAt.compareTo(a.completedAt));
      return records;
    } on Object catch (error) {
      debugPrint('Could not list session history: $error');
      return <SessionRecord>[];
    }
  }

  /// Weighted working seconds per category-key over the last [window],
  /// aggregated across sessions — the weekly balance view's data.
  Future<Map<String, int>> weeklyBalance({
    Duration window = const Duration(days: 7),
  }) async {
    final cutoff = _now().subtract(window);
    final recent =
        (await list()).where((r) => r.completedAt.isAfter(cutoff));
    return aggregateCategorySeconds(recent);
  }

  /// Sums category seconds across records. Pure, so it is unit-tested directly.
  static Map<String, int> aggregateCategorySeconds(
    Iterable<SessionRecord> records,
  ) {
    final totals = <String, int>{};
    for (final record in records) {
      record.categorySeconds.forEach((key, seconds) {
        totals[key] = (totals[key] ?? 0) + seconds;
      });
    }
    return totals;
  }
}
