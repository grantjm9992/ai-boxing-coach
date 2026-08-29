import 'package:flutter/material.dart';

import '../../data/session_templates.dart';
import '../../domain/feature_flags.dart';
import '../../domain/session_phase.dart';
import '../../domain/session_settings.dart';
import '../../domain/session_template.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/category_widgets.dart';
import '../widgets/phase_bar.dart';
import 'combination_library_screen.dart';
import 'exercise_library_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
import 'progress_screen.dart';
import 'shadow_result_screen.dart';
import 'template_detail_screen.dart';

/// Template picker — the entry point of the app.
///
/// v0.1 ships templates only: the spec's open question 5 recommends templates
/// for the MVP, with generation at v0.9 and a custom builder at v1.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI Boxing Coach',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: <Widget>[
          _HomeMenu(),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: <Widget>[
          const _Preamble(),
          const SizedBox(height: 20),
          for (final template in SessionTemplates.all) ...<Widget>[
            _TemplateCard(template: template),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

/// The single home menu — replaces the row of app-bar icons, which had grown
/// cramped. Add destinations here, not more buttons.
enum _MenuItem {
  shadow('Shadow boxing', Icons.sports_mma),
  combinations('Combinations', Icons.repeat),
  exercises('Exercise library', Icons.fitness_center),
  progress('Progress & trends', Icons.insights_outlined),
  history('History', Icons.history),
  profile('Your profile', Icons.person_outline);

  const _MenuItem(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _HomeMenu extends StatelessWidget {
  Route<void> _route(Widget screen) =>
      MaterialPageRoute<void>(builder: (_) => screen);

  void _onSelected(BuildContext context, _MenuItem item) {
    switch (item) {
      case _MenuItem.shadow:
        startShadowRound(context);
      case _MenuItem.combinations:
        Navigator.of(context).push(_route(const CombinationLibraryScreen()));
      case _MenuItem.exercises:
        Navigator.of(context).push(_route(const ExerciseLibraryScreen()));
      case _MenuItem.progress:
        Navigator.of(context).push(_route(const ProgressScreen()));
      case _MenuItem.history:
        Navigator.of(context).push(_route(const HistoryScreen()));
      case _MenuItem.profile:
        Navigator.of(context).push(_route(const ProfileScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = <_MenuItem>[
      if (FeatureFlags.shadowBoxingV2) _MenuItem.shadow,
      if (FeatureFlags.combinationDrills) _MenuItem.combinations,
      _MenuItem.exercises,
      _MenuItem.progress,
      _MenuItem.history,
      _MenuItem.profile,
    ];
    return PopupMenuButton<_MenuItem>(
      icon: const Icon(Icons.menu),
      tooltip: 'Menu',
      onSelected: (item) => _onSelected(context, item),
      itemBuilder: (context) => <PopupMenuEntry<_MenuItem>>[
        for (final item in items)
          PopupMenuItem<_MenuItem>(
            value: item,
            child: Row(
              children: <Widget>[
                Icon(item.icon, size: 20, color: AppTheme.textSecondary),
                const SizedBox(width: 12),
                Text(item.label),
              ],
            ),
          ),
      ],
    );
  }
}

class _Preamble extends StatelessWidget {
  const _Preamble();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Pick a session',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Every session runs the full arc: warm-up, conditioning, shadow, '
          'technical, cool-down. Durations are yours to set.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
      ],
    );
  }
}

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({required this.template});

  final SessionTemplate template;

  @override
  Widget build(BuildContext context) {
    final settings = SessionSettings.fromTemplate(template);
    final durations = <SessionPhase, Duration>{
      for (final phase in settings.phases) phase.phase: phase.duration,
    };

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => TemplateDetailScreen(template: template),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Text(
                      template.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    TimeFormat.minutes(settings.totalDuration),
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                template.tagline,
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),
              PhaseBar(durations: durations),
              const SizedBox(height: 14),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (final category in template.focus)
                    CategoryChip(
                      category,
                      emphasis: category == template.focus.first,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
