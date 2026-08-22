import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/round_clip.dart';
import '../debug_log.dart';
import 'round_sync.dart';

enum SyncJobKind { round, finalize }

/// One durable unit of work: sync a round, or mark a session finished. Persisted
/// so a round recorded offline (or a sync that failed) is retried on a later
/// launch / sign-in, instead of being lost until a manual re-analyse.
class SyncJob {
  SyncJob({
    required this.kind,
    this.clip,
    this.title,
    this.mode,
    this.clientSessionId,
    this.rollup,
    this.attempts = 0,
  });

  final SyncJobKind kind;
  final RoundClip? clip; // round jobs
  final String? title;
  final String? mode; // round jobs
  final String? clientSessionId; // finalize jobs
  final Map<String, Object?>? rollup; // finalize jobs — session-level summary
  int attempts;

  /// One job per round / per session — re-enqueuing replaces rather than dupes.
  String get key => kind == SyncJobKind.round
      ? 'round:${clip!.sessionId}/${clip!.segmentIndex}'
      : 'finalize:$clientSessionId';

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'clip': clip?.toJson(),
    'title': title,
    'mode': mode,
    'clientSessionId': clientSessionId,
    'rollup': rollup,
    'attempts': attempts,
  };

  static SyncJob? fromJson(Map<String, Object?> json) {
    final kind = SyncJobKind.values.firstWhere(
      (k) => k.name == json['kind'],
      orElse: () => SyncJobKind.round,
    );
    final clipJson = json['clip'];
    final clip = clipJson is Map
        ? RoundClip.fromJson(clipJson.cast<String, Object?>())
        : null;
    if (kind == SyncJobKind.round && clip == null) return null;
    final clientSessionId = json['clientSessionId'] as String?;
    if (kind == SyncJobKind.finalize && clientSessionId == null) return null;
    final rollupJson = json['rollup'];
    return SyncJob(
      kind: kind,
      clip: clip,
      title: json['title'] as String?,
      mode: json['mode'] as String?,
      clientSessionId: clientSessionId,
      rollup: rollupJson is Map ? rollupJson.cast<String, Object?>() : null,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A durable "upload when online" queue on top of [SupabaseRoundSync].
///
/// Rounds are enqueued (persisted to disk) and then [process] drains them: it
/// runs each sync, drops the ones that land, keeps the ones that fail for a
/// later attempt, and stops early when signed out / offline. Triggered on app
/// start, on sign-in, and after each round / session — so nothing recorded is
/// lost, it just syncs whenever a connection and a session next exist.
class BackfillQueue {
  BackfillQueue({RoundSync? sync, File? file})
    : _sync = sync ?? SupabaseRoundSync() {
    _file = file;
  }

  /// The app-wide queue. Everything (start-up, auth, session) shares this so a
  /// single persisted file is the source of truth.
  static final BackfillQueue instance = BackfillQueue();

  /// A round syncs its keyframes from the video, which the retention sweep
  /// deletes after 7 days; past this a job can never complete, so it's dropped.
  static const Duration _maxAge = Duration(days: 14);

  final RoundSync _sync;

  File? _file;
  List<SyncJob> _jobs = <SyncJob>[];
  bool _loaded = false;
  bool _processing = false;
  Future<void> _writeChain = Future<void>.value();

  int get pending => _jobs.length;

  Future<void> enqueueRound(
    RoundClip clip, {
    String? title,
    String? mode,
  }) async {
    await _upsert(
      SyncJob(kind: SyncJobKind.round, clip: clip, title: title, mode: mode),
    );
  }

  Future<void> enqueueFinalize(
    String clientSessionId, {
    String? title,
    Map<String, Object?>? rollup,
  }) async {
    await _upsert(
      SyncJob(
        kind: SyncJobKind.finalize,
        clientSessionId: clientSessionId,
        title: title,
        rollup: rollup,
      ),
    );
  }

  Future<void> _upsert(SyncJob job) async {
    await _ensureLoaded();
    _jobs.removeWhere((j) => j.key == job.key);
    _jobs.add(job);
    DebugLog.instance.log('queued ${job.key} (${_jobs.length} pending)',
        tag: 'sync-queue');
    await _persist(); // durable before we ever attempt it
  }

  /// Attempt every pending job. [onOutcome] fires per job so a caller can
  /// surface the current round's result; every outcome is logged regardless.
  Future<void> process({
    void Function(SyncJob job, SyncOutcome outcome)? onOutcome,
  }) async {
    if (_processing) return; // one drain at a time
    _processing = true;
    try {
      await _ensureLoaded();
      if (_jobs.isEmpty) return;

      // Work off a snapshot; only the keys we finish are removed from the live
      // list at the end, so a round enqueued while we await here isn't dropped.
      final done = <String>{};
      for (final job in List<SyncJob>.of(_jobs)) {
        if (_isStale(job)) {
          done.add(job.key);
          DebugLog.instance.log('dropped stale ${job.key}', tag: 'sync-queue');
          continue;
        }
        final outcome = await _run(job);
        onOutcome?.call(job, outcome);
        DebugLog.instance
            .log('${job.key} → ${outcome.status.name}', tag: 'sync-queue');
        switch (outcome.status) {
          case SyncStatus.uploaded:
          case SyncStatus.skippedNoAnalysis:
            // Done, or the analysis is gone for good — either way, drop it.
            done.add(job.key);
          case SyncStatus.skippedSignedOut:
            // Offline / signed out: stop here, keep this job and the rest.
            _jobs.removeWhere((j) => done.contains(j.key));
            await _persist();
            DebugLog.instance.log(
              'signed out — ${_jobs.length} job(s) held',
              tag: 'sync-queue',
            );
            return;
          case SyncStatus.failed:
            job.attempts++; // left in place, retried on a later trigger
        }
      }
      _jobs.removeWhere((j) => done.contains(j.key));
      await _persist();
    } finally {
      _processing = false;
    }
  }

  Future<SyncOutcome> _run(SyncJob job) {
    return job.kind == SyncJobKind.round
        ? _sync.syncRound(job.clip!, title: job.title, mode: job.mode)
        : _sync.finalizeSession(
            job.clientSessionId!,
            title: job.title,
            rollup: job.rollup,
          );
  }

  bool _isStale(SyncJob job) {
    final clip = job.clip;
    if (clip == null) return false; // finalize jobs never expire on age
    return DateTime.now().difference(clip.recordedAt) > _maxAge;
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = _file ??= await _defaultFile();
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is List) {
          final loaded = <SyncJob>[];
          for (final entry in decoded) {
            if (entry is! Map) continue;
            final job = SyncJob.fromJson(entry.cast<String, Object?>());
            if (job != null) loaded.add(job);
          }
          _jobs = loaded;
        }
      }
    } on Object catch (error) {
      DebugLog.instance.log('load failed: $error', tag: 'sync-queue');
      debugPrint('Backfill queue load failed: $error');
    }
  }

  Future<File> _defaultFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/sync_queue.json');
  }

  Future<void> _persist() {
    final file = _file;
    if (file == null) return Future<void>.value();
    final payload = jsonEncode(<Map<String, Object?>>[
      for (final job in _jobs) job.toJson(),
    ]);
    _writeChain = _writeChain.then((_) async {
      try {
        await file.writeAsString(payload);
      } on Object catch (error) {
        debugPrint('Backfill queue write failed: $error');
      }
    });
    return _writeChain;
  }
}
