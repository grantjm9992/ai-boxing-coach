import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../analysis/pose.dart';
import '../analysis/sparring_analyzer.dart';
import '../model/fighter.dart';
import '../model/sparring_session.dart';
import '../pose/multi_pose.dart';
import '../tracking/fighter_tracker.dart';

/// Sparring's own on-device storage — separate from the clip and analysis
/// stores the single-person pipeline uses.
///
/// ```
/// <documents>/sparring/<sessionId>/session.json
/// <documents>/sparring/<sessionId>/r<n>/clip.mp4        (7-day retention)
///                                     /frames.json.gz   (every body, every frame)
///                                     /decisions.json   (user's who's-who fixes)
///                                     /tracked.json     (tracklets, labels, gaps)
///                                     /fighter_a.json   (A's pose sequence)
///                                     /fighter_b.json
///                                     /analysis.json
/// ```
///
/// The raw frames are kept so identity can be corrected and the round
/// re-tracked and re-measured in a second, with no re-extraction.
class SparringStore {
  SparringStore({Directory? baseDir, DateTime Function()? now})
    : _injected = baseDir,
      _now = now ?? DateTime.now;

  final Directory? _injected;
  final DateTime Function() _now;

  /// Same retention as single-person clips; everything else is kept.
  static const Duration clipRetention = Duration(days: 7);

  /// Changes whenever a session is saved, so screens can refresh.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Directory? _rootCache;

  Future<Directory> root() async {
    final cached = _rootCache;
    if (cached != null) return cached;
    final base = _injected ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/sparring');
    if (!await dir.exists()) await dir.create(recursive: true);
    return _rootCache = dir;
  }

