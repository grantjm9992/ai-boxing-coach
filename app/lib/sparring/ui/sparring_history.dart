import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../data/sparring_store.dart';
import '../data/sparring_sync.dart';
import '../model/sparring_session.dart';
import 'sparring_orientation.dart';
import 'sparring_session_screen.dart';

/// Past sparring sessions, newest first — the History screen's Sparring tab
/// and the "Past sparring" screen. Reads sparring's own store only.
class SparringHistoryList extends StatefulWidget {
  const SparringHistoryList({this.store, super.key});

  final SparringStore? store;

  @override
  State<SparringHistoryList> createState() => _SparringHistoryListState();
}

class _SparringHistoryListState extends State<SparringHistoryList> {
  late final SparringStore _store = widget.store ?? SparringStore();
  List<SparringSession>? _sessions;

  @override
  void initState() {
    super.initState();
    SparringStore.revision.addListener(_load);
    _load();
    // Clean up and catch up: old clips go, pending uploads retry.
    _store.sweepExpiredClips().catchError((Object _) => 0);
    SparringSyncQueue.instance.process().catchError((Object _) {});
  }

  @override
  void dispose() {
    SparringStore.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    List<SparringSession> sessions;
    try {
      sessions = await _store.listSessions();
    } on Object {
      sessions = const <SparringSession>[];
    }
    if (mounted) setState(() => _sessions = sessions);
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;
    if (sessions == null) return const Center(child: CircularProgressIndicator());
    if (sessions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No sparring yet. Set one up from the home screen.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: <Widget>[
        for (final s in sessions)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.people_alt_outlined, color: AppTheme.accent),
              title: Text(
                'Sparring${s.partnerName == null ? '' : ' with ${s.partnerName}'}',
              ),
              subtitle: Text(
                '${_date(s.createdAt)} · ${s.rounds.length} round(s)'
                '${s.rounds.any((r) => r.status.isBusy) ? ' · analysing' : ''}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => SparringSessionScreen(sessionId: s.id),
              )),
            ),
          ),
      ],
    );
  }

  static String _date(DateTime d) =>
      '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}';
}

/// "Past sparring" from the home screen.
class SparringHistoryScreen extends StatefulWidget {
  const SparringHistoryScreen({super.key});

  @override
  State<SparringHistoryScreen> createState() => _SparringHistoryScreenState();
}

class _SparringHistoryScreenState extends State<SparringHistoryScreen> with SparringLandscape {
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sparring history')),
    body: const SafeArea(child: SparringHistoryList()),
  );
}
