import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../analysis/drill.dart';
import '../../analysis/drill_matching.dart';
import '../../analysis/pose_only_adapter.dart';
import '../../analysis/round_analysis.dart';
import '../../analysis/session_type.dart';
import '../../data/combination_library.dart';
import '../../services/analytics.dart';
import '../../services/camera_round_recorder.dart';
import '../../services/pose_estimator.dart';
import '../../services/profile_store.dart';
import '../../services/round_recorder.dart';
import '../theme.dart';

/// Records a drill round for one target combination and evaluates it (brief §15).
///
/// This is the live half of the combination-drill loop: record → pose + rules →
/// combination detection + execution scoring → compare against the target. It
/// pops with a [DrillResult] the caller (the detail screen) then renders, so the
/// screen itself stays a thin recorder + progress view.
///
/// The recorder, estimator and analysis step are injectable so the loop can be
/// driven in a widget test without a camera or MediaPipe.
class CombinationDrillScreen extends StatefulWidget {
  const CombinationDrillScreen({
    super.key,
    required this.combo,
    this.recorder,
    this.estimator,
    this.analyseOverride,
    this.profileLoader,
    this.analytics,
  });

  final CombinationDef combo;
  final RoundRecorder? recorder;
  final PoseEstimator? estimator;

  /// Analytics sink; defaults to the app-wide one.
  final Analytics? analytics;

  /// Test seam: given the recorded clip path + the drill, return the analysis.
  /// When null the real pose + rules pipeline runs.
  final Future<RoundAnalysis?> Function(String path, DrillContext drill)?
      analyseOverride;

  /// Test seam for the drill context (stance drives punch numbering).
  final Future<DrillContext> Function()? profileLoader;

  @override
  State<CombinationDrillScreen> createState() => _CombinationDrillScreenState();
}

enum _Stage { initializing, ready, recording, analysing, error }

class _CombinationDrillScreenState extends State<CombinationDrillScreen> {
  late final RoundRecorder _recorder =
      widget.recorder ?? CameraRoundRecorder();
  late final PoseEstimator _estimator =
      widget.estimator ?? MediaPipePoseEstimator();
  Analytics get _analytics => widget.analytics ?? AnalyticsScope.instance;

  _Stage _stage = _Stage.initializing;
  String _message = '';

  @override
  void initState() {
    super.initState();
    _initialise();
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _initialise() async {
    try {
      await _recorder.initialize();
      if (!mounted) return;
      setState(() => _stage = _Stage.ready);
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

  Future<void> _startRecording() async {
    try {
      await _recorder.startRecording();
      _analytics.log(AnalyticsEvent.technicalRoundStarted,
          <String, Object?>{'combo': widget.combo.id});
      if (!mounted) return;
      setState(() => _stage = _Stage.recording);
    } on Object catch (error) {
      _fail('Could not start recording: $error');
    }
  }

  Future<void> _stopAndEvaluate() async {
    setState(() {
      _stage = _Stage.analysing;
      _message = 'Analysing your combination…';
    });
    try {
      final path = await _recorder.stopRecording();
      if (path == null) {
        _fail('That recording was too short — throw the combination a few '
            'times and try again.');
        return;
      }
      final drill = await _loadDrill();
      final analysis = await _analyse(path, drill);
      if (!mounted) return;
      final result = evaluateDrill(
        widget.combo.numbers,
        analysis?.combinationAnalyses ?? const [],
      );
      for (final attempt in result.attempts) {
        _analytics.log(AnalyticsEvent.combinationAttemptDetected,
            <String, Object?>{'detected': attempt.detected.join('-')});
        _analytics.log(
          attempt.sequenceMatch
              ? AnalyticsEvent.combinationMatchSuccess
              : AnalyticsEvent.combinationMatchFailure,
          <String, Object?>{'combo': widget.combo.id},
        );
      }
      Navigator.of(context).pop(result);
    } on Object catch (error) {
      _fail('Analysis failed: $error');
    }
  }

  Future<DrillContext> _loadDrill() async {
    if (widget.profileLoader != null) return widget.profileLoader!();
    final profile = await const ProfileStore().load();
    return profile.toDrill(
      sessionType: SessionType.combinationDrill,
      focus: const <String>{'combinations'},
      notes: widget.combo.numberLabel,
    );
  }

  Future<RoundAnalysis?> _analyse(String path, DrillContext drill) async {
    if (widget.analyseOverride != null) {
      return widget.analyseOverride!(path, drill);
    }
    RoundAnalysis? analysis;
    await for (final progress in _estimator.analyse(path)) {
      final result = progress.result;
      if (result != null) {
        analysis = PoseOnlyAdapter().analyse(result.sequence, drill);
      }
    }
    return analysis;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Drill · ${widget.combo.numberLabel}')),
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
    if (controller != null && controller.value.isInitialized) {
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: controller.value.previewSize?.height ?? 9,
            height: controller.value.previewSize?.width ?? 16,
            child: CameraPreview(controller),
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
            _Stage.initializing => 'Starting the camera…',
            _Stage.analysing => _message,
            _Stage.error => _message,
            _ => 'Stand back so your whole body is in frame,\n'
                'then throw ${widget.combo.numberLabel} on repeat.',
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
              onPressed: _startRecording,
              icon: const Icon(Icons.fiber_manual_record),
              label: const Text('Start recording'),
            ),
          _Stage.recording => FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
              onPressed: _stopAndEvaluate,
              icon: const Icon(Icons.stop),
              label: const Text('Stop & score'),
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
