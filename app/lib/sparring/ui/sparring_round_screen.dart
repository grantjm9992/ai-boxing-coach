import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../analysis/round_analysis.dart' show Severity;
import '../../ui/theme.dart';
import '../ai/sparring_report.dart';
import '../analysis/fighter_analysis.dart';
import '../analysis/interaction.dart';
import '../analysis/sparring_analyzer.dart';
import '../data/sparring_store.dart';
import '../jobs/sparring_jobs.dart';
import '../model/fighter.dart';
import '../model/sparring_session.dart';
import '../tracking/fighter_tracker.dart';
import 'sparring_check_screen.dart';
import 'sparring_identify_screen.dart';
import 'sparring_orientation.dart';
import 'widgets/sparring_progress.dart';
import 'widgets/sparring_video_view.dart';
import 'widgets/two_skeleton_painter.dart';

/// One sparring round reviewed: the video with both colour-coded skeletons,
/// a tab per fighter (summary, output, punch mix, corrections, strengths) and
/// a Together tab (distance, exchanges, counters, guard under fire, defence).
class SparringRoundScreen extends StatefulWidget {
  const SparringRoundScreen({
    required this.sessionId,
    required this.round,
    this.store,
    this.jobs,
    super.key,
  });

  final String sessionId;
  final int round;
  final SparringStore? store;
  final SparringJobs? jobs;

  @override
  State<SparringRoundScreen> createState() => _SparringRoundScreenState();
}