  Future<Directory> _sessionDir(String sessionId) async {
    final dir = Directory('${(await root()).path}/$sessionId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> roundDir(String sessionId, int round) async {
    final dir = Directory('${(await _sessionDir(sessionId)).path}/r$round');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// A new session id (timestamp-based, like the rest of the app).
  String newSessionId() => 'spar-${_now().millisecondsSinceEpoch}';

  // -- sessions ---------------------------------------------------------------

  Future<void> saveSession(SparringSession session) async {
    final dir = await _sessionDir(session.id);
    await _writeJson(File('${dir.path}/session.json'), session.toJson());
    revision.value++;
  }

  Future<SparringSession?> loadSession(String sessionId) async {
    final file = File('${(await root()).path}/$sessionId/session.json');
    final json = await _readJson(file);
    if (json == null) return null;
    try {
      return SparringSession.fromJson(json);
    } on Object catch (error) {
      debugPrint('Bad sparring session $sessionId: $error');
      return null;
    }
  }

  /// Every stored session, newest first.
  Future<List<SparringSession>> listSessions() async {
    final out = <SparringSession>[];
    final dir = await root();
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final session = await loadSession(entity.uri.pathSegments.where((s) => s.isNotEmpty).last);
      if (session != null) out.add(session);
    }
    out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return out;
  }

  /// Reads, changes and saves a session in one step.
  Future<SparringSession?> update(
    String sessionId,
    SparringSession Function(SparringSession) change,
  ) async {
    final current = await loadSession(sessionId);
    if (current == null) return null;
    final next = change(current);
    await saveSession(next);
    return next;
  }

  Future<void> deleteSession(String sessionId) async {
    final dir = Directory('${(await root()).path}/$sessionId');
    if (await dir.exists()) await dir.delete(recursive: true);
    revision.value++;
  }

  // -- round files ----------------------------------------------------------

  Future<String> clipPath(String sessionId, int round) async =>
      '${(await roundDir(sessionId, round)).path}/clip.mp4';

  /// Moves a freshly recorded file into the round's folder.
  Future<String> adoptClip(String sessionId, int round, String tempPath) async {
    final target = await clipPath(sessionId, round);
    final source = File(tempPath);
    try {
      await source.rename(target);
    } on FileSystemException {
      await source.copy(target);
      await source.delete();
    }
    return target;
  }

  Future<bool> hasClip(String sessionId, int round) async =>
      File(await clipPath(sessionId, round)).exists();

  Future<void> saveFrames(String sessionId, int round, MultiPoseRound frames) async {
    final dir = await roundDir(sessionId, round);
    final bytes = gzip.encode(utf8.encode(jsonEncode(jsonSafe(frames.toJson()))));
    await File('${dir.path}/frames.json.gz').writeAsBytes(bytes, flush: true);
  }

  Future<MultiPoseRound?> loadFrames(String sessionId, int round) async {
    final file = File('${(await roundDir(sessionId, round)).path}/frames.json.gz');
    if (!await file.exists()) return null;
    try {
      final json = jsonDecode(utf8.decode(gzip.decode(await file.readAsBytes())));
      return MultiPoseRound.fromJson((json as Map).cast<String, Object?>());
    } on Object catch (error) {
      debugPrint('Bad sparring frames $sessionId/r$round: $error');
      return null;
    }
  }

  /// The user's identity decisions: tracklet id → label (null = neither).
  Future<Map<int, FighterLabel?>> loadDecisions(String sessionId, int round) async {
    final json = await _readJson(File('${(await roundDir(sessionId, round)).path}/decisions.json'));
    final forced = (json?['forced'] as Map?)?.cast<String, Object?>() ?? const <String, Object?>{};
    return <int, FighterLabel?>{
      for (final e in forced.entries)
        if (int.tryParse(e.key) != null) int.parse(e.key): FighterLabel.fromValue(e.value),
    };
  }

  Future<void> saveDecisions(String sessionId, int round, Map<int, FighterLabel?> forced) async {
    final dir = await roundDir(sessionId, round);
    await _writeJson(File('${dir.path}/decisions.json'), <String, Object?>{
      'forced': <String, Object?>{
        for (final e in forced.entries) '${e.key}': e.value?.value ?? 'none',
      },
    });
  }

  Future<void> saveTracked(String sessionId, int round, TrackedRound tracked) async {
    final dir = await roundDir(sessionId, round);
    await _writeJson(File('${dir.path}/tracked.json'), tracked.toJson());
    for (final label in FighterLabel.values) {
      await _writeJson(
        File('${dir.path}/fighter_${label.value}.json'),
        tracked.fighters[label]!.toJson(),
      );
    }
  }

  Future<TrackedRound?> loadTracked(String sessionId, int round) async {
    final dir = await roundDir(sessionId, round);
    final json = await _readJson(File('${dir.path}/tracked.json'));
    if (json == null) return null;
    final fighters = <FighterLabel, PoseSequence>{};
    for (final label in FighterLabel.values) {
      final seq = await _readJson(File('${dir.path}/fighter_${label.value}.json'));
      if (seq == null) return null;
      fighters[label] = PoseSequence.fromJson(seq);
    }
    try {
      return TrackedRound.fromJson(json, fighters);
    } on Object catch (error) {
      debugPrint('Bad sparring track $sessionId/r$round: $error');
      return null;
    }
  }

  /// The per-fighter pose files, for upload.
  Future<File?> fighterFile(String sessionId, int round, FighterLabel label) async {
    final file = File('${(await roundDir(sessionId, round)).path}/fighter_${label.value}.json');
    return await file.exists() ? file : null;
  }

  Future<void> saveAnalysis(String sessionId, int round, SparringRoundAnalysis analysis) async {
    final dir = await roundDir(sessionId, round);
    await _writeJson(File('${dir.path}/analysis.json'), analysis.toJson());
    revision.value++;
  }

  Future<SparringRoundAnalysis?> loadAnalysis(String sessionId, int round) async {
    final json = await _readJson(File('${(await roundDir(sessionId, round)).path}/analysis.json'));
    if (json == null) return null;
    try {
      return SparringRoundAnalysis.fromJson(json);
    } on Object catch (error) {
      debugPrint('Bad sparring analysis $sessionId/r$round: $error');
      return null;
    }
  }

  /// Deletes clips older than [clipRetention]; everything else stays.
  Future<int> sweepExpiredClips() async {
    var deleted = 0;
    final cutoff = _now().subtract(clipRetention);
    final dir = await root();
    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('/clip.mp4')) continue;
      try {
        if ((await entity.lastModified()).isBefore(cutoff)) {
          await entity.delete();
          deleted++;
        }
      } on FileSystemException {
        // Gone already.
      }
    }
    return deleted;
  }

  static Future<void> _writeJson(File file, Map<String, Object?> json) async {
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(jsonSafe(json)), flush: true);
    await tmp.rename(file.path);
  }

  static Future<Map<String, Object?>?> _readJson(File file) async {
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } on Object {
      return null;
    }
  }
}

/// [value] with every non-finite double replaced by null — JSON has no NaN,
/// and a single NaN metric from a rule must not lose a round's analysis.
Object? jsonSafe(Object? value) {
  if (value is double) return value.isFinite ? value : null;
  if (value is Map) {
    return <String, Object?>{
      for (final e in value.entries) '${e.key}': jsonSafe(e.value),
    };
  }
  if (value is List) return <Object?>[for (final v in value) jsonSafe(v)];
  return value;
}
