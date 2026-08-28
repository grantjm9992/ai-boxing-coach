import 'package:flutter/material.dart';

import '../../data/combination_library.dart';
import '../theme.dart';
import 'combination_detail_screen.dart';

/// The combination library (brief §14, §15): browse target combinations, filter
/// by difficulty, and open one to view it and drill it.
class CombinationLibraryScreen extends StatefulWidget {
  const CombinationLibraryScreen({super.key});

  @override
  State<CombinationLibraryScreen> createState() =>
      _CombinationLibraryScreenState();
}

class _CombinationLibraryScreenState extends State<CombinationLibraryScreen> {
  CombinationDifficulty? _difficulty;

  List<CombinationDef> get _filtered => CombinationLibrary.all
      .where((c) => _difficulty == null || c.difficulty == _difficulty)
      .toList();

  @override
  Widget build(BuildContext context) {
    final combos = _filtered;
    return Scaffold(
      appBar: AppBar(title: const Text('Combinations')),
      body: Column(
        children: <Widget>[
          _DifficultyFilter(
            value: _difficulty,
            onChanged: (d) => setState(() => _difficulty = d),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: combos.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _CombinationTile(combo: combos[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _DifficultyFilter extends StatelessWidget {
  const _DifficultyFilter({required this.value, required this.onChanged});

  final CombinationDifficulty? value;
  final ValueChanged<CombinationDifficulty?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: <Widget>[
          _chip('All', value == null, () => onChanged(null)),
          for (final d in CombinationDifficulty.values)
            _chip(d.label, value == d, () => onChanged(d)),
        ],
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    ),
  );
}

class _CombinationTile extends StatelessWidget {
  const _CombinationTile({required this.combo});

  final CombinationDef combo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => CombinationDetailScreen(combo: combo),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: <Widget>[
              _NumberBadge(label: combo.numberLabel),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      combo.name,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      combo.difficulty.label,
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumberBadge extends StatelessWidget {
  const _NumberBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.accent,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
    );
  }
}
