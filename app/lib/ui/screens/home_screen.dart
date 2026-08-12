import 'package:flutter/material.dart';

import '../../data/session_templates.dart';
import '../../domain/session_phase.dart';
import '../../domain/session_settings.dart';
import '../../domain/session_template.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/category_widgets.dart';
import '../widgets/phase_bar.dart';
import 'exercise_library_screen.dart';
import 'history_screen.dart';
import 'profile_screen.dart';
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
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Your profile',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ProfileScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History & weekly balance',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const HistoryScreen(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.fitness_center),
            tooltip: 'Exercise library',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const ExerciseLibraryScreen(),
              ),
            ),
          ),
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
