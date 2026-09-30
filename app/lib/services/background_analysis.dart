import 'package:flutter/material.dart';

import '../analysis/analysis_mode.dart';
import '../analysis/drill.dart';
import '../analysis/round_analysis.dart';
import '../domain/round_clip.dart';
import 'ai/ai_settings_store.dart';
import 'ai/vision_model.dart';
import 'analysis_progress.dart';
import 'analysis_store.dart';
import 'debug_log.dart';
import 'keep_awake.dart';
import 'profile_store.dart';
import 'round_analyzer.dart';
import 'round_coach.dart';
import 'sync/backfill_queue.dart';

/// Runs a round's analysis off the critical path so the user can start the next
/// round immediately instead of waiting for pose + AI + upload to finish.
///
/// A round is recorded and saved synchronously (fast); the slow work — pose
/// estimation, the AI coaching call, keyframe upload — is handed here and runs
/// detached. When it finishes, a toast tells the user (via [messengerKey], set
/// on the root [MaterialApp]). The analysis is written to the AnalysisStore by
/// the analyzer, so History / the review screen pick it up whenever they open.
class BackgroundAnalysis {
  BackgroundAnalysis._();
  static final BackgroundAnalysis instance = BackgroundAnalysis._();

  /// Set as the MaterialApp's scaffoldMessengerKey so completion toasts can be
  /// shown no matter which screen the user is on (or if they've left to record
  /// another round).
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  /// Clip keys (`sessionId/segmentIndex`) currently being analysed, so UI can
  /// show "Analysing…" instead of offering a redundant re-run.
  final ValueNotifier<Set<String>> running = ValueNotifier<Set<String>>(<String>{});

  /// Where each running analysis is (stage + fraction), keyed like [running],
  /// for the progress card and History badge.
  final ValueNotifier<Map<String, AnalysisProgress>> progress =
      ValueNotifier<Map<String, AnalysisProgress>>(<String, AnalysisProgress>{});

  /// The running analysis of [clip], or null when it isn't running.
  AnalysisProgress? progressFor(RoundClip clip) => progress.value[keyFor(clip)];

  /// The running analysis of any round in [sessionId], or null.
  AnalysisProgress? progressForSession(String sessionId) {
    for (final entry in progress.value.entries) {
      if (entry.key.startsWith('$sessionId/')) return entry.value;
    }
    return null;
  }

  static String keyFor(RoundClip clip) => '${clip.sessionId}/${clip.segmentIndex}';

  bool isRunning(RoundClip clip) => running.value.contains(keyFor(clip));

  /// Analyse [clip] in the background, then sync it and toast the result. Safe
  /// to call unawaited. [label] is the History/session title; [finalizeRollup],
  /// when given, is enqueued so the cloud session carries its totals.
  Future<void> analyse(
    RoundClip clip, {
    required DrillContext drill,
    String? label,
    Map<String, Object?>? finalizeRollup,
    BackfillQueue? queue,
    RoundAnalyzer? analyzer,
  }) async {
    final key = keyFor(clip);
    _mark(key, true);
    // Pose + AI take minutes; if the phone auto-locks meanwhile, the OS
    // throttles the app and cuts its network, stalling the run.
    final releaseAwake = KeepAwake.instance.acquire('analysing $key');
    RoundAnalysis? analysis;
    AnalysisMode? mode;
    try {
      final built = analyzer ?? await _buildAnalyzer();
      final profile = await const ProfileStore().load();
      mode = profile.analysisMode;
      _setProgress(key, AnalysisProgress.start(mode));
      analysis = await built.analyse(
        clip,
        drill: drill,
        mode: mode,
        onProgress: (stage, fraction) {
          final current = progress.value[key];
          if (current != null) {
            _setProgress(key, current.advance(stage, fraction));
          }
        },
      );

      final q = queue ?? BackfillQueue.instance;
      await q.enqueueRound(
        clip,
        title: label,
        // The chosen AI mode when the round got AI coaching; offline when
        // the AI step didn't run or produced nothing.
        mode: analysis?.modelCoaching != null && mode != null
            ? mode.value
            : AnalysisMode.offline.value,
      );
      if (finalizeRollup != null) {
        await q.enqueueFinalize(clip.sessionId,
            title: label, rollup: finalizeRollup);
      }
      q.process().ignore();
    } on Object catch (error) {
      DebugLog.instance.log('background analysis failed: $error', tag: 'bg');
    } finally {
      releaseAwake();
      _setProgress(key, null);
      _mark(key, false);
    }
    _toast(analysis != null
        ? '${label ?? 'Round'} analysed — open History to review'
        : "${label ?? 'Round'} couldn't be analysed — tap the round to retry");
  }

