import 'package:flutter/material.dart';

import '../../analysis/ai_review.dart';
import '../../analysis/checkpoint_evaluation.dart';
import '../../analysis/checkpoints.dart';
import '../../analysis/drill_matching.dart';
import '../../analysis/round_analysis.dart';
import '../../analysis/session_type.dart';
import '../../data/combination_library.dart';
import '../../domain/round_clip.dart';
import '../../services/analysis_progress.dart';
import '../../services/analytics.dart';
import '../../services/background_analysis.dart';
import '../../services/clip_store.dart';
import '../theme.dart';
import '../widgets/analysis_progress_card.dart';
import '../widgets/duration_selector.dart';
import 'round_capture_screen.dart';
import 'round_review_screen.dart';

/// A combination's detail + drill view (brief §15). Shows the sequence, the
/// coaching points and — once a drill round has been analysed — the per-attempt
/// and aggregate result.
///
/// [result] seeds the view (null = browse mode); running a drill from here
/// records a round, evaluates it, and updates the view with the fresh result.
class CombinationDetailScreen extends StatefulWidget {
  const CombinationDetailScreen({
    super.key,
    required this.combo,
    this.result,
    this.aiReview,
    this.onStartDrill,
  });

  final CombinationDef combo;
  final DrillResult? result;

  /// Seeds the drill's AI review alongside [result] (restoring a view, tests).
  final RoundAnalysis? aiReview;

  /// Test seam: overrides launching the live recorder when "Start drill" is
  /// tapped. Production leaves this null and pushes [CombinationDrillScreen].
  final VoidCallback? onStartDrill;

  @override
  State<CombinationDetailScreen> createState() =>
      _CombinationDetailScreenState();
}

class _CombinationDetailScreenState extends State<CombinationDetailScreen> {
  DrillResult? _result;
  Duration _duration = const Duration(minutes: 2);
  final ClipStore _clipStore = ClipStore();

  /// Session id of the last drill round recorded here, so it can be watched
  /// back / re-analysed like a session or shadow round.
  String? _lastSessionId;

  /// The last drill round's clip, while its background AI review may run.
  RoundClip? _lastClip;

  /// The last drill round's analysis once the AI review has landed (null
  /// until then, and in offline mode).
  RoundAnalysis? _aiReview;

  @override
  void initState() {
    super.initState();
    _result = widget.result;
    _aiReview = widget.aiReview;
    AnalyticsScope.instance.log(
      AnalyticsEvent.combinationSelected,
      <String, Object?>{'id': widget.combo.id},
    );
  }

  Future<void> _startDrill() async {
    if (widget.onStartDrill != null) {
      widget.onStartDrill!();
      return;
    }
    final combo = widget.combo;
    final sessionId = 'drill_${DateTime.now().millisecondsSinceEpoch}';
    final capture = await Navigator.of(context).push<RoundCaptureResult>(
      MaterialPageRoute<RoundCaptureResult>(
        builder: (_) => RoundCaptureScreen(
          title: 'Drill · ${combo.numberLabel}',
          framingSubtitle:
              'Get your whole body in frame, then throw ${combo.numberLabel} '
              'on repeat.',
          sessionType: SessionType.combinationDrill,
          maxDuration: _duration,
          focus: const <String>{'combinations'},
          notes: combo.numberLabel,
          // Graded against this combination's technique checkpoints.
          targetSequence: combo.numbers,
          // Keep the clip + persist the (pose-only) analysis so the drill round
          // can be watched back and re-analysed, like a session round.
          clipStore: _clipStore,
          sessionId: sessionId,
        ),
      ),
    );
    if (capture == null || !mounted) return;
    if (capture.clip != null) _lastSessionId = sessionId;
    final result = evaluateDrill(
      combo.numbers,
      capture.analysis?.combinationAnalyses ?? const [],
      checkpoints: capture.analysis?.checkpointTallies ?? const [],
    );
    for (final attempt in result.attempts) {
      AnalyticsScope.instance.log(AnalyticsEvent.combinationAttemptDetected,
          <String, Object?>{'detected': attempt.detected.join('-')});
      AnalyticsScope.instance.log(
        attempt.sequenceMatch
            ? AnalyticsEvent.combinationMatchSuccess
            : AnalyticsEvent.combinationMatchFailure,
        <String, Object?>{'combo': combo.id},
      );
    }
    setState(() {
      _result = result;
      _lastClip = capture.clip;
      _aiReview = null;
    });
    _startAiReview(capture);
  }

