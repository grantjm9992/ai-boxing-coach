import 'package:flutter/material.dart';

import '../../domain/session_record.dart';
import '../../domain/skill_category.dart';
import '../../services/session_history_store.dart';
import '../../services/sync/history_reader.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/category_widgets.dart';

/// Session history and the weekly category balance — the spec's MVP "am I
/// training in balance?" view, rolled up across every completed session.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({this.store, this.reader, super.key});

  final SessionHistoryStore? store;
  final SupabaseHistoryReader? reader;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final SessionHistoryStore _store = widget.store ?? SessionHistoryStore();
  late final SupabaseHistoryReader _reader =
      widget.reader ?? SupabaseHistoryReader();
  late Future<_HistoryData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  /// Loads the list from the cloud (the source of truth that survives a
  /// reinstall / another device), merged with the local history so anything not
  /// yet synced — or recorded while signed out / offline — still shows. Cloud
  /// wins per session; local fills the gaps and is the fallback when the cloud
  /// call returns nothing. The weekly balance is rolled up from the merged set.
  Future<_HistoryData> _load() async {
    final local = await _store.list();
    final cloud = await _reader.listSessions();
    final sessions = _merge(cloud: cloud, local: local);
    final weekly = _store.weeklyBalanceFrom(sessions);
    return _HistoryData(sessions: sessions, weeklySeconds: weekly);
  }

  /// Union of cloud + local sessions, keyed by session id, cloud preferred.
  /// Sorted newest first.
  List<SessionRecord> _merge({
    required List<SessionRecord> cloud,
    required List<SessionRecord> local,
  }) {
    final byId = <String, SessionRecord>{
      for (final s in local) s.sessionId: s,
    };
    for (final s in cloud) {
      byId[s.sessionId] = s; // cloud is authoritative on conflict
    }
    final merged = byId.values.toList()
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: FutureBuilder<_HistoryData>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data ?? const _HistoryData(sessions: [], weeklySeconds: {});
          if (data.sessions.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No sessions yet. Finish a session and it will show up here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: <Widget>[
              const _SectionTitle('This week'),
              const SizedBox(height: 4),
              const Text(
                'Weighted working minutes across the last 7 days.',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 14),
              CategoryBalance(breakdown: _asBreakdown(data.weeklySeconds), maxRows: 14),
              const SizedBox(height: 28),
              const _SectionTitle('Past sessions'),
              const SizedBox(height: 12),
              for (final session in data.sessions) _SessionTile(session: session),
            ],
          );
        },
      ),
    );
  }

  Map<SkillCategory, Duration> _asBreakdown(Map<String, int> seconds) {
    final entries = seconds.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return <SkillCategory, Duration>{
      for (final e in entries)
        ?SkillCategory.fromKey(e.key): Duration(seconds: e.value),
    };
  }
}

class _HistoryData {
  const _HistoryData({required this.sessions, required this.weeklySeconds});
  final List<SessionRecord> sessions;
  final Map<String, int> weeklySeconds;
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session});

  final SessionRecord session;

  @override
  Widget build(BuildContext context) {
    final analysed = session.rounds.where((r) => r.summary != null).length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(session.templateName),
          subtitle: Text(
            '${_date(session.completedAt)} · '
            '${TimeFormat.minutes(Duration(seconds: session.totalSeconds))} · '
            '${session.roundCount} rounds'
            '${analysed > 0 ? ' · $analysed analysed' : ''}',
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
          trailing: session.rounds.any((r) => r.summary != null)
              ? const Icon(Icons.chevron_right, color: AppTheme.textSecondary)
              : null,
          onTap: session.rounds.any((r) => r.summary != null)
              ? () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _SessionDetailScreen(session: session),
                  ),
                )
              : null,
        ),
      ),
    );
  }

  static String _date(DateTime dt) {
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}

/// A completed session's rounds and their full feedback. Reads the rich
/// analysis + keyframe images back from Supabase (which survives the local
/// 7-day sweep of the video), and falls back to the thin local rollup while
/// that loads or when offline / signed out.
class _SessionDetailScreen extends StatefulWidget {
  const _SessionDetailScreen({required this.session});

  final SessionRecord session;

  @override
  State<_SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<_SessionDetailScreen> {
  HistorySession? _cloud;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    HistorySession? cloud;
    try {
      cloud = await SupabaseHistoryReader().loadSession(widget.session.sessionId);
    } on Object {
      cloud = null; // any failure → local fallback
    }
    if (!mounted) return;
    setState(() {
      _cloud = cloud;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cloud = _cloud;
    final localRounds =
        widget.session.rounds.where((r) => r.summary != null).toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.session.templateName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          if (cloud != null)
            for (final round in cloud.rounds) _CloudRoundCard(round: round)
          else ...<Widget>[
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Loading full feedback…',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ),
            for (final round in localRounds) _LocalRoundCard(round: round),
          ],
        ],
      ),
    );
  }
}

