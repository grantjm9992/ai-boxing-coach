import 'package:flutter/material.dart';

import '../../analysis/session_type.dart';
import '../../domain/shadow_round.dart';
import '../../services/background_analysis.dart';
import '../../services/clip_store.dart';
import '../../services/profile_store.dart';
import '../../services/session_history_store.dart';
import 'round_capture_screen.dart';
import 'round_review_screen.dart';

/// Runs a standalone shadow-boxing round: framing check + count-in + record
/// (via [RoundCaptureScreen]), then analyse it IN THE BACKGROUND so the user can
/// start the next round without waiting. The round is filed to History and the
/// user lands on the same review screen a session round uses — video with pose
/// overlay, corrections, AI coaching, save-video and re-run. A toast fires when
/// the background analysis finishes.
///
/// [store]/[clipStore] are injectable for tests; production uses the defaults.
Future<void> startShadowRound(
  BuildContext context, {
  Duration duration = const Duration(minutes: 2),
  SessionHistoryStore? store,
  ClipStore? clipStore,
  DateTime Function()? now,
}) async {
  final at = (now ?? DateTime.now)();
  final sessionId = 'shadow_${at.millisecondsSinceEpoch}';
  final clips = clipStore ?? ClipStore();

  final capture = await Navigator.of(context).push<RoundCaptureResult>(
    MaterialPageRoute<RoundCaptureResult>(
      builder: (_) => RoundCaptureScreen(
        title: 'Shadow boxing',
        framingSubtitle:
            'A shadow round coming up. Get your whole body in frame — head to '
            'feet — so the coach can read your work.',
        sessionType: SessionType.shadowBoxing,
        maxDuration: duration,
        // Keep the video and defer analysis: the slow pose+AI+upload runs in the
        // background so the next round can start immediately.
        clipStore: clips,
        sessionId: sessionId,
        deferAnalysis: true,
      ),
    ),
  );
  if (capture == null || !context.mounted) return;

  final clip = capture.clip;
  if (clip == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Couldn't record that round — check your camera and try again.",
        ),
      ),
    );
    return;
  }

  // File the session now (pending summary) so it shows in History immediately;
  // the background analysis + cloud sync fill in the detail.
  final record = shadowSessionRecord(
    null,
    durationMs: capture.durationMs,
    sessionId: sessionId,
    completedAt: at,
  );
  await (store ?? SessionHistoryStore()).save(record);

  // Analyse off the critical path: pose + AI + keyframes + cloud sync, with a
  // toast on completion. Not awaited — the user is free to start another round.
  final drill = (await const ProfileStore().load())
      .toDrill(sessionType: SessionType.shadowBoxing);
  BackgroundAnalysis.instance
      .analyse(clip,
          drill: drill,
          label: 'Shadow boxing',
          finalizeRollup: record.rollupJson)
      .ignore();

  if (!context.mounted) return;
  // Land on the same review the full session uses — watch back with the pose
  // overlay, corrections, AI, save video, and re-run. It reflects the
  // background analysis as it completes, and "Another round" lets the user go
  // again without waiting.
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => RoundReviewScreen(
        clipStore: clips,
        sessionId: sessionId,
        onAnotherRound: () => startShadowRound(context,
            duration: duration, store: store, clipStore: clipStore, now: now),
      ),
    ),
  );
}