  /// In an AI mode, the drill's AI review runs in the background over the
  /// round just analysed (BackgroundAnalysis.reviewWithAi) — the on-device
  /// result is already on screen. Offline mode: nothing happens.
  void _startAiReview(RoundCaptureResult capture) {
    final clip = capture.clip;
    final drill = capture.drill;
    if (clip == null || drill == null) return;
    BackgroundAnalysis.instance
        .reviewWithAi(
          clip,
          drill: drill,
          label: 'Drill ${widget.combo.numberLabel}',
        )
        .then((enriched) {
          if (!mounted || enriched == null) return;
          // Only if it's still the latest drill on screen.
          if (_lastClip?.sessionId != clip.sessionId) return;
          setState(() => _aiReview = enriched);
        })
        .ignore();
  }

  @override
  Widget build(BuildContext context) {
    final combo = widget.combo;
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: Text(combo.numberLabel)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          Text(
            combo.name,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            combo.difficulty.label,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 16),
          const _VideoPlaceholder(),
          const SizedBox(height: 16),
          _SequenceStrip(numbers: combo.numbers, names: combo.punchNames),
          const SizedBox(height: 20),
          Text(
            combo.description,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              height: 1.4,
            ),
          ),
          if (combo.checkpoints.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            const _SectionHeader('What the coach is looking for'),
            const SizedBox(height: 8),
            _CheckpointList(checkpoints: combo.checkpoints),
          ],
          if (combo.coachingPoints.isNotEmpty) ...<Widget>[
            const SizedBox(height: 24),
            const _SectionHeader('Coaching points'),
            const SizedBox(height: 8),
            for (final point in combo.coachingPoints) _Bullet(point),
          ],
          if (result != null) ...<Widget>[
            const SizedBox(height: 28),
            const _SectionHeader('Your drill'),
            const SizedBox(height: 8),
            _DrillResultView(
              result: result,
              clip: _lastClip,
              aiReview: _aiReview,
            ),
            if (_lastSessionId != null) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RoundReviewScreen(
                      clipStore: _clipStore,
                      sessionId: _lastSessionId!,
                    ),
                  ),
                ),
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('Watch round · re-analyse'),
              ),
            ],
          ],
          const SizedBox(height: 28),
          DurationSelector(
            value: _duration,
            onChanged: (d) => setState(() => _duration = d),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _startDrill,
            icon: const Icon(Icons.play_arrow),
            label: Text(result == null ? 'Start drill' : 'Drill again'),
          ),
        ],
      ),
    );
  }
}

class _VideoPlaceholder extends StatelessWidget {
  const _VideoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.ondemand_video_outlined,
                  color: AppTheme.textSecondary, size: 40),
              SizedBox(height: 8),
              Text(
                'Example video coming soon',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SequenceStrip extends StatelessWidget {
  const _SequenceStrip({required this.numbers, required this.names});

  final List<int> numbers;
  final List<String> names;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (var i = 0; i < numbers.length; i++) ...<Widget>[
            if (i > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 6),
                child: Icon(Icons.arrow_forward,
                    size: 16, color: AppTheme.textSecondary),
              ),
            _PunchChip(number: numbers[i], name: names[i]),
          ],
        ],
      ),
    );
  }
}

class _PunchChip extends StatelessWidget {
  const _PunchChip({required this.number, required this.name});

