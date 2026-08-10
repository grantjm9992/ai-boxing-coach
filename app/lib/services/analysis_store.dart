import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../analysis/pose.dart';
import '../analysis/round_analysis.dart';

/// Persists a round's analysis and its pose sequence as JSON files beside the
/// clip they came from, keyed by session + segment.
///
/// The analysis is small; the pose sequence is a few hundred KB (it lets the
/// review screen redraw the skeleton without re-running MediaPipe). Both are
/// swept with the clip by the [ClipStore] retention policy — but analysis
/// outlives the video for history, so it is also rolled up into the
/// [SessionHistoryStore] on session end.
class AnalysisStore {
  AnalysisStore({Directory? baseDir}) : _injectedBase = baseDir;

  final Directory? _injectedBase;
  Directory? _cache;

  Future<Directory> _dir() async {
    final cached = _cache;
    if (cached != null) return cached;
    final base = _injectedBase ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/clips');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _cache = dir;
  }

  String _stem(String sessionId, int segmentIndex) =>
      '${sessionId}_seg$segmentIndex';

  Future<void> save(
    String sessionId,
    int segmentIndex, {
    required RoundAnalysis analysis,
    PoseSequence? sequence,
  }) async {
    try {
      final dir = await _dir();
      final stem = _stem(sessionId, segmentIndex);
      await File('${dir.path}/$stem.analysis.json')
          .writeAsString(jsonEncode(analysis.toJson()));
      if (sequence != null) {
        await File('${dir.path}/$stem.pose.json')
            .writeAsString(jsonEncode(sequence.toJson()));
      }
    } on Object catch (error) {
      debugPrint('Could not save analysis for $sessionId/$segmentIndex: $error');
    }
  }

  Future<RoundAnalysis?> loadAnalysis(String sessionId, int segmentIndex) async {
    return _loadJson('${_stem(sessionId, segmentIndex)}.analysis.json',
        (m) => RoundAnalysis.fromJson(m));
  }

  Future<PoseSequence?> loadPose(String sessionId, int segmentIndex) async {
    return _loadJson('${_stem(sessionId, segmentIndex)}.pose.json',
        (m) => PoseSequence.fromJson(m));
  }

  Future<T?> _loadJson<T>(
    String name,
    T Function(Map<String, Object?>) parse,
  ) async {
    try {
      final dir = await _dir();
      final file = File('${dir.path}/$name');
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return parse(decoded.cast<String, Object?>());
    } on Object catch (error) {
      debugPrint('Could not load $name: $error');
      return null;
    }
  }
}
