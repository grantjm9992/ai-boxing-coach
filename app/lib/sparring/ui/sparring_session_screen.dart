import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../analysis/sparring_analyzer.dart';
import '../data/sparring_store.dart';
import '../data/sparring_sync.dart';
import '../jobs/sparring_jobs.dart';
import '../model/fighter.dart';
import '../model/sparring_session.dart';
import 'sparring_identify_screen.dart';
import 'sparring_orientation.dart';
import 'sparring_round_screen.dart';
import 'widgets/sparring_progress.dart';
import 'widgets/two_skeleton_painter.dart';

/// One sparring session: its rounds (each analysing in the background, then
/// ready), session totals for both fighters, and the "which one is you"
/// prompt until the user has answered it.
class SparringSessionScreen extends StatefulWidget {
  const SparringSessionScreen({required this.sessionId, this.store, this.jobs, super.key});

  final String sessionId;
  final SparringStore? store;
  final SparringJobs? jobs;

  @override
  State<SparringSessionScreen> createState() => _SparringSessionScreenState();
}

class _SparringSessionScreenState extends State<SparringSessionScreen> with SparringLandscape {
  late final SparringStore _store = widget.store ?? SparringStore();
  late final SparringJobs _jobs = widget.jobs ?? SparringJobs.instance;
  SparringSession? _session;
  Map<int, SparringRoundAnalysis> _analyses = const <int, SparringRoundAnalysis>{};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    SparringStore.revision.addListener(_reload);
    _reload();
    SparringSyncQueue.instance.process().catchError((Object _) {});
  }

  @override
  void dispose() {
    SparringStore.revision.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    final session = await _store.loadSession(widget.sessionId);
    final analyses = <int, SparringRoundAnalysis>{};
    for (final r in session?.rounds ?? const <SparringRound>[]) {
      final a = await _store.loadAnalysis(widget.sessionId, r.number);
      if (a != null) analyses[r.number] = a;
    }
    if (!mounted) return;
    setState(() {
      _session = session;
      _analyses = analyses;
      _loaded = true;
    });
  }

  int? get _identifiableRound {
    for (final r in _session?.rounds ?? const <SparringRound>[]) {
      if (_analyses.containsKey(r.number)) return r.number;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        title: Text(session == null ? 'Sparring' : 'Sparring · ${_date(session.createdAt)}'),
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : session == null
              ? const Center(child: Text('This session is gone.'))
              : ValueListenableBuilder<Map<String, SparringJobProgress>>(
                  valueListenable: _jobs.progress,
                  builder: (context, progress, _) => _body(session, progress),
                ),
    );
  }

  Widget _body(SparringSession session, Map<String, SparringJobProgress> progress) {
    final identify = _identifiableRound;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        if (!session.identified && identify != null)
          Card(
            color: AppTheme.surfaceAlt,
            child: ListTile(
              leading: const Icon(Icons.person_search, color: AppTheme.accent),
              title: const Text('Which one is you?'),
              subtitle: const Text(
                'Tap yourself once and every round is labelled You and Partner.',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SparringIdentifyScreen(sessionId: session.id, round: identify),
              )),
            ),
          ),
        if (_analyses.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          _Totals(session: session, analyses: _analyses),
        ],
        const SizedBox(height: 12),
        if (session.rounds.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'No rounds recorded.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textSecondary),
            ),
          ),
        for (final r in session.rounds)
          _RoundTile(
            session: session,
            round: r,
            analysis: _analyses[r.number],
            progress: progress[SparringJobs.key(session.id, r.number)],
            onRetry: () => _jobs.enqueueRound(session.id, r.number),
          ),
      ],
    );
  }

  static String _date(DateTime d) =>
      '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _Totals extends StatelessWidget {
  const _Totals({required this.session, required this.analyses});

  final SparringSession session;
  final Map<int, SparringRoundAnalysis> analyses;

  @override
  Widget build(BuildContext context) {
    final punches = <FighterLabel, int>{for (final l in FighterLabel.values) l: 0};
    final counters = <FighterLabel, int>{for (final l in FighterLabel.values) l: 0};
    var exchanges = 0;
    for (final a in analyses.values) {
      for (final l in FighterLabel.values) {
        punches[l] = punches[l]! + a.fighter(l).punchCount;
        counters[l] = counters[l]! + (a.interaction.fighters[l]?.counters ?? 0);
      }
      exchanges += a.interaction.exchanges.length;
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: <Widget>[
            for (final l in FighterLabel.values)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      session.nameOf(l),
                      style: TextStyle(color: fighterColor(l), fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text('${punches[l]} punches · ${counters[l]} counters'),
                  ],
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Together', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text('$exchanges exchanges over ${analyses.length} round(s)'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundTile extends StatelessWidget {
  const _RoundTile({
    required this.session,
    required this.round,
    required this.analysis,
    required this.progress,
    required this.onRetry,
  });

  final SparringSession session;
  final SparringRound round;
  final SparringRoundAnalysis? analysis;
  final SparringJobProgress? progress;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final a = analysis;
    final p = progress;
    Widget subtitle;
    if (p != null) {
      subtitle = SparringProgressLine(progress: p);
    } else if (round.status == SparringRoundStatus.failed) {
      subtitle = Text(
        round.error ?? 'Analysis failed.',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppTheme.work),
      );
    } else if (a != null) {
      subtitle = Text(
        <String>[
          for (final l in FighterLabel.values)
            '${session.nameOf(l)}: ${a.fighter(l).punchCount} punches',
          '${a.interaction.exchanges.length} exchanges',
          if (a.ai != null) 'AI reviewed',
        ].join(' · '),
      );
    } else {
      subtitle = Text(round.status.label, style: const TextStyle(color: AppTheme.textSecondary));
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text('Round ${round.number}'),
        subtitle: subtitle,
        trailing: round.status == SparringRoundStatus.failed && p == null
            ? TextButton(onPressed: onRetry, child: const Text('Retry'))
            : const Icon(Icons.chevron_right),
        onTap: a == null
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => SparringRoundScreen(sessionId: session.id, round: round.number),
                )),
      ),
    );
  }
}
