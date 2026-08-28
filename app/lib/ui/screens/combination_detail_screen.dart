import 'package:flutter/material.dart';

import '../../analysis/drill_matching.dart';
import '../../data/combination_library.dart';
import '../theme.dart';
import 'combination_drill_screen.dart';

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
    this.onStartDrill,
  });

  final CombinationDef combo;
  final DrillResult? result;

  /// Test seam: overrides launching the live recorder when "Start drill" is
  /// tapped. Production leaves this null and pushes [CombinationDrillScreen].
  final VoidCallback? onStartDrill;

  @override
  State<CombinationDetailScreen> createState() =>
      _CombinationDetailScreenState();
}

class _CombinationDetailScreenState extends State<CombinationDetailScreen> {
  DrillResult? _result;

  @override
  void initState() {
    super.initState();
    _result = widget.result;
  }

  Future<void> _startDrill() async {
    if (widget.onStartDrill != null) {
      widget.onStartDrill!();
      return;
    }
    final result = await Navigator.of(context).push<DrillResult>(
      MaterialPageRoute<DrillResult>(
        builder: (_) => CombinationDrillScreen(combo: widget.combo),
      ),
    );
    if (result != null && mounted) {
      setState(() => _result = result);
    }
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
            _DrillResultView(result: result),
          ],
          const SizedBox(height: 28),
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
  const _DrillResultView({required this.result});

  final DrillResult result;

  @override
  Widget build(BuildContext context) {
    final avg = result.averageScore;
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
        const SizedBox(height: 12),
        for (var i = 0; i < result.attempts.length; i++)
          _AttemptRow(index: i + 1, attempt: result.attempts[i]),
      ],
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