class _SparringRoundScreenState extends State<SparringRoundScreen> with SparringLandscape {
  late final SparringStore _store = widget.store ?? SparringStore();
  late final SparringJobs _jobs = widget.jobs ?? SparringJobs.instance;
  VideoPlayerController? _video;
  SparringSession? _session;
  TrackedRound? _tracked;
  SparringRoundAnalysis? _analysis;
  Set<FighterLabel> _visible = <FighterLabel>{FighterLabel.a, FighterLabel.b};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    SparringStore.revision.addListener(_reload);
    _reload();
    _openVideo();
  }

  @override
  void dispose() {
    SparringStore.revision.removeListener(_reload);
    _video?.dispose();
    super.dispose();
  }

  Future<void> _openVideo() async {
    final clip = await _store.clipPath(widget.sessionId, widget.round);
    if (!await File(clip).exists()) return;
    final video = VideoPlayerController.file(File(clip));
    try {
      await video.initialize();
    } on Object {
      await video.dispose();
      return;
    }
    if (!mounted) {
      await video.dispose();
      return;
    }
    setState(() => _video = video);
  }

  Future<void> _reload() async {
    final session = await _store.loadSession(widget.sessionId);
    final tracked = await _store.loadTracked(widget.sessionId, widget.round);
    final analysis = await _store.loadAnalysis(widget.sessionId, widget.round);
    if (!mounted) return;
    setState(() {
      _session = session;
      _tracked = tracked;
      _analysis = analysis;
      _loaded = true;
    });
  }

  void _seek(double ms) {
    final video = _video;
    if (video == null) return;
    final target = (ms - 1500).clamp(0, double.infinity).toDouble();
    video.seekTo(Duration(milliseconds: target.round()));
    video.play();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final analysis = _analysis;
    return Scaffold(
      appBar: AppBar(title: Text('Round ${widget.round}')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : session == null || analysis == null
              ? const Center(child: Text('This round has no analysis yet.'))
              : SafeArea(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(flex: 5, child: _videoPane(session)),
                      Expanded(flex: 4, child: _panel(session, analysis)),
                    ],
                  ),
                ),
    );
  }

  Widget _videoPane(SparringSession session) {
    final video = _video;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 4, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (video == null)
            const AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: Text(
                    'Video not available (clips are kept for 7 days).',
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              ),
            )
          else
            GestureDetector(
              onDoubleTap: () => video.value.isPlaying ? video.pause() : video.play(),
              child: SparringVideoView(
                controller: video,
                tracked: _tracked,
                visible: _visible,
                labels: <FighterLabel, String>{
                  for (final l in FighterLabel.values) l: session.nameOf(l),
                },
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              if (video != null)
                ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: video,
                  builder: (context, value, _) => IconButton(
                    onPressed: () => value.isPlaying ? video.pause() : video.play(),
                    icon: Icon(value.isPlaying ? Icons.pause : Icons.play_arrow),
                  ),
                ),
              for (final l in FighterLabel.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: FilterChip(
                    label: Text(session.nameOf(l)),
                    selected: _visible.contains(l),
                    selectedColor: fighterColor(l).withValues(alpha: 0.35),
                    onSelected: (on) => setState(() {
                      _visible = <FighterLabel>{..._visible};
                      on ? _visible.add(l) : _visible.remove(l);
                    }),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panel(SparringSession session, SparringRoundAnalysis analysis) {
    final tracked = _tracked;
    final review = tracked?.toReview ?? const <TrackletInfo>[];
    return DefaultTabController(
      length: 3,
      child: Column(
        children: <Widget>[
          ValueListenableBuilder<Map<String, SparringJobProgress>>(
            valueListenable: _jobs.progress,
            builder: (context, progress, _) {
              final p = progress[SparringJobs.key(widget.sessionId, widget.round)];
              return p == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                      child: SparringProgressLine(progress: p),
                    );
            },
          ),
          if (!session.identified)
            _Banner(
              icon: Icons.person_search,
              text: 'Which one is you?',
              action: 'Tell us',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SparringIdentifyScreen(sessionId: session.id, round: widget.round),
              )),
            ),
          if (review.isNotEmpty)
            _Banner(
              icon: Icons.compare_arrows,
              text: "Check who's who — ${review.length} moment(s) the tracker wasn't sure of",
              action: 'Check',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SparringCheckScreen(sessionId: session.id, round: widget.round),
              )),
            ),
          if (analysis.aiStale)
            _Banner(
              icon: Icons.refresh,
              text: "Who's who changed after the AI review — parts of it may describe the wrong fighter.",
              action: 'Re-run',
              onTap: () => _jobs.enqueueAiReview(session.id, widget.round),
            ),
          if (analysis.ai == null && analysis.aiError != null)
            _Banner(
              icon: Icons.cloud_off,
              text: 'AI review: ${analysis.aiError}',
              action: 'Try again',
              onTap: () => _jobs.enqueueAiReview(session.id, widget.round),
            ),
          TabBar(
            tabs: <Widget>[
              for (final l in FighterLabel.values)
                Tab(
                  child: Text(
                    session.nameOf(l),
                    style: TextStyle(color: fighterColor(l), fontWeight: FontWeight.w700),
                  ),
                ),
              const Tab(text: 'Together'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: <Widget>[
                for (final l in FighterLabel.values)
                  _FighterTab(
                    name: session.nameOf(l),
                    fighter: analysis.fighter(l),
                    ai: analysis.ai?.fighter(l),
                    onSeek: _seek,
                  ),
                _TogetherTab(session: session, analysis: analysis, onSeek: _seek),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, required this.action, required this.onTap});

  final IconData icon;
  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    color: AppTheme.surfaceAlt,
    margin: const EdgeInsets.fromLTRB(6, 4, 12, 4),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(icon, color: AppTheme.accent, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
          TextButton(onPressed: onTap, child: Text(action)),
        ],
      ),
    ),
  );
}

