import 'package:flutter/material.dart';

import '../../domain/session_phase.dart';
import '../../domain/session_settings.dart';
import '../../domain/session_template.dart';
import '../../engine/session_plan_builder.dart';
import '../../services/settings_store.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/category_widgets.dart';
import '../widgets/phase_bar.dart';
import 'session_screen.dart';

/// Where the athlete tunes the session before starting it.
///
/// Every control is bounded by the phase's own limits, so the session that
/// comes out the other side is always a recognisable version of the template
/// rather than a two-minute warm-up followed by nine technical rounds.
class SessionConfigScreen extends StatefulWidget {
  const SessionConfigScreen({
    required this.template,
    this.settingsStore = const SettingsStore(),
    super.key,
  });

  final SessionTemplate template;
  final SettingsStore settingsStore;

  @override
  State<SessionConfigScreen> createState() => _SessionConfigScreenState();
}

class _SessionConfigScreenState extends State<SessionConfigScreen> {
  late SessionSettings _settings = SessionSettings.fromTemplate(
    widget.template,
  );
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final stored = await widget.settingsStore.load(widget.template);
    if (!mounted) return;
    setState(() {
      _settings = stored;
      _loading = false;
    });
  }

  void _update(PhaseSettings updated) {
    setState(() => _settings = _settings.withPhase(updated));
  }

  Future<void> _start() async {
    await widget.settingsStore.save(widget.template, _settings);
    if (!mounted) return;
    final plan = SessionPlanBuilder.build(widget.template, _settings);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => SessionScreen(plan: plan)));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final plan = SessionPlanBuilder.build(widget.template, _settings);
    final durations = <SessionPhase, Duration>{
      for (final phase in _settings.phases) phase.phase: phase.duration,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('Configure session')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: plan.segments.isEmpty ? null : _start,
              child: Text(
                'Start — ${TimeFormat.minutes(plan.totalDuration)}, '
                '${plan.roundCount} rounds',
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          PhaseBar(durations: durations, height: 10),
          const SizedBox(height: 20),
          for (final phase in _settings.phases) ...<Widget>[
            _PhaseCard(settings: phase, onChanged: _update),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 8),
          _AudioCard(
            settings: _settings,
            onChanged: (updated) => setState(() => _settings = updated),
          ),
          const SizedBox(height: 20),
          Text(
            'Session balance',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Weighted working minutes per category — rest excluded.',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 14),
          CategoryBalance(breakdown: plan.categoryBreakdown),
        ],
      ),
    );
  }
}

class _PhaseCard extends StatelessWidget {
  const _PhaseCard({required this.settings, required this.onChanged});

  final PhaseSettings settings;
  final ValueChanged<PhaseSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final phase = settings.phase;
    final bounds = phase.bounds;
    final enabled = settings.enabled;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: AppTheme.phaseColor(phase),
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
                  TimeFormat.minutes(settings.duration),
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (phase.isOptional)
                  Switch(
                    value: enabled,
                    onChanged: (value) =>
                        onChanged(settings.copyWith(enabled: value)),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(left: 12),
                    child: Tooltip(
                      message: 'The warm-up and cool-down are not optional.',
                      child: Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
              ],
            ),
            if (enabled) ...<Widget>[
              const SizedBox(height: 4),
              if (phase.isRoundBased) ...<Widget>[
                _SliderRow(
                  label: 'Rounds',
                  value: settings.rounds.toDouble(),
                  min: bounds.minRounds.toDouble(),
                  max: bounds.maxRounds.toDouble(),
                  divisions: bounds.maxRounds - bounds.minRounds,
                  display: '${settings.rounds}',
                  onChanged: (value) =>
                      onChanged(settings.copyWith(rounds: value.round())),
                ),
                _SliderRow(
                  label: 'Round length',
                  value: settings.workSeconds.toDouble(),
                  min: bounds.minWorkSeconds.toDouble(),
                  max: bounds.maxWorkSeconds.toDouble(),
                  divisions:
                      (bounds.maxWorkSeconds - bounds.minWorkSeconds) ~/ 15,
                  display: TimeFormat.clock(
                    Duration(seconds: settings.workSeconds),
                  ),
                  onChanged: (value) => onChanged(
                    settings.copyWith(workSeconds: _round(value, 15)),
                  ),
                ),
                _SliderRow(
                  label: 'Rest',
                  value: settings.restSeconds.toDouble(),
                  min: bounds.minRestSeconds.toDouble(),
                  max: bounds.maxRestSeconds.toDouble(),
                  divisions:
                      (bounds.maxRestSeconds - bounds.minRestSeconds) ~/ 15,
                  display: TimeFormat.clock(
                    Duration(seconds: settings.restSeconds),
                  ),
                  onChanged: (value) => onChanged(
                    settings.copyWith(restSeconds: _round(value, 15)),
                  ),
                ),
              ] else
                _SliderRow(
                  label: 'Total',
                  value: settings.totalSeconds.toDouble(),
                  min: bounds.minTotalSeconds.toDouble(),
                  max: bounds.maxTotalSeconds.toDouble(),
                  divisions:
                      (bounds.maxTotalSeconds - bounds.minTotalSeconds) ~/ 60,
                  display: TimeFormat.minutes(
                    Duration(seconds: settings.totalSeconds),
                  ),
                  onChanged: (value) => onChanged(
                    settings.copyWith(totalSeconds: _round(value, 60)),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static int _round(double value, int step) => (value / step).round() * step;
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions > 0 ? divisions : null,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            display,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _AudioCard extends StatelessWidget {
  const _AudioCard({required this.settings, required this.onChanged});

  final SessionSettings settings;
  final ValueChanged<SessionSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: <Widget>[
          SwitchListTile(
            value: settings.voiceEnabled,
            title: const Text('Coach voice'),
            subtitle: const Text(
              'Spoken round calls, previews and technique reminders.',
              style: TextStyle(fontSize: 12),
            ),
            onChanged: (value) =>
                onChanged(settings.copyWith(voiceEnabled: value)),
          ),
          SwitchListTile(
            value: settings.soundEnabled,
            title: const Text('Bells and ticks'),
            subtitle: const Text(
              'Round start and end bells, ten-second countdown.',
              style: TextStyle(fontSize: 12),
            ),
            onChanged: (value) =>
                onChanged(settings.copyWith(soundEnabled: value)),
          ),
        ],
      ),
    );
  }
}
