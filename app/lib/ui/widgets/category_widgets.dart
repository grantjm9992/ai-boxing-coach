import 'package:flutter/material.dart';

import '../../domain/skill_category.dart';
import '../format.dart';
import '../theme.dart';

/// A small tag naming one skill category.
class CategoryChip extends StatelessWidget {
  const CategoryChip(this.category, {this.emphasis = false, super.key});

  final SkillCategory category;

  /// Highlights the category a template or exercise is mainly about.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: emphasis
            ? AppTheme.accent.withValues(alpha: 0.18)
            : AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: emphasis
              ? AppTheme.accent.withValues(alpha: 0.6)
              : Colors.transparent,
        ),
      ),
      child: Text(
        category.label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: emphasis ? AppTheme.textPrimary : AppTheme.textSecondary,
        ),
      ),
    );
  }
}

/// The balance view: weighted working minutes per category.
///
/// This is the spec's category tracking in its v0.1 form — one session rather
/// than a week, because v0.1 keeps no history. The maths is already the
/// weighted-minutes model the weekly dashboard will use.
class CategoryBalance extends StatelessWidget {
  const CategoryBalance({required this.breakdown, this.maxRows = 8, super.key});

  final Map<SkillCategory, Duration> breakdown;
  final int maxRows;

  @override
  Widget build(BuildContext context) {
    if (breakdown.isEmpty) {
      return const Text(
        'No work segments in this session.',
        style: TextStyle(color: AppTheme.textSecondary),
      );
    }
    final entries = breakdown.entries.take(maxRows).toList();
    final peak = entries.first.value.inSeconds.clamp(1, 1 << 30);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 120,
                  child: Text(
                    entry.key.label,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: entry.value.inSeconds / peak,
                      minHeight: 8,
                      backgroundColor: AppTheme.surfaceAlt,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        AppTheme.accent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 56,
                  child: Text(
                    TimeFormat.minutes(entry.value),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 13,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
