import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import 'sparring_history.dart';
import 'sparring_setup_screen.dart';

/// The Sparring accordion's content on the home screen — the entry point into
/// sparring mode (which runs in landscape).
class SparringHomeSection extends StatelessWidget {
  const SparringHomeSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'Film a sparring session from ringside. Both fighters are tracked and '
          'get their own corrections and stats, plus distance, exchanges and '
          'counters between you.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.35),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SparringSetupScreen()),
          ),
          icon: const Icon(Icons.people_alt_outlined),
          label: const Text('Set up sparring'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SparringHistoryScreen()),
          ),
          icon: const Icon(Icons.history),
          label: const Text('Past sparring'),
        ),
      ],
    );
  }
}
