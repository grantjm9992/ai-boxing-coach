import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../analysis/round_analysis.dart';
import '../../domain/round_clip.dart';
import '../../domain/session_phase.dart';
import '../../domain/session_plan.dart';
import '../../domain/session_record.dart';
import '../../domain/user_profile.dart';
import '../../engine/coach_cue.dart';
import '../../engine/session_engine.dart';
import '../../services/ai/ai_settings_store.dart';
import '../../services/ai/openai_compatible_vision_model.dart';
import '../../services/camera_round_recorder.dart';
import '../../services/clip_store.dart';
import '../../services/coach_voice.dart';
import '../../services/debug_log.dart';
import '../../services/device_coach_voice.dart';
import '../../services/frame_grabber.dart';
import '../../services/round_analyzer.dart';
import '../../services/profile_store.dart';
import '../../services/round_recorder.dart';
import '../../services/sync/backfill_queue.dart';
import '../../services/sync/round_sync.dart';
import '../../services/round_recording_controller.dart';
import '../../services/session_history_store.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/phase_bar.dart';
import 'camera_check_screen.dart';
import 'session_summary_screen.dart';

/// The running session: one big clock, the current round, and what is coming.
///
/// Everything on this screen has to be readable at arm's length by someone
/// breathing hard, so it is deliberately sparse — the coach carries the detail
/// in audio, the screen carries the clock.
class SessionScreen extends StatefulWidget {
  const SessionScreen({
    required this.plan,
    this.voice,
    this.recorder,
    this.clipStore,
    this.sessionId,
    this.analyzer,
    this.historyStore,
    this.profile,
    this.sync,
    super.key,
  });

  final SessionPlan plan;

  /// The athlete's profile, used to build the drill each round is analysed
  /// against. Loaded from [ProfileStore] when null (the normal path).
  final UserProfile? profile;

  /// Injectable for tests and for running without audio.
  final CoachVoice? voice;

  /// Runs pose analysis over a recorded round. Defaults to the real pipeline.
  final RoundAnalyzer? analyzer;

  /// Persists the completed session for history + the weekly balance.
  final SessionHistoryStore? historyStore;

  /// Best-effort cloud sync of each round. Injectable for tests; defaults to
  /// the real Supabase-backed sync.
  final SupabaseRoundSync? sync;

  /// Records technical rounds. Defaults to the real camera; tests inject a
  /// [FakeRoundRecorder]. Left null on platforms with no camera, where the
  /// camera-check simply reports it and the session runs unrecorded.
  final RoundRecorder? recorder;

  /// Where recorded clips are filed. Injectable for tests.
  final ClipStore? clipStore;

  /// Identifies this session run for clip grouping. Defaults to a timestamp.
  final String? sessionId;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  late final CoachVoice _voice = widget.voice ?? DeviceCoachVoice();
  late final SessionEngine _engine = SessionEngine(
    plan: widget.plan,
    voice: _voice,
  );

  late final RoundRecorder _recorder = widget.recorder ?? CameraRoundRecorder();
  late final ClipStore _clipStore = widget.clipStore ?? ClipStore();
  late final String _sessionId =
      widget.sessionId ?? DateTime.now().millisecondsSinceEpoch.toString();
  late final RoundRecordingController _recording = RoundRecordingController(
    recorder: _recorder,
    clipStore: _clipStore,
    sessionId: _sessionId,
    onClipSaved: _onClipSaved,
  );
  /// Built once the profile + AI settings load, so it's wired for the chosen
  /// analysis mode. Falls back to an offline analyzer until then.
  RoundAnalyzer? _analyzer;
  late final SessionHistoryStore _historyStore =
      widget.historyStore ?? SessionHistoryStore();
  // Durable "upload when online" queue. Lazy: only touched when a round is
  // actually filed, so tests that never record never touch Supabase. Uses the
  // app-wide instance in production (shared with start-up / sign-in drains); an
  // injected sync gets an isolated queue for tests.
  late final BackfillQueue _queue = widget.sync != null
      ? BackfillQueue(sync: widget.sync!)
      : BackfillQueue.instance;

  /// Analyses produced this session, keyed by the round's segment index.
  final Map<int, RoundAnalysis> _analyses = <int, RoundAnalysis>{};

  /// Segment indices whose analysis is running right now — drives the
  /// "Analysing…" badge. Pose runs are serialised, so this is usually one.
  final Set<int> _analysing = <int>{};

