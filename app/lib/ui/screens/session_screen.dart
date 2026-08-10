import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../domain/session_phase.dart';
import '../../domain/session_plan.dart';
import '../../engine/session_engine.dart';
import '../../services/coach_voice.dart';
import '../../services/device_coach_voice.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/phase_bar.dart';
import 'session_summary_screen.dart';

/// The running session: one big clock, the current round, and what is coming.
///
/// Everything on this screen has to be readable at arm's length by someone
/// breathing hard, so it is deliberately sparse — the coach carries the detail
/// in audio, the screen carries the clock.
class SessionScreen extends StatefulWidget {
  const SessionScreen({required this.plan, this.voice, super.key});

  final SessionPlan plan;

  /// Injectable for tests and for running without audio.
  final CoachVoice? voice;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final CoachVoice _voice = widget.voice ?? DeviceCoachVoice();
  late final SessionEngine _engine = SessionEngine(
    plan: widget.plan,
    voice: _voice,
  );
  bool _navigatedToSummary = false;

  @override
  void initState() {
    super.initState();
    _engine.addListener(_onEngineChanged);
    WakelockPlus.enable().ignore();
    _engine.start();
  }

  void _onEngineChanged() {
    if (_engine.isCompleted && !_navigatedToSummary) {
      _navigatedToSummary = true;
      // Let the completion cues start before the screen changes.
      Future<void>.delayed(const Duration(milliseconds: 400), () {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => SessionSummaryScreen(plan: widget.plan),
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineChanged);
    _engine.dispose();
    _voice.dispose().ignore();
    WakelockPlus.disable().ignore();
    super.dispose();
  }

  Future<bool> _confirmExit() async {
    _engine.pause();
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End session?'),
        content: const Text(
          'The session will not be finished. v0.1 keeps no history, so '
          'nothing is saved either way.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End session'),
          ),
        ],
      ),
    );
    if (leave ?? false) {
      _engine.abandon();
      return true;
    }
    _engine.start();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _confirmExit()) {
          navigator.pop();
        }
      },
      child: Scaffold(
        body: SafeArea(
          child: ListenableBuilder(
            listenable: _engine,
            builder: (context, _) => _SessionBody(engine: _engine),
          ),
        ),
      ),
    );
  }
}

class _SessionBody extends StatelessWidget {
  const _SessionBody({required this.engine});

  final SessionEngine engine;

  @override
  Widget build(BuildContext context) {
    final segment = engine.currentSegment;
    if (segment == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final isRest = segment.isRest;
    final accent = isRest ? AppTheme.rest : AppTheme.phaseColor(segment.phase);
    final durations = <SessionPhase, Duration>{
      for (final phase in engine.plan.activePhases)
        phase: engine.plan.durationOf(phase),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _TopBar(engine: engine),
          const SizedBox(height: 10),
          PhaseBar(
            durations: durations,
            height: 6,
            progress: engine.sessionProgress,
          ),
          const SizedBox(height: 24),
          Text(
            isRest ? 'REST' : segment.phase.label.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              letterSpacing: 2,
              fontWeight: FontWeight.w700,
              color: accent,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            segment.positionLabel,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          FittedBox(
            child: Text(
              TimeFormat.clock(engine.remainingInSegment),
              style: TextStyle(
                fontSize: 116,
                height: 1,
                fontWeight: FontWeight.w200,
                color: accent,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: engine.segmentProgress,
              minHeight: 5,
              backgroundColor: AppTheme.surfaceAlt,
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            isRest ? 'Recover' : segment.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          if (!isRest && segment.theme != null) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              segment.exercise.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 16),
          Expanded(child: _CoachPanel(engine: engine)),
          _Controls(engine: engine),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.engine});

  final SessionEngine engine;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'End session',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        Expanded(
          child: Text(
            engine.plan.template.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          '${TimeFormat.clock(engine.sessionRemaining)} left',
          style: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
        IconButton(
          icon: Icon(
            engine.voiceEnabled
                ? Icons.record_voice_over
                : Icons.voice_over_off,
          ),
          tooltip: engine.voiceEnabled ? 'Mute coach' : 'Unmute coach',
          onPressed: () => engine.setVoiceEnabled(!engine.voiceEnabled),
        ),
      ],
    );
  }
}

/// The coach's last line, plus what is coming next — the anticipatory part of
/// the spec's coach behaviour, made visible for anyone training with the sound
/// off.
class _CoachPanel extends StatelessWidget {
  const _CoachPanel({required this.engine});

  final SessionEngine engine;

  @override
  Widget build(BuildContext context) {
    final cue = engine.lastCue?.speech;
    final next = engine.nextWorkSegment;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text(
                    'COACH',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.6,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cue ?? 'Get set.',
                    style: const TextStyle(fontSize: 16, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (next != null) ...<Widget>[
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              const Icon(
                Icons.arrow_forward,
                size: 14,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Next: ${next.title}'
                  '${next.phase == engine.currentSegment?.phase ? '' : ' · ${next.phase.label}'}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.engine});

  final SessionEngine engine;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: <Widget>[
          IconButton(
            iconSize: 32,
            icon: const Icon(Icons.skip_previous),
            tooltip: 'Restart or go back',
            onPressed: engine.previousSegment,
          ),
          SizedBox(
            width: 88,
            height: 88,
            child: FilledButton(
              style: FilledButton.styleFrom(
                shape: const CircleBorder(),
                padding: EdgeInsets.zero,
                backgroundColor: engine.isRunning
                    ? AppTheme.surfaceAlt
                    : AppTheme.accent,
              ),
              onPressed: engine.togglePause,
              child: Icon(
                engine.isRunning ? Icons.pause : Icons.play_arrow,
                size: 40,
              ),
            ),
          ),
          IconButton(
            iconSize: 32,
            icon: const Icon(Icons.skip_next),
            tooltip: 'Skip ahead',
            onPressed: engine.skipSegment,
          ),
        ],
      ),
    );
  }
}
