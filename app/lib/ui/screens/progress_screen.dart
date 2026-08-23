import 'package:flutter/material.dart';

import '../../domain/progress_stats.dart';
import '../../domain/skill_category.dart';
import '../../services/session_history_store.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/category_widgets.dart';

/// The Progress view: whether the boxer is actually getting better, rolled up
/// from every analysed round. Guard consistency and punch volume over time, the
/// corrections that keep coming back, and all-time training totals — all from
/// real analysis, so a session that wasn't analysed just doesn't move a line.
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({this.store, super.key});

  final SessionHistoryStore? store;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late final SessionHistoryStore _store = widget.store ?? SessionHistoryStore();
  late final Future<ProgressStats> _stats =
      _store.list().then(ProgressStats.from);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Progress')),
      body: FutureBuilder<ProgressStats>(
        future: _stats,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = snapshot.data;
          if (stats == null || stats.isEmpty) {
            return const _Empty(
              'No training logged yet.\nFinish a session and your trends show up here.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: _sections(stats),
          );
        },
      ),
    );
  }

  List<Widget> _sections(ProgressStats s) {
    final widgets = <Widget>[
      _StatRow(stats: s),
      const SizedBox(height: 24),
    ];

    if (!s.hasAnalysis) {
      widgets.add(
        const _Note(
          'Trends need analysed rounds. Train a technical round with the camera '
          'on and your guard, punch volume and recurring flags start tracking here.',
        ),
      );
      return widgets;
    }

    widgets.addAll(<Widget>[
      _TrendCard(
        title: 'Guard consistency',
        subtitle: 'Hands back after you punch',
        series: s.guardReturn,
        format: _asPercent,
        deltaUnit: 'pts',
        deltaScale: 100,
        colorByDirection: true,
        fullScale: 1.0, // a rate: bars read against a fixed 0–100%
      ),
      const SizedBox(height: 16),
      _TrendCard(
        title: 'Punch volume',
        subtitle: 'Punches thrown per session',
        series: s.punchVolume,
        format: (v) => v.round().toString(),
        deltaUnit: '',
        deltaScale: 1,
        colorByDirection: false,
      ),
      const SizedBox(height: 24),
    ]);

    if (s.recurringErrors.isNotEmpty) {
      widgets.addAll(<Widget>[
        const _SectionTitle('Recurring flags'),
        const SizedBox(height: 4),
        const _Caption('The corrections that keep coming up. Pick the top one for your next session.'),
        const SizedBox(height: 14),
        _RecurringFlags(errors: s.recurringErrors),
        const SizedBox(height: 24),
      ]);
    }

    if (s.categorySeconds.isNotEmpty) {
      widgets.addAll(<Widget>[
        const _SectionTitle('All-time balance'),
        const SizedBox(height: 4),
        const _Caption('Weighted working minutes across every session.'),
        const SizedBox(height: 14),
        CategoryBalance(breakdown: _balance(s.categorySeconds), maxRows: 14),
      ]);
    }

    return widgets;
  }

  static String _asPercent(double rate) => '${(rate * 100).round()}%';

  Map<SkillCategory, Duration> _balance(Map<String, int> seconds) {
    final entries = seconds.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return <SkillCategory, Duration>{
      for (final e in entries)
        ?SkillCategory.fromKey(e.key): Duration(seconds: e.value),
    };
  }
}

/// The headline totals: sessions, analysed rounds, work time, punches.
class _StatRow extends StatelessWidget {
  const _StatRow({required this.stats});
  final ProgressStats stats;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _StatTile(value: '${stats.sessionCount}', label: 'Sessions'),
      _StatTile(value: '${stats.analysedRoundCount}', label: 'Rounds analysed'),
      _StatTile(
        value: TimeFormat.minutes(Duration(seconds: stats.totalWorkSeconds)),
        label: 'Work time',
      ),
      if (stats.totalPunches > 0)
        _StatTile(value: '${stats.totalPunches}', label: 'Punches'),
    ];
    return Wrap(spacing: 12, runSpacing: 12, children: tiles);
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}

