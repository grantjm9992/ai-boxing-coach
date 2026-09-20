import 'package:flutter/material.dart';

import '../analysis/drill.dart';
import '../analysis/round_analysis.dart';
import '../domain/round_clip.dart';
import 'ai/ai_settings_store.dart';
import 'ai/coach_vision_model.dart';
import 'debug_log.dart';
import 'frame_grabber.dart';
import 'profile_store.dart';
import 'round_analyzer.dart';
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
    RoundAnalysis? analysis;
    try {
      final built = analyzer ?? await _buildAnalyzer();
      final profile = await const ProfileStore().load();
      analysis =
          await built.analyse(clip, drill: drill, mode: profile.analysisMode);

      final q = queue ?? BackfillQueue.instance;
      await q.enqueueRound(
        clip,
        title: label,
        mode: analysis?.aiReport != null ? 'keyframe' : 'offline',
      );
      if (finalizeRollup != null) {
        await q.enqueueFinalize(clip.sessionId,
            title: label, rollup: finalizeRollup);
      }
      q.process().ignore();
    } on Object catch (error) {
      DebugLog.instance.log('background analysis failed: $error', tag: 'bg');
    } finally {
      _mark(key, false);
    }
    _toast(analysis != null
        ? '${label ?? 'Round'} analysed — open History to review'
        : "${label ?? 'Round'} couldn't be analysed — tap the round to retry");
  }

  Future<RoundAnalyzer> _buildAnalyzer() async {
    final profile = await const ProfileStore().load();
    final config = await const AiSettingsStore().load();
    final visionModel =
        profile.analysisMode.usesAi ? resolveCoachVisionModel(config: config) : null;
    return visionModel != null
        ? RoundAnalyzer(visionModel: visionModel, frameGrabber: PluginFrameGrabber())
        : RoundAnalyzer();
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