  /// The athlete's profile — rounds are analysed against it. Starts neutral and
  /// is replaced once loaded (or taken from the injected value).
  UserProfile _profile = const UserProfile();

  /// True once this session contains technical rounds and we have offered the
  /// framing check. It is offered exactly once, before the first such round.
  bool _cameraChecked = false;

  /// Whether recording is on for this session — set by the camera check.
  bool _recordingEnabled = false;

  /// Serialises the async recording reactions so a burst of engine
  /// notifications cannot start two recordings or two camera checks.
  bool _recordingBusy = false;

  /// Set when a segment change arrives while [_syncRecording] is mid-flight, so
  /// a burst of transitions (skipping quickly) is handled after the current one
  /// rather than silently dropped.
  bool _recordingPending = false;
  int? _lastRecordingIndex;

  bool _navigatedToSummary = false;

  /// Set when the session ends. After that, each late-landing analysis re-saves
  /// the history rollup (AI rounds often finish well after the screen is gone),
  /// so the entry becomes openable once any round has actually been analysed.
  DateTime? _completedAt;

  @override
  void initState() {
    super.initState();
    _engine.addListener(_onEngineChanged);
    WakelockPlus.enable().ignore();
    // Load the profile + AI settings so rounds are analysed against the
    // athlete's stance/style/school in their chosen mode. Injected in tests.
    if (widget.analyzer != null) _analyzer = widget.analyzer;
    final injected = widget.profile;
    if (injected != null) {
      _profile = injected;
      _analyzer ??= RoundAnalyzer();
    } else {
      _loadProfileAndAnalyzer();
    }
    _engine.start();
  }

  Future<void> _loadProfileAndAnalyzer() async {
    final profile = await const ProfileStore().load();
    final config = await const AiSettingsStore().load();
    if (!mounted) return;
    _profile = profile;
    // Only build an AI-backed analyzer when the mode wants it and it's set up;
    // otherwise stay offline.
    if (_analyzer == null) {
      if (profile.analysisMode.usesAi && config.isConfigured) {
        _analyzer = RoundAnalyzer(
          visionModel: OpenAiCompatibleVisionModel(config),
          frameGrabber: PluginFrameGrabber(),
        );
      } else {
        _analyzer = RoundAnalyzer();
      }
    }
  }

