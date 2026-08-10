import 'package:flutter/material.dart';

import '../../analysis/round_analysis.dart';
import '../../domain/round_clip.dart';
import '../../domain/session_plan.dart';
import '../../services/clip_store.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/category_widgets.dart';
import 'round_review_screen.dart';

/// The end-of-session recap.
///
/// v0.1 keeps no history — session persistence arrives with the data model in
/// v0.5 — so this is the plan that was just run, not a record of it. It is
/// still worth showing: the balance view is the thing the athlete is meant to
/// act on when picking the next session.
class SessionSummaryScreen extends StatelessWidget {
  const SessionSummaryScreen({
    required this.plan,
    this.clipStore,
    this.sessionId,
    this.analyses = const <int, RoundAnalysis>{},
    super.key,
  });

  final SessionPlan plan;

  /// Present when the session recorded technical rounds (v0.5). Null in v0.1
  /// runs and when recording was off, in which case no review section shows.
  final ClipStore? clipStore;
  final String? sessionId;

  /// Per-round analyses produced this session, keyed by segment index.
  final Map<int, RoundAnalysis> analyses;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Session complete')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: const Text('Done'),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          Text(
            plan.template.name,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              _Stat(
                label: 'Total',
                value: TimeFormat.minutes(plan.totalDuration),
              ),
              _Stat(
                label: 'Working',
                value: TimeFormat.minutes(plan.workDuration),
              ),
              _Stat(label: 'Rounds', value: '${plan.roundCount}'),
            ],
          ),
          const SizedBox(height: 24),
          const _SectionTitle('Where the time went'),
          const SizedBox(height: 12),
          for (final phase in plan.activePhases)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppTheme.phaseColor(phase),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(phase.label)),
                  Text(
                    TimeFormat.minutes(plan.durationOf(phase)),
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          if (analyses.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            const _SectionTitle('Round feedback'),
            const SizedBox(height: 12),
            for (final entry in (analyses.entries.toList()
                  ..sort((a, b) => a.key.compareTo(b.key))))
              _RoundFeedbackCard(analysis: entry.value),
          ],
          if (clipStore != null && sessionId != null) ...<Widget>[
            const SizedBox(height: 24),
            const _SectionTitle('Recordings'),
            const SizedBox(height: 12),
            _RecordingsSection(
              clipStore: clipStore!,
              sessionId: sessionId!,
            ),
          ],
          const SizedBox(height: 24),
          const _SectionTitle('Category balance'),
          const SizedBox(height: 4),
          const Text(
            'Weighted working minutes. From v0.5 this rolls up into the weekly '
            'view the spec describes.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          CategoryBalance(breakdown: plan.categoryBreakdown, maxRows: 12),
          const SizedBox(height: 24),
          const _NextUpNote(),
        ],
      ),
    );
  }
}

class _RoundFeedbackCard extends StatelessWidget {
  const _RoundFeedbackCard({required this.analysis});

  final RoundAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(analysis.overallSummary, style: const TextStyle(height: 1.4)),
          for (final c in analysis.correctionPriorities)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.arrow_right, size: 18, color: AppTheme.accent),
                  Expanded(
                    child: Text(
                      c.description,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RecordingsSection extends StatelessWidget {
  const _RecordingsSection({required this.clipStore, required this.sessionId});

  final ClipStore clipStore;
  final String sessionId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<RoundClip>>(
      future: clipStore.listForSession(sessionId),
      builder: (context, snapshot) {
        final clips = snapshot.data ?? const <RoundClip>[];
        final count = clips.length;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                count == 0
                    ? 'No technical rounds were recorded.'
                    : '$count technical ${count == 1 ? 'round' : 'rounds'} '
                          'recorded. Kept for 7 days.',
                style: const TextStyle(color: AppTheme.textSecondary),
              ),
              if (count > 0) ...<Widget>[
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RoundReviewScreen(
                        clipStore: clipStore,
                        sessionId: sessionId,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.video_library_outlined),
                  label: const Text('Review rounds'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _NextUpNote extends StatelessWidget {
  const _NextUpNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Coming in v0.5', style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 6),
          Text(
            'Recording during the technical rounds, on-device pose estimation, '
            'and rule-based feedback on guard return, punch retraction, stance '
            'and head movement — delivered as audio in the rest between rounds.',
            style: TextStyle(
              color: AppTheme.textSecondary,
              height: 1.4,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 0.8,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