  final int number;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: <Widget>[
          Text(
            '$number',
            style: const TextStyle(
              color: AppTheme.accent,
              fontWeight: FontWeight.w700,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            name,
            style: const TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _DrillResultView extends StatelessWidget {
  const _DrillResultView({required this.result, this.clip, this.aiReview});

  final DrillResult result;

  /// The drill's clip — its background AI review, while running, shows here.
  final RoundClip? clip;

  /// The drill's analysis after the AI review (null until it lands).
  final RoundAnalysis? aiReview;

  /// The checkpoints the AI's shown findings failed; null when there's no
  /// structured AI review (offline, key-moment mode, or not back yet).
  Set<String>? get _aiFlagged {
    final report = aiReview?.aiReport;
    if (report == null) return null;
    return <String>{
      for (final finding in AiReview.shownFindings(report))
        if (finding.checkpoint != null) finding.checkpoint!,
    };
  }

  @override
  Widget build(BuildContext context) {
    final avg = result.averageScore;
    final aiFlagged = _aiFlagged;
    final coaching = aiReview?.modelCoaching;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          result.totalAttempts == 0
              ? 'No attempts detected. Make sure your whole body is in frame and '
                  'throw the combination a few times.'
              : '${result.matchedCount}/${result.totalAttempts} attempts threw '
                  'the right sequence'
                  '${avg == null ? '' : ' · avg technique ${avg.round()}/100'}.',
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
        ),
        if (result.checkpoints.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          const _SectionHeader('Checkpoints'),
          const SizedBox(height: 8),
          for (final tally in result.checkpoints)
            _CheckpointRow(
              tally: tally,
              aiFlagged: aiFlagged?.contains(tally.checkpoint.id),
            ),
        ],
        if (clip case final drillClip?)
          ValueListenableBuilder<Map<String, AnalysisProgress>>(
            valueListenable: BackgroundAnalysis.instance.progress,
            builder: (context, _, _) {
              final running =
                  BackgroundAnalysis.instance.progressFor(drillClip);
              if (running == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Row(
                  children: <Widget>[
                    AnalysisProgressBadge(progress: running),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'The AI coach is reviewing this drill.',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        if (coaching != null && coaching.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          const _SectionHeader('AI coach'),
          const SizedBox(height: 8),
          Text(
            coaching,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              height: 1.4,
            ),
          ),
        ],
        const SizedBox(height: 12),
        for (var i = 0; i < result.attempts.length; i++)
          _AttemptRow(index: i + 1, attempt: result.attempts[i]),
      ],
    );
  }
}

/// Colour for a checkpoint held on some reps but not most.
const Color _partial = Color(0xFFE0A33A);

/// The drill's checkpoints grouped by punch, as the standard to aim for.
class _CheckpointList extends StatelessWidget {
  const _CheckpointList({required this.checkpoints});

  final List<DrillCheckpoint> checkpoints;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    String? punch;
    for (final dc in checkpoints) {
      if (dc.punchName != punch) {
        punch = dc.punchName;
        children.add(Padding(
          padding: EdgeInsets.only(top: children.isEmpty ? 0 : 10, bottom: 6),
          child: Text(
            punch,
            style: const TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ));
      }
      children.add(_Bullet(
        dc.checkpoint.label,
        detail: dc.checkpoint.detail,
        tag: dc.checkpoint.measurable ? null : 'AI review',
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

/// One checkpoint's result across the drill round: passed/graded reps, or a
/// note that the AI review grades it from the video.
class _CheckpointRow extends StatelessWidget {
  const _CheckpointRow({required this.tally, this.aiFlagged});

  final CheckpointTally tally;

  /// The AI review's verdict: true = it flagged this checkpoint, false = it
  /// reviewed the drill and didn't, null = no structured AI review.
  final bool? aiFlagged;

  @override
  Widget build(BuildContext context) {
    final rate = tally.passRate;
    final ai = aiFlagged;
    final (IconData icon, Color color) = switch ((rate, ai)) {
      // Not gradable on-device: the AI's verdict, when there is one.
      (null, true) => (Icons.cancel, AppTheme.accent),
      (null, false) => (Icons.check_circle, AppTheme.rest),
      (null, null) => (Icons.videocam_outlined, AppTheme.textSecondary),
      (final double r, _) when r >= 0.8 => (Icons.check_circle, AppTheme.rest),
      (final double r, _) when r >= 0.5 => (Icons.error_outline, _partial),
      _ => (Icons.cancel, AppTheme.accent),
    };
    final String trailing;
    if (rate != null) {
      trailing = '${tally.passed}/${tally.graded}'
          '${ai == true ? ' · AI flagged' : ''}';
    } else if (ai != null) {
      trailing = ai ? 'AI: missed' : 'AI: OK';
    } else {
      trailing =
          tally.checkpoint.checkpoint.measurable ? 'Not seen' : 'AI review';
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${tally.checkpoint.punchName} · ${tally.checkpoint.checkpoint.label}',
              style: const TextStyle(color: AppTheme.textPrimary, height: 1.3),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            trailing,
            style: TextStyle(
              color: rate == null && ai == null ? AppTheme.textSecondary : color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _AttemptRow extends StatelessWidget {
  const _AttemptRow({required this.index, required this.attempt});

  final int index;
  final DrillAttempt attempt;

  @override
  Widget build(BuildContext context) {
    final color = attempt.sequenceMatch ? AppTheme.rest : AppTheme.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Icon(
            attempt.sequenceMatch ? Icons.check_circle : Icons.cancel,
            color: color,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Attempt $index: ${attempt.detected.join('-')}',
              style: const TextStyle(color: AppTheme.textPrimary),
            ),
          ),
          if (attempt.sequenceMatch)
            Text(
              '${attempt.executionScore}/100',
              style: TextStyle(color: color, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

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
  const _Bullet(this.text, {this.detail, this.tag});

  final String text;

  /// A second, quieter line under [text].
  final String? detail;

  /// A small pill after [text] (e.g. "AI review").
  final String? tag;

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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text.rich(
                TextSpan(
                  text: text,
                  children: <InlineSpan>[
                    if (tag != null)
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceAlt,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            tag!,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
              if (detail != null) ...<Widget>[
                const SizedBox(height: 2),
                Text(
                  detail!,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
