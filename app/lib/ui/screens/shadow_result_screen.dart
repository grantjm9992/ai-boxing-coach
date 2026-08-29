import 'package:flutter/material.dart';

import '../../analysis/round_analysis.dart';
import '../../analysis/session_type.dart';
import '../../domain/shadow_round.dart';
import '../../services/session_history_store.dart';
import '../theme.dart';
import 'round_capture_screen.dart';

/// Runs a standalone shadow-boxing round: framing check + count-in + record
/// (via [RoundCaptureScreen]), analyse, save it to History/Progress, then show
/// the feedback. Entry point from the home menu.
///
/// [store] is injectable for tests; production uses the default local store.
Future<void> startShadowRound(
  BuildContext context, {
  Duration duration = const Duration(minutes: 2),
  SessionHistoryStore? store,
  DateTime Function()? now,
}) async {
  final capture = await Navigator.of(context).push<RoundCaptureResult>(
    MaterialPageRoute<RoundCaptureResult>(
      builder: (_) => RoundCaptureScreen(
        title: 'Shadow boxing',
        framingSubtitle:
            'A shadow round coming up. Get your whole body in frame — head to '
            'feet — so the coach can read your work.',
        sessionType: SessionType.shadowBoxing,
        maxDuration: duration,
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

  final at = (now ?? DateTime.now)();
  final record = shadowSessionRecord(
    analysis,
    durationMs: capture.durationMs,
    sessionId: 'shadow_${at.millisecondsSinceEpoch}',
    completedAt: at,
  );
  await (store ?? SessionHistoryStore()).save(record);

  if (!context.mounted) return;
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => ShadowResultScreen(analysis: analysis),
    ),
  );
}

/// The feedback for a completed shadow round.
class ShadowResultScreen extends StatelessWidget {
  const ShadowResultScreen({super.key, required this.analysis});

  final RoundAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final corrections = analysis.correctionPriorities;
    return Scaffold(
      appBar: AppBar(title: const Text('Shadow round')),
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
          if (corrections.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            const _Header('Top things to fix'),
            const SizedBox(height: 8),
            for (final c in corrections.take(3))
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