String _clock(double ms) {
  final s = (ms / 1000).floor();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class _FighterTab extends StatelessWidget {
  const _FighterTab({
    required this.name,
    required this.fighter,
    required this.ai,
    required this.onSeek,
  });

  final String name;
  final FighterAnalysis fighter;
  final SparringAiFighter? ai;
  final void Function(double ms) onSeek;

  @override
  Widget build(BuildContext context) {
    final f = fighter;
    final mix = f.punchMix;
    final maxMix = mix.values.fold<int>(0, (a, b) => a > b ? a : b);
    final patterns = ai?.patterns ?? const <String>[];
    final landed = ai?.landedEstimate;
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 24),
      children: <Widget>[
        if (f.summary != null) ...<Widget>[
          Text(f.summary!, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 12),
        ],
        if (f.note != null)
          Text(f.note!, style: const TextStyle(color: AppTheme.textSecondary)),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            _Stat('Punches', '${f.punchCount}'),
            _Stat('Per minute', f.punchesPerMinute.toStringAsFixed(0)),
            _Stat('Stance', '${f.stance.name}${f.stanceInferred ? ' (seen)' : ''}'),
            _Stat('Tracked', '${f.analysedSeconds.round()} s'),
            if (landed != null) _Stat('Landed (AI est.)', '$landed'),
          ],
        ),
        if (mix.isNotEmpty) ...<Widget>[
          const _Heading('Punch mix'),
          for (final e in mix.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: <Widget>[
                  SizedBox(width: 92, child: Text(e.key, style: const TextStyle(fontSize: 13))),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: maxMix == 0 ? 0 : e.value / maxMix,
                      minHeight: 6,
                    ),
                  ),
                  SizedBox(width: 32, child: Text('  ${e.value}', style: const TextStyle(fontSize: 13))),
                ],
              ),
            ),
        ],
        const _Heading('Corrections'),
        if (f.findings.isEmpty)
          const Text(
            'Nothing confident enough to flag this round.',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        for (final finding in f.findings) _FindingTile(finding: finding, onSeek: onSeek),
        if (f.strengths.isNotEmpty) ...<Widget>[
          const _Heading('Working well'),
          for (final s in f.strengths)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Text('• $s'),
            ),
        ],
        if (patterns.isNotEmpty) ...<Widget>[
          const _Heading('Tendencies (AI)'),
          for (final p in patterns)
            Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('• $p')),
        ],
      ],
    );
  }
}

class _FindingTile extends StatelessWidget {
  const _FindingTile({required this.finding, required this.onSeek});

  final FighterFinding finding;
  final void Function(double ms) onSeek;