  /// The AI step alone, for a round whose pose + rules analysis is already
  /// saved — a combination drill, which is analysed on the spot so the drill
  /// result shows at once. Runs the profile's AI mode ([RoundCoach]) over the
  /// saved analysis and pose (no second tracking pass) and saves the enriched
  /// analysis back, so the drill screen and the review screen pick it up.
  ///
  /// Does nothing in offline mode or with no model available. Returns the
  /// enriched analysis, or null when there was none. [store], [coach] and
  /// [mode] are injectable for tests; production resolves them.
  Future<RoundAnalysis?> reviewWithAi(
    RoundClip clip, {
    required DrillContext drill,
    String? label,
    AnalysisStore? store,
    RoundCoach? coach,
    AnalysisMode? mode,
  }) async {
    final resolvedMode = mode ?? (await const ProfileStore().load()).analysisMode;
    if (!resolvedMode.usesAi) return null;
    final resolvedCoach = coach ??
        resolveRoundCoach(
          mode: resolvedMode,
          config: await const AiSettingsStore().load(),
        );
    if (!resolvedCoach.canCoach(resolvedMode)) return null;

    final saved = store ?? AnalysisStore();
    final analysis =
        await saved.loadAnalysis(clip.sessionId, clip.segmentIndex);
    final pose = await saved.loadPose(clip.sessionId, clip.segmentIndex);
    if (analysis == null || pose == null) return null;

    final key = keyFor(clip);
    _mark(key, true);
    final releaseAwake = KeepAwake.instance.acquire('AI review $key');
    _setProgress(
      key,
      AnalysisProgress.start(
        resolvedMode,
        stage: resolvedMode == AnalysisMode.fullFrame
            ? AnalysisStage.uploading
            : AnalysisStage.reviewing,
      ),
    );
    RoundAnalysis? enriched;
    String? failure;
    try {
      final coaching = await resolvedCoach.coach(
        mode: resolvedMode,
        videoPath: clip.path,
        analysis: analysis,
        drill: drill,
        durationMs: pose.durationMs,
        onProgress: (stage, fraction) {
          final current = progress.value[key];
          if (current != null) {
            _setProgress(key, current.advance(stage, fraction));
          }
        },
      );
      if (coaching != null) {
        final current = progress.value[key];
        if (current != null) {
          _setProgress(key, current.advance(AnalysisStage.saving, null));
        }
        enriched = coaching.applyTo(analysis, durationMs: pose.durationMs);
        await saved.save(
          clip.sessionId,
          clip.segmentIndex,
          analysis: enriched,
          sequence: pose,
        );
      }
    } on VisionModelException catch (error) {
      failure = error.message;
    } on Object catch (error) {
      failure = '$error';
    } finally {
      releaseAwake();
      _setProgress(key, null);
      _mark(key, false);
    }
    if (failure != null) {
      DebugLog.instance.log('AI review failed for $key: $failure', tag: 'bg');
    }
    _toast(enriched != null
        ? "${label ?? 'Drill'}: the AI coach's review is ready"
        : "${label ?? 'Drill'}: AI review unavailable"
            '${failure == null ? '' : ' — $failure'}');
    return enriched;
  }

  Future<RoundAnalyzer> _buildAnalyzer() async {
    final profile = await const ProfileStore().load();
    final config = await const AiSettingsStore().load();
    return RoundAnalyzer.withCoach(
      resolveRoundCoach(mode: profile.analysisMode, config: config),
    );
  }

  void _setProgress(String key, AnalysisProgress? value) {
    final next = Map<String, AnalysisProgress>.of(progress.value);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    progress.value = next;
  }

  void _mark(String key, bool active) {
    final next = Set<String>.of(running.value);
    if (active) {
      next.add(key);
    } else {
      next.remove(key);
    }
    running.value = next;
  }

  void _toast(String message) {
    messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
