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
import '../../data/combination_library.dart';
import '../widgets/duration_selector.dart';
import 'combination_detail_screen.dart';
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
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
        children: <Widget>[
          const _Preamble(),
          const SizedBox(height: 12),
          _HomeSection(
            title: 'Workouts & sessions',
            icon: Icons.schedule,
            initiallyExpanded: true,
            children: <Widget>[
              for (final template in SessionTemplates.all) ...<Widget>[
                _TemplateCard(template: template),
                const SizedBox(height: 12),
              ],
            ],
          ),
          if (FeatureFlags.shadowBoxingV2)
            const _HomeSection(
              title: 'Shadow boxing',
              icon: Icons.sports_mma,
              children: <Widget>[_ShadowSection()],
            ),
          if (FeatureFlags.combinationDrills)
            _HomeSection(
              title: 'Combination drills',
              icon: Icons.repeat,
              children: <Widget>[
                for (final combo in CombinationLibrary.all)
                  _ComboTile(combo: combo),
              ],
            ),
        ],
      ),
    );
  }
}

/// The single home menu — replaces the row of app-bar icons, which had grown
/// cramped. Add destinations here, not more buttons.
enum _MenuItem {
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
    return PopupMenuButton<_MenuItem>(
      icon: const Icon(Icons.menu),
      tooltip: 'Menu',
      onSelected: (item) => _onSelected(context, item),
      itemBuilder: (context) => <PopupMenuEntry<_MenuItem>>[
        for (final item in _MenuItem.values)
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

/// One home accordion.
class _HomeSection extends StatelessWidget {
  const _HomeSection({
    required this.title,
    required this.icon,
    required this.children,
    this.initiallyExpanded = false,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        // Drop the default divider lines the ExpansionTile draws.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Icon(icon, color: AppTheme.accent),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// Shadow boxing: pick a length and go straight to the camera set-up.
class _ShadowSection extends StatefulWidget {
  const _ShadowSection();

  @override
  State<_ShadowSection> createState() => _ShadowSectionState();
}

class _ShadowSectionState extends State<_ShadowSection> {
  Duration _duration = const Duration(minutes: 2);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'Record a full shadow round. Guard, stance, footwork and mechanics '
          'all get read.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.35),
        ),
        const SizedBox(height: 12),
        DurationSelector(
          value: _duration,
          onChanged: (d) => setState(() => _duration = d),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => startShadowRound(context, duration: _duration),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start'),
        ),
      ],
    );
  }
}

/// One combination row inside the drills accordion → the config/detail screen.
class _ComboTile extends StatelessWidget {
  const _ComboTile({required this.combo});

  final CombinationDef combo;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Text(
        combo.numberLabel,
        style: const TextStyle(
          color: AppTheme.accent,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
      title: Text(combo.name),
      subtitle: Text(combo.difficulty.label),
      trailing: const Icon(Icons.chevron_right, color: AppTheme.textSecondary),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CombinationDetailScreen(combo: combo),
        ),
      ),
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
