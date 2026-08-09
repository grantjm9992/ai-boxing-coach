import 'package:flutter/material.dart';

import '../../data/exercise_library.dart';
import '../../domain/session_settings.dart';
import '../../domain/session_template.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/category_widgets.dart';
import 'session_config_screen.dart';

/// The full breakdown of a template: what each phase is for, and what is in it.
///
/// The spec's first design principle is structure over freestyle, so the intent
/// of each phase is shown as prominently as its content.
class TemplateDetailScreen extends StatelessWidget {
  const TemplateDetailScreen({required this.template, super.key});

  final SessionTemplate template;

  @override
  Widget build(BuildContext context) {
    final settings = SessionSettings.fromTemplate(template);

    return Scaffold(
      appBar: AppBar(title: Text(template.name)),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SessionConfigScreen(template: template),
                ),
              ),
              child: const Text('Configure & start'),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          Text(
            template.description,
            style: const TextStyle(color: AppTheme.textSecondary, height: 1.45),
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              _Stat(
                label: 'Duration',
                value: TimeFormat.minutes(settings.totalDuration),
              ),
              _Stat(label: 'Difficulty', value: '${template.difficulty}/5'),
              _Stat(label: 'Phases', value: '${template.phases.length}'),
            ],
          ),
          const SizedBox(height: 20),
          for (final templatePhase in template.phases) ...<Widget>[
            _PhaseSection(
              templatePhase: templatePhase,
              settings: settings.forPhase(templatePhase.phase)!,
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 0.8,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _PhaseSection extends StatelessWidget {
  const _PhaseSection({required this.templatePhase, required this.settings});

  final TemplatePhase templatePhase;
  final PhaseSettings settings;

  @override
  Widget build(BuildContext context) {
    final phase = templatePhase.phase;
    final colour = AppTheme.phaseColor(phase);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colour,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    phase.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  phase.isRoundBased
                      ? TimeFormat.rounds(
                          settings.rounds,
                          settings.workSeconds,
                          settings.restSeconds,
                        )
                      : TimeFormat.minutes(settings.duration),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              templatePhase.intentText,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                height: 1.4,
              ),
            ),
            const Divider(height: 24),
            for (var i = 0; i < templatePhase.items.length; i++)
              _ItemRow(
                index: i,
                item: templatePhase.items[i],
                numbered: phase.isRoundBased,
              ),
          ],
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.index,
    required this.item,
    required this.numbered,
  });

  final int index;
  final PhaseItem item;
  final bool numbered;

  @override
  Widget build(BuildContext context) {
    final exercise = ExerciseLibrary.byKey(item.exerciseKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 28,
            child: Text(
              numbered ? '${index + 1}' : '•',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.theme ?? exercise.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (item.theme != null)
                  Text(
                    exercise.label,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final category in exercise.categories.take(3))
                      CategoryChip(
                        category,
                        emphasis: category == exercise.primaryCategory,
                      ),
                    if (exercise.requiresEquipment) const _EquipmentTag(),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EquipmentTag extends StatelessWidget {
  const _EquipmentTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Equipment',
        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
      ),
    );
  }
}
