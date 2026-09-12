import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../analysis/drill.dart';
import '../../analysis/pose_only_adapter.dart';
import '../../analysis/round_analysis.dart';
import '../../analysis/session_type.dart';
import '../../domain/round_clip.dart';
import '../../domain/session_phase.dart';
import '../../services/ai/ai_settings_store.dart';
import '../../services/ai/coach_vision_model.dart';
import '../../services/analytics.dart';
import '../../services/camera_round_recorder.dart';
import '../../services/clip_store.dart';
import '../../services/frame_grabber.dart';
import '../../services/pose_estimator.dart';
import '../../services/profile_store.dart';
import '../../services/round_analyzer.dart';
import '../../services/round_recorder.dart';
import '../format.dart';
import '../theme.dart';
import 'camera_check_screen.dart';

/// What a capture produced: the analysis (null if it couldn't be produced), the
/// round's duration, and — on the deep-analysis path — the persisted clip.
class RoundCaptureResult {
  const RoundCaptureResult({
    required this.analysis,
    required this.durationMs,
    this.clip,
  });

  final RoundAnalysis? analysis;
  final double durationMs;

  /// The saved [RoundClip], when the capture ran the full analyzer and kept the
  /// video (shadow rounds). Null for the pose-only combination-drill path.
  final RoundClip? clip;
}

/// Records one round with the same pre-flight as a routine — the [CameraCheckScreen]
/// framing check + "I'm in frame" + 5-second count-in — then analyses it and
/// pops a [RoundCaptureResult]. Shared by the combination drill and the
/// standalone shadow-boxing round.
///
/// Recorder, estimator and the analysis step are injectable so the flow is
/// testable without a camera or MediaPipe; [skipFramingCheck] lets a test drive
/// it straight to recording.
class RoundCaptureScreen extends StatefulWidget {
  const RoundCaptureScreen({
    super.key,
    required this.title,
    required this.sessionType,
    this.framingSubtitle =
        'Get yourself in frame so the coach can see your work.',
    this.maxDuration,
    this.focus = const <String>{},
    this.notes = '',
    this.recorder,
    this.estimator,
    this.analyseOverride,
    this.profileLoader,
    this.analytics,
    this.skipFramingCheck = false,
    this.clipStore,
    this.sessionId,
  });

  final String title;
  final SessionType sessionType;
  final String framingSubtitle;

  /// When both are set, the capture keeps the video (saved to [clipStore] under
  /// [sessionId]) and runs the FULL analyzer — pose + AI coaching + keyframes,
  /// written to the AnalysisStore for cloud sync — instead of the pose-only
  /// read. This is how a standalone shadow round reaches parity with a session
  /// round (History detail, AI, saved video). Left null, the capture stays
  /// pose-only and keeps nothing (the combination drill).
  final ClipStore? clipStore;
  final String? sessionId;

  /// When set, the round auto-stops and analyses after this long. The user can
  /// still stop early. Null = record until the user stops.
  final Duration? maxDuration;

  final Set<String> focus;
  final String notes;

  final RoundRecorder? recorder;
  final PoseEstimator? estimator;

  /// Test seam: given the clip path + drill, return the analysis and duration.
  final Future<RoundCaptureResult> Function(String path, DrillContext drill)?
      analyseOverride;
  final Future<DrillContext> Function()? profileLoader;
  final Analytics? analytics;
  final bool skipFramingCheck;

  @override
  State<RoundCaptureScreen> createState() => _RoundCaptureScreenState();
}

enum _Stage { initializing, ready, recording, analysing, error }

class _RoundCaptureScreenState extends State<RoundCaptureScreen> {
  late final RoundRecorder _recorder =
      widget.recorder ?? CameraRoundRecorder();
  late final PoseEstimator _estimator =
      widget.estimator ?? MediaPipePoseEstimator();
  Analytics get _analytics => widget.analytics ?? AnalyticsScope.instance;

  _Stage _stage = _Stage.initializing;
  String _message = '';

  Timer? _countdown;
  Duration? _remaining;
  DateTime? _recordStartedAt;

  @override
  void initState() {
    super.initState();
    _initialise();
  }

