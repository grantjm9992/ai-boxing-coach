import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../domain/round_clip.dart';

/// Where recorded rounds live on disk, and the seven-day retention policy that
/// stops them living there forever.
///
/// The spec's answer to its own open question 2 is "keep clips 7 days, then
/// delete unless explicitly saved; analysis persists", and the v0.5 design note
/// is blunt about it: *a retention policy added later is a retention policy that
/// never ships.* So the sweep is written alongside the writing, and it is the
/// part that gets a unit test — [baseDir] and [now] are injectable precisely so
/// the sweep can be tested against a temp directory and a fake clock, with no
/// camera and no plugin.
class ClipStore {
  ClipStore({Directory? baseDir, DateTime Function()? now})
    : _injectedBase = baseDir,
      _now = now ?? DateTime.now;

  final Directory? _injectedBase;
  final DateTime Function() _now;

  /// How long a clip survives before the sweep deletes it. The spec's number.
  static const Duration retention = Duration(days: 7);

  static const String _indexFile = 'index.json';

  Directory? _clipsDirCache;

  /// The directory clips and the index live in, created on first use. Defaults
  /// to `<app documents>/clips`; tests inject [baseDir] instead.
  Future<Directory> clipsDir() async {
    final cached = _clipsDirCache;
    if (cached != null) return cached;
    final base = _injectedBase ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/clips');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _clipsDirCache = dir;
    return dir;
  }

  /// A fresh, unused file path to record the given round into. The name encodes
  /// the session and segment so it is legible on disk and collision-free within
  /// a session.
  Future<String> allocatePath(String sessionId, int segmentIndex) async {
    final dir = await clipsDir();
    return '${dir.path}/${sessionId}_seg$segmentIndex.mp4';
  }

  /// Records a finished clip in the index. If a clip already exists for the same
  /// session and segment (a re-record), it is replaced.
  Future<void> add(RoundClip clip) async {
    final clips = await list()
      ..removeWhere(
        (c) =>
            c.sessionId == clip.sessionId &&
            c.segmentIndex == clip.segmentIndex,
      )
      ..add(clip);
    await _writeIndex(clips);
  }

  /// Every clip currently known, newest first.
  Future<List<RoundClip>> list() async {
    try {
      final file = await _indexPath();
      if (!await file.exists()) return <RoundClip>[];
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! List) return <RoundClip>[];
      final clips = <RoundClip>[
        for (final entry in decoded)
          if (entry is Map)
            ?RoundClip.fromJson(entry.cast<String, Object?>()),
      ]..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      return clips;
    } on Object catch (error) {
      debugPrint('Could not read clip index: $error');
      return <RoundClip>[];
    }
  }

  Future<List<RoundClip>> listForSession(String sessionId) async {
    final clips = await list();
    return clips.where((c) => c.sessionId == sessionId).toList()
      ..sort((a, b) => a.segmentIndex.compareTo(b.segmentIndex));
  }

  /// Deletes clips older than [keepFor], file and index entry both. Returns how
  /// many were removed. Also drops index entries whose file has vanished, so the
  /// index never outlives the clips it points at.
  Future<int> sweepExpired({Duration keepFor = retention}) async {
    final cutoff = _now().subtract(keepFor);
    final clips = await list();
    final kept = <RoundClip>[];
    var removed = 0;
    for (final clip in clips) {
      final file = File(clip.path);
      final expired = clip.recordedAt.isBefore(cutoff);
      final missing = !await file.exists();
      if (expired || missing) {
        if (expired && !missing) {
          try {
            await file.delete();
          } on Object catch (error) {
            debugPrint('Could not delete expired clip ${clip.path}: $error');
          }
        }
        removed++;
        continue;
      }
      kept.add(clip);
    }
    if (removed > 0) await _writeIndex(kept);
    return removed;
  }

  Future<File> _indexPath() async {
    final dir = await clipsDir();
    return File('${dir.path}/$_indexFile');
  }

  Future<void> _writeIndex(List<RoundClip> clips) async {
    try {
      final file = await _indexPath();
      await file.writeAsString(
        jsonEncode(<Map<String, Object?>>[for (final c in clips) c.toJson()]),
      );
    } on Object catch (error) {
      debugPrint('Could not write clip index: $error');
    }
  }
}
