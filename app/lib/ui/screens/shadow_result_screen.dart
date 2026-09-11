import 'package:flutter/material.dart';

import '../../analysis/round_analysis.dart';
import '../../analysis/session_type.dart';
import '../../domain/round_clip.dart';
import '../../domain/shadow_round.dart';
import '../../services/clip_store.dart';
import '../../services/session_history_store.dart';
import '../../services/sync/backfill_queue.dart';
import '../../services/sync/round_sync.dart';
import '../theme.dart';
import 'round_capture_screen.dart';
import 'round_review_screen.dart' show saveClipVideo;

/// Runs a standalone shadow-boxing round: framing check + count-in + record
/// (via [RoundCaptureScreen]), analyse, save it to History/Progress, then show
/// the feedback. Entry point from the home menu.
///
/// [store] is injectable for tests; production uses the default local store.
Future<void> startShadowRound(
  BuildContext context, {
  Duration duration = const Duration(minutes: 2),
  SessionHistoryStore? store,
  ClipStore? clipStore,
  SupabaseRoundSync? sync,
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
        // Keep the video + run the full analyzer (AI + keyframes) so this round
        // reaches parity with a session round in History.
        clipStore: clips,
        sessionId: sessionId,
      ),
    ),
  );
  if (capture == null || !context.mounted) return;

  final analysis = capture.analysis;
  if (analysis == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Couldn't analyse that round — check your framing and lighting and "
          'try again.',
        ),
      ),
    );
    return;
  }

  final record = shadowSessionRecord(
    analysis,
    durationMs: capture.durationMs,
    sessionId: sessionId,
    completedAt: at,
  );
  await (store ?? SessionHistoryStore()).save(record);

  // Best-effort cloud sync of the round (pose + AI + keyframes) so opening it
  // from History shows the same rich detail as a session round. Durable queue:
  // retries on a later launch if offline / signed out — nothing is lost.
  final clip = capture.clip;
  if (clip != null) {
    final queue =
        sync != null ? BackfillQueue(sync: sync) : BackfillQueue.instance;
    await queue.enqueueRound(
      clip,
      title: 'Shadow boxing',
      mode: analysis.aiReport != null ? 'keyframe' : 'offline',
    );
    queue.process().ignore();
  }

  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ShadowResultScreen(analysis: analysis, clip: clip),
    ),
  );
}

/// The feedback for a completed shadow round.
class ShadowResultScreen extends StatelessWidget {
  const ShadowResultScreen({super.key, required this.analysis, this.clip});

  final RoundAnalysis analysis;

  /// The saved round video, if it was kept — enables "Save video to phone".
  final RoundClip? clip;

  @override
  Widget build(BuildContext context) {
    final corrections = analysis.correctionPriorities;
    final coaching = analysis.modelCoaching;
    final roundClip = clip;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Shadow round'),
        actions: <Widget>[
          if (roundClip != null)
            IconButton(
              icon: const Icon(Icons.save_alt),
              tooltip: 'Save video to phone',
              onPressed: () => saveClipVideo(context, roundClip),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          const _Saved(),
          const SizedBox(height: 16),
          const _Header('Round summary'),
          const SizedBox(height: 6),
          Text(
            analysis.overallSummary,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 16,
              height: 1.4,
            ),
          ),
          if (coaching != null && coaching.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            const _Header('Coach'),
            const SizedBox(height: 6),
            Text(
              coaching.trim(),
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                height: 1.4,
              ),
            ),
          ],
          if (corrections.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            const _Header('Things to fix'),
            const SizedBox(height: 8),
            for (final c in corrections)
              _Bullet('${c.priority}. ${c.description}'),
          ],
          if (analysis.positiveNotes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            const _Header('What looked good'),
            const SizedBox(height: 8),
            for (final note in analysis.positiveNotes.take(3)) _Bullet(note),
          ],
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(context).pop();
              await startShadowRound(context);
            },
            icon: const Icon(Icons.replay),
            label: const Text('Another round'),
          ),
        ],
      ),
    );
  }
}

class _Saved extends StatelessWidget {
  const _Saved();

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      const Icon(Icons.check_circle, color: AppTheme.rest, size: 18),
      const SizedBox(width: 8),
      Text(
        'Saved to your history',
        style: TextStyle(color: AppTheme.rest, fontWeight: FontWeight.w600),
      ),
    ],
  );
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: AppTheme.textSecondary,
      fontSize: 12,
      fontWeight: FontWeight.w700,
      letterSpacing: 0.8,
    ),
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Padding(
          padding: EdgeInsets.only(top: 6, right: 10),
          child: Icon(Icons.circle, size: 6, color: AppTheme.accent),
        ),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              height: 1.35,
            ),
          ),
        ),
      ],
    ),
  );
}