/// A round rendered from the full cloud analysis: summary, AI coaching, every
/// correction, positive notes, and its keyframe images.
class _CloudRoundCard extends StatelessWidget {
  const _CloudRoundCard({required this.round});

  final HistoryRound round;

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
          Text(
            round.roundNumber != null
                ? 'Round ${round.roundNumber}: ${round.title}'
                : round.title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (round.summary != null && round.summary!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(round.summary!, style: const TextStyle(height: 1.4)),
          ],
          if (round.aiCoaching != null && round.aiCoaching!.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const _MiniLabel('AI COACH'),
            const SizedBox(height: 6),
            Text(round.aiCoaching!, style: const TextStyle(height: 1.4)),
          ],
          if (round.moments.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            const _MiniLabel('MOMENTS'),
            for (var i = 0; i < round.moments.length; i++)
              _MomentSection(
                index: i + 1,
                label: round.moments[i].label,
                frameCount: round.moments[i].keyframes.length,
                thumb: (j) =>
                    _NetworkThumb(url: round.moments[i].keyframes[j].url),
                onTapFrame: (j) => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => _KeyframeViewer(
                      keyframes: round.moments[i].keyframes,
                      initialIndex: j,
                    ),
                  ),
                ),
              ),
          ] else if (round.corrections.isNotEmpty) ...<Widget>[
            // Older rounds (synced before per-moment frames): text only.
            const SizedBox(height: 12),
            const _MiniLabel('CORRECTIONS'),
            const SizedBox(height: 6),
            for (final c in round.corrections)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $c', style: const TextStyle(height: 1.35)),
              ),
          ],
          if (round.positiveNotes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            for (final note in round.positiveNotes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(Icons.check, size: 16, color: AppTheme.rest),
                    const SizedBox(width: 8),
                    Expanded(child: Text(note)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// The fallback card: the one-line rollup kept on-device.
class _LocalRoundCard extends StatelessWidget {
  const _LocalRoundCard({required this.round});

  final RoundSummary round;

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
          Text(
            round.roundNumber != null
                ? 'Round ${round.roundNumber}: ${round.title}'
                : round.title,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(round.summary ?? '', style: const TextStyle(height: 1.4)),
          if (round.topCorrection != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              round.topCorrection!,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

/// One flagged moment: its numbered label and the horizontal strip of frames the
/// model reviewed for it. Tap any frame to open the full-screen viewer.
class _MomentSection extends StatelessWidget {
  const _MomentSection({
    required this.index,
    required this.label,
    required this.frameCount,
    required this.thumb,
    this.onTapFrame,
  });

  final int index;
  final String label;
  final int frameCount;
  final Widget Function(int i) thumb;
  final void Function(int i)? onTapFrame;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$index. $label',
            style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: frameCount,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => GestureDetector(
                onTap: onTapFrame == null ? null : () => onTapFrame!(i),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: thumb(i),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A fixed-size keyframe thumbnail from a signed URL, with loading + error
/// placeholders.
class _NetworkThumb extends StatelessWidget {
  const _NetworkThumb({required this.url});

  final String url;

  static const double _w = 128;
  static const double _h = 96;

  @override
  Widget build(BuildContext context) {
    return Image.network(
      url,
      width: _w,
      height: _h,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) => progress == null
          ? child
          : Container(
              width: _w,
              height: _h,
              color: AppTheme.surfaceAlt,
              child: const Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
      errorBuilder: (context, _, _) => Container(
        width: _w,
        height: _h,
        color: AppTheme.surfaceAlt,
        child: const Icon(
          Icons.broken_image_outlined,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

/// Full-screen, swipeable, pinch-to-zoom keyframe viewer.
class _KeyframeViewer extends StatelessWidget {
  const _KeyframeViewer({required this.keyframes, required this.initialIndex});

  final List<HistoryKeyframe> keyframes;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: keyframes.length,
        itemBuilder: (context, i) => InteractiveViewer(
          child: Center(
            child: Image.network(
              keyframes[i].url,
              fit: BoxFit.contain,
              errorBuilder: (context, _, _) => const Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 48,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniLabel extends StatelessWidget {
  const _MiniLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      letterSpacing: 1.2,
      color: AppTheme.textSecondary,
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.w700),
  );
}
