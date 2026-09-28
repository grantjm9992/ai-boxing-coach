import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/analysis_progress.dart';
import '../format.dart';
import '../theme.dart';

/// Shows where a round's analysis is while the user waits: each stage of the
/// pipeline as a step (done, current, or to come), a progress bar for the
/// stages that can measure themselves, the time elapsed, a rough time left for
/// the current stage, and a reminder that they don't have to wait here.
///
/// A pose pass on a 2–3 minute round takes a few minutes and a Full AI review
/// a couple more, so a bare spinner reads as "stuck"; naming the stage and
/// showing it move is what makes the wait tolerable.
class AnalysisProgressCard extends StatefulWidget {
  const AnalysisProgressCard({
    super.key,
    required this.progress,
    this.showLeaveHint = true,
  });

  final AnalysisProgress progress;

  /// Whether to mention the analysis carries on if they leave the screen —
  /// true for background analysis, false for an on-screen re-run.
  final bool showLeaveHint;

  @override
  State<AnalysisProgressCard> createState() => _AnalysisProgressCardState();
}

class _AnalysisProgressCardState extends State<AnalysisProgressCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Elapsed time and the estimate move every second even when no progress
    // event arrives (the model reviewing reports nothing until it's done).
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.progress;
    final stages = progress.stages;
    final currentIndex = stages.indexOf(progress.stage);
    final now = DateTime.now();
    final elapsed = now.difference(progress.startedAt);
    final remaining = progress.stageRemaining(now: now);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const _Pulse(),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Analysing your round',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                TimeFormat.clock(elapsed),
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < stages.length; i++)
            _StepRow(
              stage: stages[i],
              state: i < currentIndex
                  ? _StepState.done
                  : i == currentIndex
                  ? _StepState.current
                  : _StepState.upcoming,
              fraction: i == currentIndex ? progress.fraction : null,
              remaining: i == currentIndex ? remaining : null,
            ),
          if (widget.showLeaveHint) ...<Widget>[
            const SizedBox(height: 6),
            const Text(
              "You can leave this screen — it keeps going and we'll let you "
              'know when your feedback is ready.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

enum _StepState { done, current, upcoming }

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.stage,
    required this.state,
    this.fraction,
    this.remaining,
  });

  final AnalysisStage stage;
  final _StepState state;
  final double? fraction;
  final Duration? remaining;

  @override
  Widget build(BuildContext context) {
    final current = state == _StepState.current;
    final Widget icon = switch (state) {
      _StepState.done =>
        const Icon(Icons.check_circle, size: 20, color: AppTheme.rest),
      _StepState.current => const SizedBox(
        width: 20,
        height: 20,
        child: Padding(
          padding: EdgeInsets.all(2),
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: AppTheme.accent,
          ),
        ),
      ),
      _StepState.upcoming => Icon(
        Icons.radio_button_unchecked,
        size: 20,
        color: AppTheme.textSecondary.withValues(alpha: 0.5),
      ),
    };
    final percent = fraction == null ? null : (fraction!.clamp(0, 1) * 100).round();
    final trailing = !current
        ? null
        : <String>[
            if (percent != null) '$percent%',
            if (remaining != null) '~${_roughly(remaining!)} left',
          ].join(' · ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              icon,
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stage.label,
                  style: TextStyle(
                    fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                    color: state == _StepState.upcoming
                        ? AppTheme.textSecondary
                        : AppTheme.textPrimary,
                  ),
                ),
              ),
              if (trailing != null && trailing.isNotEmpty)
                Text(
                  trailing,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
            ],
          ),
          if (current) ...<Widget>[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 30),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  // Indeterminate when the stage can't measure itself.
                  value: fraction == null || fraction == 0 ? null : fraction,
                  minHeight: 6,
                  backgroundColor: AppTheme.surfaceAlt,
                  color: AppTheme.accent,
                ),
              ),
            ),
            if (_hint(stage) case final hint?) ...<Widget>[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Text(
                  hint,
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// A line on what's happening in the stages that can't show a percentage.
  static String? _hint(AnalysisStage stage) => switch (stage) {
    AnalysisStage.reviewing =>
      'Watching the whole round — usually a minute or two.',
    AnalysisStage.uploading => 'Keep the app open until the upload finishes.',
    _ => null,
  };

  static String _roughly(Duration d) {
    if (d.inSeconds < 60) return '${(d.inSeconds / 5).ceil() * 5}s';
    final minutes = (d.inSeconds / 60).round();
    return '$minutes min';
  }
}

/// A softly pulsing dot — "alive", without another spinner.
class _Pulse extends StatefulWidget {
  const _Pulse();

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
      child: Container(
        width: 10,
        height: 10,
        decoration: const BoxDecoration(
          color: AppTheme.accent,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// A compact pill for lists (History): the current stage and its percentage.
class AnalysisProgressBadge extends StatelessWidget {
  const AnalysisProgressBadge({super.key, required this.progress});

  final AnalysisProgress progress;

  @override
  Widget build(BuildContext context) {
    final f = progress.fraction;
    final label = f == null || f == 0
        ? progress.stage.label
        : '${progress.stage.label} · ${(f.clamp(0, 1) * 100).round()}%';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.6,
              color: AppTheme.accent,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
  }
}