  @override
  void dispose() {
    _countdown?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  /// Counts the timed round down and auto-stops at zero.
  void _startCountdown(Duration total) {
    setState(() => _remaining = total);
    _countdown = Timer.periodic(const Duration(seconds: 1), (timer) {
      final left = (_remaining ?? Duration.zero) - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        timer.cancel();
        if (mounted) {
          setState(() => _remaining = Duration.zero);
          _stopAndAnalyse();
        }
        return;
      }
      if (mounted) setState(() => _remaining = left);
    });
  }

  Future<void> _initialise() async {
    try {
      await _recorder.initialize();
      if (!mounted) return;
      setState(() => _stage = _Stage.ready);
      // With a real camera, go straight into the framing check + count-in.
      final recorder = _recorder;
      if (!widget.skipFramingCheck && recorder is CameraRoundRecorder) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _framingThenRecord());
      }
    } on RecorderUnavailable catch (error) {
      _fail('Camera unavailable: ${error.message}');
    } on Object catch (error) {
      _fail('Could not start the camera: $error');
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.error;
      _message = message;
    });
  }

  /// Framing check (with the 5s count-in) → start recording when confirmed.
  Future<void> _framingThenRecord() async {
    final recorder = _recorder;
    if (recorder is! CameraRoundRecorder) return _startRecording();
    final confirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => CameraCheckScreen(
          recorder: recorder,
          title: widget.title,
          subtitle: widget.framingSubtitle,
        ),
      ),
    );
    if (!mounted) return;
    if (confirmed == true) {
      await _startRecording();
    } else {
      // No framing, no round — back out.
      Navigator.of(context).pop();
    }
  }

  Future<void> _startRecording() async {
    try {
      await _recorder.startRecording();
      _analytics.log(
        widget.sessionType == SessionType.shadowBoxing
            ? AnalyticsEvent.shadowBoxingStarted
            : AnalyticsEvent.technicalRoundStarted,
        <String, Object?>{'type': widget.sessionType.value},
      );
      _recordStartedAt = DateTime.now();
      if (!mounted) return;
      setState(() => _stage = _Stage.recording);
      final limit = widget.maxDuration;
      if (limit != null) _startCountdown(limit);
    } on Object catch (error) {
      _fail('Could not start recording: $error');
    }
  }

  /// The round's length. For a timed round the countdown is the reliable
  /// source; wall-clock from record start can be skewed (or, if the start time
  /// never landed, ~zero), which is why a timed shadow round could log 0 min.
  /// Untimed rounds fall back to wall-clock.
  double _elapsedMs() {
    final limit = widget.maxDuration;
    if (limit != null) {
      final elapsed = limit - (_remaining ?? Duration.zero);
      return (elapsed.isNegative ? Duration.zero : elapsed)
          .inMilliseconds
          .toDouble();
    }
    final started = _recordStartedAt;
    if (started == null) return 0;
    return DateTime.now().difference(started).inMilliseconds.toDouble();
  }

  Future<void> _stopAndAnalyse() async {
    if (_stage != _Stage.recording) return; // guard double-stop (timer + tap)
    final elapsedMs = _elapsedMs();
    _countdown?.cancel();
    setState(() {
      _stage = _Stage.analysing;
      _message = 'Analysing your round…';
    });
    try {
      final path = await _recorder.stopRecording();
      if (path == null) {
        _fail('That recording was too short — give it a proper round and try '
            'again.');
        return;
      }
      final drill = await _loadDrill();
      final result = await _analyse(path, drill, elapsedMs);
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on Object catch (error) {
      _fail('Analysis failed: $error');
    }
  }

  Future<DrillContext> _loadDrill() async {
    if (widget.profileLoader != null) return widget.profileLoader!();
    final profile = await const ProfileStore().load();
    return profile.toDrill(
      sessionType: widget.sessionType,
      focus: widget.focus,
      notes: widget.notes,
    );
  }

  Future<RoundCaptureResult> _analyse(
      String path, DrillContext drill, double elapsedMs) async {
    if (widget.analyseOverride != null) {
      return widget.analyseOverride!(path, drill);
    }
    final clipStore = widget.clipStore;
    final sessionId = widget.sessionId;
    if (clipStore != null && sessionId != null) {
      return _deepAnalyse(clipStore, sessionId, path, drill, elapsedMs);
    }
    // Pose-only path (combination drill): read the round, keep nothing.
    RoundAnalysis? analysis;
    double durationMs = 0;
    await for (final progress in _estimator.analyse(path)) {
      final result = progress.result;
      if (result != null) {
        analysis = PoseOnlyAdapter().analyse(result.sequence, drill);
        durationMs = result.sequence.durationMs;
      }
    }
    return RoundCaptureResult(analysis: analysis, durationMs: durationMs);
  }

  /// Deep path (shadow round): keep the video in [ClipStore] and run the FULL
  /// analyzer — pose + AI coaching + keyframes, persisted to the AnalysisStore
  /// so the cloud sync uploads it and History shows the same rich detail a
  /// session round does.
  Future<RoundCaptureResult> _deepAnalyse(
    ClipStore clipStore,
    String sessionId,
    String path,
    DrillContext drill,
    double elapsedMs,
  ) async {
    final startedAt = _recordStartedAt ?? DateTime.now();
    final durationMs = elapsedMs;

    // Move the recording into the managed clip store so it survives the round
    // (and can be exported). rename can fail across mounts — fall back to copy.
    final target = await clipStore.allocatePath(sessionId, 0);
    try {
      await File(path).rename(target);
    } on FileSystemException {
      await File(path).copy(target);
    }
    final clip = RoundClip(
      sessionId: sessionId,
      segmentIndex: 0,
      phase: SessionPhase.shadow,
      path: target,
      recordedAt: startedAt,
      roundNumber: 1,
      durationMs: durationMs.round(),
      title: widget.title,
    );
    await clipStore.add(clip);

    final profile = await const ProfileStore().load();
    final config = await const AiSettingsStore().load();
    final visionModel = profile.analysisMode.usesAi
        ? resolveCoachVisionModel(config: config)
        : null;
    final analyzer = visionModel != null
        ? RoundAnalyzer(
            visionModel: visionModel, frameGrabber: PluginFrameGrabber())
        : RoundAnalyzer();
    final analysis =
        await analyzer.analyse(clip, drill: drill, mode: profile.analysisMode);
    return RoundCaptureResult(
        analysis: analysis, durationMs: durationMs, clip: clip);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: <Widget>[
          Expanded(child: _preview()),
          _controls(),
        ],
      ),
    );
  }

  Widget _preview() {
    final recorder = _recorder;
    final controller =
        recorder is CameraRoundRecorder ? recorder.controller : null;
    if (controller != null &&
        controller.value.isInitialized &&
        _stage == _Stage.recording) {
      // SizedBox.expand + BoxFit.cover fills the whole preview area edge to
      // edge and centres the camera in it. Without the expand, the Column's
      // default (centre) cross-axis alignment left the preview narrower than
      // the screen with dead space beside it.
      return ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.previewSize?.height ?? 9,
              height: controller.value.previewSize?.width ?? 16,
              child: CameraPreview(controller),
            ),
          ),
        ),
      );
    }
    return Container(
      color: AppTheme.surfaceAlt,
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          switch (_stage) {
            _Stage.recording => 'Recording — throw your round.',
            _Stage.analysing => _message,
            _Stage.error => _message,
            _ => 'Setting up…',
          },
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15),
        ),
      ),
    );
  }

  Widget _controls() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: switch (_stage) {
          _Stage.analysing => const _Busy(label: 'Analysing…'),
          _Stage.initializing => const _Busy(label: 'Preparing camera…'),
          _Stage.error => FilledButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back'),
            ),
          _Stage.ready => FilledButton.icon(
              onPressed: _framingThenRecord,
              icon: const Icon(Icons.fiber_manual_record),
              label: const Text('Start recording'),
            ),
          _Stage.recording => Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_remaining != null) ...<Widget>[
                  Text(
                    TimeFormat.clock(_remaining!),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 40,
                      fontWeight: FontWeight.w800,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                FilledButton.icon(
                  style:
                      FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                  onPressed: _stopAndAnalyse,
                  icon: const Icon(Icons.stop),
                  label: Text(
                    _remaining != null ? 'Stop early' : 'Stop & analyse',
                  ),
                ),
              ],
            ),
        },
      ),
    );
  }
}

class _Busy extends StatelessWidget {
  const _Busy({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: 12),
      Text(label, style: const TextStyle(color: AppTheme.textSecondary)),
    ],
  );
}