  @override
  Widget build(BuildContext context) {
    final color = switch (finding.severity) {
      Severity.major => AppTheme.work,
      Severity.moderate => const Color(0xFFE0A030),
      _ => AppTheme.textSecondary,
    };
    final at = finding.timestampMs;
    return InkWell(
      onTap: at == null ? null : () => onSeek(at),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(top: 5, right: 8),
              child: Icon(Icons.circle, size: 9, color: color),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(finding.text, style: const TextStyle(height: 1.35)),
                  const SizedBox(height: 2),
                  Text(
                    <String>[
                      if (at != null) _clock(at),
                      finding.source == 'ai' ? 'AI coach' : 'measured',
                      if (finding.drill != null) 'drill: ${finding.drill}',
                    ].join(' · '),
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (at != null) const Icon(Icons.play_circle_outline, size: 20, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _TogetherTab extends StatelessWidget {
  const _TogetherTab({required this.session, required this.analysis, required this.onSeek});

  final SparringSession session;
  final SparringRoundAnalysis analysis;
  final void Function(double ms) onSeek;

  @override
  Widget build(BuildContext context) {
    final i = analysis.interaction;
    final bandTotal = i.bandSeconds.values.fold<double>(0, (a, b) => a + b);
    final ai = analysis.ai;
    String name(FighterLabel l) => session.nameOf(l);
    String percent(double? v) => v == null ? '—' : '${(v * 100).round()}%';
    final notAnalysed = <String>[
      for (final l in FighterLabel.values)
        if ((analysis.unresolvedMs[l] ?? 0) >= 1000)
          '${name(l)} ${((analysis.unresolvedMs[l] ?? 0) / 1000).round()} s',
    ];
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 24),
      children: <Widget>[
        if (ai != null && ai.summary.trim().isNotEmpty) ...<Widget>[
          Text(ai.summary, style: const TextStyle(height: 1.4)),
          const SizedBox(height: 8),
        ],
        const _Heading('Range'),
        if (bandTotal <= 0)
          const Text('Not enough time with both fighters tracked.',
              style: TextStyle(color: AppTheme.textSecondary)),
        for (final band in DistanceBand.values)
          if (bandTotal > 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: <Widget>[
                  SizedBox(width: 92, child: Text(band.label, style: const TextStyle(fontSize: 13))),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (i.bandSeconds[band] ?? 0) / bandTotal,
                      minHeight: 6,
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '  ${((i.bandSeconds[band] ?? 0) / bandTotal * 100).round()}%',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
        const _Heading('Head to head'),
        Table(
          columnWidths: const <int, TableColumnWidth>{0: FlexColumnWidth(1.4)},
          children: <TableRow>[
            TableRow(children: <Widget>[
              const SizedBox.shrink(),
              for (final l in FighterLabel.values)
                Text(name(l), style: TextStyle(color: fighterColor(l), fontWeight: FontWeight.w700)),
            ]),
            _row('Punches', (l) => '${analysis.fighter(l).punchCount}'),
            _row('Exchanges started', (l) => '${i.fighters[l]?.exchangesStarted ?? 0}'),
            _row('Counters', (l) => '${i.fighters[l]?.counters ?? 0}'),
            _row('Hands up when punched at', (l) => percent(i.fighters[l]?.guardUnderFire)),
            _row('Stepped back / ducked', (l) {
              final d = i.fighters[l]?.defence;
              return d == null ? '—' : '${d.stepBack} / ${d.duck}';
            }),
            _row('Reached head / body (2D)', (l) {
              final f = i.fighters[l];
              return f == null ? '—' : '${f.landedHeadCandidates} / ${f.landedBodyCandidates}';
            }),
            if (ai != null)
              _row('Landed (AI estimate)', (l) => '${ai.fighter(l).landedEstimate ?? '—'}'),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            '"Reached" means the fist got to the head or body in the picture — '
            'one camera can\'t see depth, so it isn\'t a landed count.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
        _Heading('Exchanges (${i.exchanges.length})'),
        if (ai != null)
          for (final e in ai.exchanges)
            InkWell(
              onTap: () => onSeek(e.startSeconds * 1000),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${_clock(e.startSeconds * 1000)}'
                  '${e.startedBy == null ? '' : ' · ${name(e.startedBy!)} started'} — ${e.summary}',
                ),
              ),
            ),
        for (final e in i.exchanges)
          InkWell(
            onTap: () => onSeek(e.startMs),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${_clock(e.startMs)}–${_clock(e.endMs)} · ${name(e.startedBy)} started, '
                '${name(e.finishedBy)} finished · '
                '${e.punches[FighterLabel.a] ?? 0}–${e.punches[FighterLabel.b] ?? 0} punches',
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ),
          ),
        if (ai != null && ai.defence.isNotEmpty) ...<Widget>[
          const _Heading('Defence (AI)'),
          for (final d in ai.defence)
            InkWell(
              onTap: () => onSeek(d.timeSeconds * 1000),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '${_clock(d.timeSeconds * 1000)}'
                  '${d.defender == null ? '' : ' · ${name(d.defender!)}'}: ${d.response} — ${d.verdict}',
                ),
              ),
            ),
        ],
        if (notAnalysed.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              'Not analysed (clinches, crossings, out of frame): ${notAnalysed.join(', ')}.',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
      ],
    );
  }

  TableRow _row(String label, String Function(FighterLabel) value) => TableRow(
    children: <Widget>[
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
      ),
      for (final l in FighterLabel.values)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(value(l)),
        ),
    ],
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: AppTheme.surfaceAlt,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 6),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
  );
}
