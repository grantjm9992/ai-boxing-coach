import 'package:flutter/material.dart';

import '../../data/exercise_library.dart';
import '../../domain/exercise.dart';
import '../../domain/session_phase.dart';
import '../../domain/skill_category.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/category_widgets.dart';

/// The exercise library, filterable by phase and by skill category.
///
/// Category tags are not decoration: they are the same weights that drive the
/// balance view, so browsing by "defence" shows exactly what the tracking
/// counts as defensive work.
class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  SessionPhase? _phase;
  SkillCategory? _category;

  List<Exercise> get _filtered => ExerciseLibrary.all.where((exercise) {
    if (_phase != null && exercise.phase != _phase) return false;
    if (_category != null && !exercise.categoryWeights.containsKey(_category)) {
      return false;
    }
    return true;
  }).toList();

  @override
  Widget build(BuildContext context) {
    final exercises = _filtered;

    return Scaffold(
      appBar: AppBar(title: const Text('Exercise library')),
      body: Column(
        children: <Widget>[
          _FilterRow(
            phase: _phase,
            category: _category,
            onPhase: (value) => setState(() => _phase = value),
            onCategory: (value) => setState(() => _category = value),
          ),
          const Divider(height: 1),
          Expanded(
            child: exercises.isEmpty
                ? const Center(
                    child: Text(
                      'Nothing matches those filters.',
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    itemCount: exercises.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _ExerciseCard(exercise: exercises[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({
    required this.phase,
    required this.category,
    required this.onPhase,
    required this.onCategory,
  });

  final SessionPhase? phase;
  final SkillCategory? category;
  final ValueChanged<SessionPhase?> onPhase;
  final ValueChanged<SkillCategory?> onCategory;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _Pill(
                  label: 'All phases',
                  selected: phase == null,
                  onTap: () => onPhase(null),
                ),
                for (final value in SessionPhase.values)
                  _Pill(
                    label: value.label,
                    selected: phase == value,
                    colour: AppTheme.phaseColor(value),
                    onTap: () => onPhase(phase == value ? null : value),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _Pill(
                  label: 'All categories',
                  selected: category == null,
                  onTap: () => onCategory(null),
                ),
                for (final value in SkillCategory.values)
                  _Pill(
                    label: value.label,
                    selected: category == value,
                    onTap: () => onCategory(category == value ? null : value),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.colour,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final accent = colour ?? AppTheme.accent;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.22)
                : AppTheme.surfaceAlt,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: selected ? accent : Colors.transparent),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? AppTheme.textPrimary : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    exercise.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  TimeFormat.clock(
                    Duration(seconds: exercise.defaultDurationSeconds),
                  ),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppTheme.phaseColor(exercise.phase),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${exercise.phase.label} · difficulty '
                  '${exercise.difficulty}/5',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              exercise.description,
              style: const TextStyle(height: 1.4, fontSize: 14),
            ),
            if (exercise.equipmentNotes != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Equipment: ${exercise.equipmentNotes}',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final category in exercise.categories)
                  CategoryChip(
                    category,
                    emphasis: category == exercise.primaryCategory,
                  ),
              ],
            ),
            if (exercise.cues.isNotEmpty) ...<Widget>[
              const Divider(height: 24),
              const Text(
                'COACH CUES',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              for (final cue in exercise.cues)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '“$cue”',
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      fontStyle: FontStyle.italic,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
