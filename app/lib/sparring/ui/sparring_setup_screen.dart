import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../data/sparring_store.dart';
import '../model/sparring_session.dart';
import 'sparring_capture_screen.dart';
import 'sparring_orientation.dart';

/// Sets up a sparring session: rounds, lengths, the partner, what each of you
/// is wearing (helps the AI coach tell you apart), and whether the AI coach
/// reviews each round. Landscape, like all of sparring mode.
class SparringSetupScreen extends StatefulWidget {
  const SparringSetupScreen({this.store, super.key});

  final SparringStore? store;

  @override
  State<SparringSetupScreen> createState() => _SparringSetupScreenState();
}

class _SparringSetupScreenState extends State<SparringSetupScreen> with SparringLandscape {
  late final SparringStore _store = widget.store ?? SparringStore();
  SparringSettings _settings = const SparringSettings();
  final TextEditingController _partner = TextEditingController();
  final TextEditingController _youKit = TextEditingController();
  final TextEditingController _partnerKit = TextEditingController();
  bool _starting = false;

  @override
  void dispose() {
    _partner.dispose();
    _youKit.dispose();
    _partnerKit.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => _starting = true);
    String? text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final session = SparringSession(
      id: _store.newSessionId(),
      createdAt: DateTime.now(),
      settings: _settings,
      partnerName: text(_partner),
      youKit: text(_youKit),
      partnerKit: text(_partnerKit),
    );
    await _store.saveSession(session);
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => SparringCaptureScreen(sessionId: session.id)),
    );
  }

  Widget _choice<T>(String title, List<(T, String)> options, T value, void Function(T) onPick) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final (v, label) in options)
              ChoiceChip(
                label: Text(label),
                selected: v == value,
                onSelected: (_) => setState(() => onPick(v)),
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _choice<int>(
          'Rounds',
          <(int, String)>[for (final n in <int>[1, 2, 3, 4, 5, 6]) (n, '$n')],
          _settings.rounds,
          (v) => _settings = _settings.copyWith(rounds: v),
        ),
        const SizedBox(height: 14),
        _choice<int>(
          'Round length',
          const <(int, String)>[(60, '1 min'), (120, '2 min'), (180, '3 min')],
          _settings.roundSeconds,
          (v) => _settings = _settings.copyWith(roundSeconds: v),
        ),
        const SizedBox(height: 14),
        _choice<int>(
          'Rest',
          const <(int, String)>[(30, '30 s'), (60, '1 min'), (90, '90 s')],
          _settings.restSeconds,
          (v) => _settings = _settings.copyWith(restSeconds: v),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _settings.aiReview,
          onChanged: (v) => setState(() => _settings = _settings.copyWith(aiReview: v)),
          title: const Text('AI coach reviews each round'),
          subtitle: const Text(
            'Uses one AI analysis per round from your weekly allowance.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );

    final people = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        TextField(
          controller: _partner,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: "Partner's name (optional)"),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _youKit,
          decoration: const InputDecoration(
            labelText: "What you're wearing (optional)",
            hintText: 'e.g. black top, red shorts',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _partnerKit,
          decoration: const InputDecoration(
            labelText: 'What your partner is wearing (optional)',
            hintText: 'e.g. white vest, blue shorts',
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Set the phone ringside at about waist height, side-on to the action '
          'and far enough back that both of you stay head-to-feet in frame as '
          'you move. Different coloured kit makes telling you apart easier.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.35, fontSize: 13),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Sparring')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              LayoutBuilder(
                builder: (context, box) => box.maxWidth >= 600
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(child: settings),
                          const SizedBox(width: 24),
                          Expanded(child: people),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[settings, const SizedBox(height: 16), people],
                      ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _starting ? null : _start,
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Set up the camera'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