/// A titled card: current value, a trend chip vs the baseline, and a bar
/// sparkline of the whole series.
class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.title,
    required this.subtitle,
    required this.series,
    required this.format,
    required this.deltaUnit,
    required this.deltaScale,
    required this.colorByDirection,
    this.fullScale,
  });

  final String title;
  final String subtitle;
  final TrendSeries series;
  final String Function(double) format;
  final String deltaUnit;
  final double deltaScale;
  final bool colorByDirection;

  /// When set, bars are drawn against this fixed maximum (e.g. 1.0 for a rate)
  /// rather than the series' own peak.
  final double? fullScale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5)),
                  ],
                ),
              ),
              if (series.latest != null)
                Text(
                  format(series.latest!),
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _MiniBars(series: series, fullScale: fullScale),
          const SizedBox(height: 12),
          _TrendChip(
            delta: series.delta,
            scale: deltaScale,
            unit: deltaUnit,
            colorByDirection: colorByDirection,
          ),
        ],
      ),
    );
  }
}

/// A dependency-free bar sparkline. The latest bar is emphasised.
class _MiniBars extends StatelessWidget {
  const _MiniBars({required this.series, this.fullScale});
  final TrendSeries series;
  final double? fullScale;

  @override
  Widget build(BuildContext context) {
    final points = series.points;
    final peak = (fullScale ?? series.max).clamp(1e-9, double.infinity);
    return SizedBox(
      height: 72,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (var i = 0; i < points.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: FractionallySizedBox(
                    heightFactor: (points[i].value / peak).clamp(0.03, 1.0),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: i == points.length - 1
                            ? AppTheme.accent
                            : AppTheme.accent.withValues(alpha: 0.35),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The up/down change since the first session, coloured by direction when the
/// direction has a clear "better" (guard: up is good; punch volume: neutral).
class _TrendChip extends StatelessWidget {
  const _TrendChip({
    required this.delta,
    required this.scale,
    required this.unit,
    required this.colorByDirection,
  });

  final double? delta;
  final double scale;
  final String unit;
  final bool colorByDirection;

  @override
  Widget build(BuildContext context) {
    final d = delta;
    if (d == null) {
      return const _Pill(
        icon: Icons.timeline,
        text: 'Building your baseline',
        color: AppTheme.textSecondary,
      );
    }
    final scaled = (d * scale).round();
    final up = scaled > 0;
    final flat = scaled == 0;
    final color = !colorByDirection
        ? AppTheme.accent
        : flat
            ? AppTheme.textSecondary
            : up
                ? AppTheme.rest
                : AppTheme.work;
    final sign = up ? '+' : '';
    final suffix = unit.isEmpty ? '' : ' $unit';
    final icon = flat
        ? Icons.trending_flat
        : up
            ? Icons.trending_up
            : Icons.trending_down;
    return _Pill(
      icon: icon,
      text: flat ? 'No change since your first session' : '$sign$scaled$suffix since your first session',
      color: color,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text, required this.color});
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// The recurring corrections, as labelled proportion bars.
class _RecurringFlags extends StatelessWidget {
  const _RecurringFlags({required this.errors});
  final List<ErrorTally> errors;

  @override
  Widget build(BuildContext context) {
    final peak = errors.first.count.clamp(1, 1 << 30);
    return Column(
      children: <Widget>[
        for (var i = 0; i < errors.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: <Widget>[
                if (i == 0)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.priority_high, size: 16, color: AppTheme.accent),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(errors[i].label, style: const TextStyle(fontSize: 14)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: errors[i].count / peak,
                          minHeight: 6,
                          backgroundColor: AppTheme.surfaceAlt,
                          valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${errors[i].count}×',
                  style: const TextStyle(color: AppTheme.textSecondary, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      );
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12.5, height: 1.4),
      );
}

class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.surfaceAlt),
        ),
        child: Text(text, style: const TextStyle(color: AppTheme.textSecondary, height: 1.45)),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.5),
          ),
        ),
      );
}