  void _onEngineChanged() {
    _syncRecording();
    if (_engine.isCompleted && !_navigatedToSummary) {
      _navigatedToSummary = true;
      // Make sure the last technical round is filed before we leave.
      _recording.finish().whenComplete(() {
        _saveHistory();
        // Let the completion cues start before the screen changes.
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => SessionSummaryScreen(
                plan: widget.plan,
                clipStore: _clipStore,
                sessionId: _recordingEnabled ? _sessionId : null,
                analyses: Map<int, RoundAnalysis>.of(_analyses),
              ),
            ),
          );
        });
      });
    }
  }

  /// Reacts to the current segment changing: runs the one-time camera check
  /// before the first technical round, then keeps the recorder in step with the
  /// segment. Recording is additive — any failure here leaves the session
  /// running exactly as it did in v0.1.
  ///
  /// Serialised through [_recordingBusy]/[_recordingPending]: the camera and the
  /// file moves are async, and the engine can fire several notifications while
  /// one is in flight (a tick, or a rapid skip). Anything that arrives mid-flight
  /// sets [_recordingPending] and is picked up by the loop, so no transition is
  /// lost.
  Future<void> _syncRecording() async {
    if (_recordingBusy) {
      _recordingPending = true;
      return;
    }
    _recordingBusy = true;
    try {
      do {
        _recordingPending = false;
        await _handleSegmentChange();
      } while (_recordingPending);
    } finally {
      _recordingBusy = false;
    }
  }

  Future<void> _handleSegmentChange() async {
    final segment = _engine.currentSegment;
    final index = segment?.index;
    if (index == _lastRecordingIndex) return;

    if (shouldRecordSegment(segment) && !_cameraChecked) {
      _cameraChecked = true;
      _engine.pause();
      _recordingEnabled = await _runCameraCheck();
      if (mounted) _engine.start();
    }
    _lastRecordingIndex = index;
    if (_recordingEnabled) {
      await _recording.onSegment(segment);
      // Reflect the REC indicator / preview appearing or disappearing.
      if (mounted) setState(() {});
    }
  }

  /// Shows the framing check and returns whether recording should be on. With a
  /// non-camera recorder (tests, no-camera platforms) there is no screen to
  /// show; we just probe whether the recorder initialises.
  Future<bool> _runCameraCheck() async {
    final recorder = _recorder;
    if (recorder is! CameraRoundRecorder) {
      try {
        await recorder.initialize();
        return recorder.isReady;
      } on RecorderUnavailable {
        return false;
      }
    }
    if (!mounted) return false;
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => CameraCheckScreen(recorder: recorder),
        fullscreenDialog: true,
      ),
    );
    return confirmed ?? false;
  }

  /// After a technical round is filed, analyse it and — if the analysis lands
  /// while we're still in the rest that follows — speak the summary and the top
  /// correction. Analysis is best-effort: a null result (no camera/model) simply
  /// means no coaching for that round, never a broken session.
  Future<void> _onClipSaved(RoundClip clip) async {
    DebugLog.instance.log(
      'clip saved seg${clip.segmentIndex} (${clip.durationMs}ms) — analysing',
      tag: 'session',
    );
    final analyzer = _analyzer ??= RoundAnalyzer();
    final drill = _profile.toDrill(notes: clip.title ?? '');
    if (mounted) setState(() => _analysing.add(clip.segmentIndex));
    RoundAnalysis? analysis;
    try {
      analysis = await analyzer.analyse(
        clip,
        drill: drill,
        mode: _profile.analysisMode,
      );
    } finally {
      if (mounted) setState(() => _analysing.remove(clip.segmentIndex));
    }
    if (analysis == null) {
      DebugLog.instance.log(
        'seg${clip.segmentIndex} analysis returned null — not synced',
        tag: 'session',
      );
      return;
    }
    _analyses[clip.segmentIndex] = analysis;

    // If this analysis landed after the session already ended (AI rounds often
    // do — pose + a network call takes tens of seconds), refresh the local
    // history rollup so the session's entry reflects it and becomes openable.
    // Mid-session completions are covered by the save at session end.
    if (_completedAt != null) _persistSessionRecord();

    // Durable enqueue, then drain. The round is persisted first, so even if the
    // upload fails now (offline / signed out) it retries on a later launch or
    // sign-in — nothing recorded is lost. Deliberately BEFORE the mounted check:
    // analysis (esp. AI mode) often finishes after the session screen is gone,
    // and this must still run — it touches no widget state.
    _queue
        .enqueueRound(
          clip,
          title: widget.plan.template.name,
          mode: _profile.analysisMode.value,
        )
        .then(
          (_) => _queue.process(
            onOutcome: (job, outcome) {
              if (_isCurrentRound(job, clip)) _reportSync(outcome, clip: clip);
            },
          ),
        )
        .ignore();

    // Everything past here drives the live screen (round map, spoken coaching),
    // so it's fine to stop if we've since left the session.
    if (!mounted) return;
    final inRest = _engine.currentSegment?.isRest ?? false;
    if (inRest && _engine.voiceEnabled) {
      // In an AI mode the model's coaching is the headline; otherwise speak the
      // rules' summary + top correction.
      final ai = analysis.modelCoaching;
      if (ai != null && ai.isNotEmpty) {
        await _voice.speak(ai, CuePriority.routine);
      } else {
        await _voice.speak(analysis.overallSummary, CuePriority.routine);
        if (analysis.correctionPriorities.isNotEmpty) {
          await _voice.speak(
            analysis.correctionPriorities.first.description,
            CuePriority.routine,
          );
        }
      }
    }
  }

  /// Records the completed session for history + the weekly balance. Saved for
  /// every session — the weighted-minutes balance comes from the plan whether or
  /// not any round was analysed.
  void _saveHistory() {
    _completedAt = DateTime.now();
    _persistSessionRecord();
    // Mark the session finished in the cloud (queued so it retries with the
    // rounds). Only meaningful when rounds were recorded this session.
    if (_recordingEnabled) {
      _queue
          .enqueueFinalize(_sessionId, title: widget.plan.template.name)
          .then((_) => _queue.process())
          .ignore();
    }
  }

  /// Build the local history rollup from whatever analyses have completed so far
  /// and persist it (idempotent overwrite by session id). Called at session end
  /// and again as each late analysis lands, so the entry ends up reflecting
  /// every analysed round even when analysis outlives the session screen.
  void _persistSessionRecord() {
    final rounds = <RoundSummary>[];
    for (final segment in widget.plan.segments) {
      if (segment.phase != SessionPhase.technical || !segment.isWork) continue;
      final analysis = _analyses[segment.index];
      final corrections = analysis?.correctionPriorities ?? const [];
      rounds.add(
        RoundSummary(
          segmentIndex: segment.index,
          title: segment.title,
          roundNumber: segment.roundNumber,
          summary: analysis?.overallSummary,
          topCorrection:
              corrections.isNotEmpty ? corrections.first.description : null,
          punchesThrown: analysis?.metrics.punchesThrown,
          guardReturnRate: analysis?.metrics.guardReturnRate,
        ),
      );
    }
    _historyStore
        .save(
          SessionRecord.fromPlan(
            widget.plan,
            sessionId: _sessionId,
            completedAt: _completedAt ?? DateTime.now(),
            rounds: rounds,
          ),
        )
        .ignore();
  }

  /// Whether a queued job is the round we just filed — the one whose outcome we
  /// surface in-app (older backfilled jobs drain quietly, logged only).
  bool _isCurrentRound(SyncJob job, RoundClip clip) =>
      job.kind == SyncJobKind.round &&
      job.clip?.sessionId == clip.sessionId &&
      job.clip?.segmentIndex == clip.segmentIndex;

  /// Surface a sync attempt in-app. During bring-up we show every per-round
  /// outcome (uploaded / no-analysis / signed-out / failed) so a release APK on
  /// a device tells us exactly what happened; [onlyOnFailure] quiets the
  /// finalize call to just its errors.
  void _reportSync(
    SyncOutcome outcome, {
    RoundClip? clip,
    bool onlyOnFailure = false,
  }) {
    if (onlyOnFailure && !outcome.isFailure) return;
    final where = clip != null ? 'Round ${clip.segmentIndex + 1}' : 'Session';
    final String message;
    switch (outcome.status) {
      case SyncStatus.uploaded:
        message = clip != null
            ? '$where synced (${outcome.keyframeCount} keyframes)'
            : '$where finalised in cloud';
      case SyncStatus.skippedSignedOut:
        message = '$where not synced — signed out';
      case SyncStatus.skippedNoAnalysis:
        message = '$where not synced — no analysis';
      case SyncStatus.failed:
        message = '$where sync failed: ${outcome.error}';
    }
    // Log always — a round frequently syncs after the screen is gone, and that
    // outcome is exactly what we need on disk. SnackBar only when still live.
    DebugLog.instance.log(message, tag: 'sync');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: Duration(seconds: outcome.isFailure ? 8 : 3),
      ),
    );
  }

  @override
  void dispose() {
    _engine.removeListener(_onEngineChanged);
    _engine.dispose();
    _recording.finish().ignore();
    _recorder.dispose().ignore();
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
          child: Stack(
            children: <Widget>[
              ListenableBuilder(
                listenable: _engine,
                builder: (context, _) => _SessionBody(engine: _engine),
              ),
              if (_recording.isRecording)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _RecordingIndicator(recorder: _recorder),
                ),
              if (_analysing.isNotEmpty)
                Positioned(
                  top: 8,
                  left: 8,
                  child: _AnalysingBadge(count: _analysing.length),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small pill shown while a round's analysis is running, so it's clear the
/// coach is still working on the last round (and won't be re-triggered).
class _AnalysingBadge extends StatelessWidget {
  const _AnalysingBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Text(
            count > 1 ? 'Analysing $count rounds…' : 'Analysing round…',
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// The "we can see you" reassurance: a small live preview plus a ● REC badge,
/// shown only while a technical round is actually being recorded. Rendering the
/// preview also keeps the camera texture bound, so the camera stays active for
/// the whole session rather than being released between the check and the round.
class _RecordingIndicator extends StatelessWidget {
  const _RecordingIndicator({required this.recorder});

  final RoundRecorder recorder;

  @override
  Widget build(BuildContext context) {
    final r = recorder;
    final controller = r is CameraRoundRecorder ? r.controller : null;
    final hasPreview = controller != null && controller.value.isInitialized;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (hasPreview)
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 66,
                height: 100,
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: controller.value.previewSize?.height ?? 9,
                    height: controller.value.previewSize?.width ?? 16,
                    child: CameraPreview(controller),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppTheme.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              const Text(
                'REC',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ],
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
