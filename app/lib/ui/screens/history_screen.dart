import 'package:flutter/material.dart';

import '../../domain/session_record.dart';
import '../../domain/skill_category.dart';
import '../../services/session_history_store.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/category_widgets.dart';

/// Session history and the weekly category balance — the spec's MVP "am I
/// training in balance?" view, rolled up across every completed session.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({this.store, super.key});

  final SessionHistoryStore? store;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final SessionHistoryStore _store = widget.store ?? SessionHistoryStore();
  late Future<_HistoryData> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_HistoryData> _load() async {
    final sessions = await _store.list();
    final weekly = await _store.weeklyBalance();
    return _HistoryData(sessions: sessions, weeklySeconds: weekly);
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

class _SessionDetailScreen extends StatelessWidget {
  const _SessionDetailScreen({required this.session});

  final SessionRecord session;

  @override
  Widget build(BuildContext context) {
    final analysed = session.rounds.where((r) => r.summary != null).toList();
    return Scaffold(
      appBar: AppBar(title: Text(session.templateName)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          for (final round in analysed)
            Container(
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
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
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
