import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../services/camera_round_recorder.dart';
import '../../services/debug_log.dart';
import '../../services/keep_awake.dart';
import '../../services/round_recorder.dart';
import '../../ui/theme.dart';
import '../data/sparring_store.dart';
import '../jobs/sparring_jobs.dart';
import '../model/sparring_session.dart';
import 'sparring_orientation.dart';
import 'sparring_session_screen.dart';

/// Where the capture is.
enum SparringCapturePhase { ready, countdown, fighting, rest, finished }

/// Records a sparring session round by round: landscape, 1080p, back camera,
/// a round timer with bells and a rest timer between rounds. Each finished
/// round is handed straight to [SparringJobs], so it is analysed during the
/// rest.
class SparringCaptureScreen extends StatefulWidget {
  const SparringCaptureScreen({
    required this.sessionId,
    this.store,
    this.jobs,
    this.recorder,
    this.cue,
    super.key,
  });

  final String sessionId;
  final SparringStore? store;
  final SparringJobs? jobs;

  /// Injected in tests; defaults to the back camera at 1080p.
  final RoundRecorder? recorder;

  /// Plays a cue sound (asset path under assets/). Injected in tests.
  final void Function(String asset)? cue;

  @override
  State<SparringCaptureScreen> createState() => _SparringCaptureScreenState();
}

class _SparringCaptureScreenState extends State<SparringCaptureScreen> with SparringLandscape {
  late final SparringStore _store = widget.store ?? SparringStore();
  late final SparringJobs _jobs = widget.jobs ?? SparringJobs.instance;
  late final RoundRecorder _recorder = widget.recorder ??
      CameraRoundRecorder(
        resolution: ResolutionPreset.veryHigh,
        lensDirection: CameraLensDirection.back,
      );
  AudioPlayer? _player;
  void Function()? _releaseAwake;

  SparringSession? _session;
  SparringCapturePhase _phase = SparringCapturePhase.ready;
  int _round = 1;
  int _remaining = 0;
  Timer? _timer;
  DateTime? _roundStartedAt;
  String? _cameraError;
  bool _saving = false;

  /// Countdown before each round.
  static const int countdownSeconds = 5;

  /// Rounds stopped before this aren't kept.
  static const int minRoundSeconds = 15;

  @override
  void initState() {
    super.initState();
    _releaseAwake = KeepAwake.instance.acquire('sparring capture');
    _load();
  }

  Future<void> _load() async {
    final session = await _store.loadSession(widget.sessionId);
    try {
      await _recorder.initialize();
    } on RecorderUnavailable catch (error) {
      _cameraError = error.message;
    }
    if (!mounted) return;
    setState(() {
      _session = session;
      _round = (session?.rounds.length ?? 0) + 1;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _releaseAwake?.call();
    _player?.dispose();
    unawaited(_recorder.dispose());
    super.dispose();
  }

  SparringSettings get _settings => _session?.settings ?? const SparringSettings();

  void _cue(String asset) {
    final cue = widget.cue;
    if (cue != null) {
      cue(asset);
      return;
    }
    try {
      final player = _player ??= AudioPlayer(playerId: 'sparring_cues');
      unawaited(player.play(AssetSource(asset)).catchError((Object _) {}));
    } on Object {
      // No audio: the timer is on screen.
    }
  }

  void _tick(void Function() onSecond) {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(onSecond);
    });
  }

  void _startCountdown() {
    setState(() {
      _phase = SparringCapturePhase.countdown;
      _remaining = countdownSeconds;
    });
    _cue('audio/tick.wav');
    _tick(() {
      _remaining--;
      if (_remaining > 0) {
        _cue('audio/tick.wav');
      } else {
        unawaited(_startRound());
      }
    });
  }

  Future<void> _startRound() async {
    _timer?.cancel();
    _phase = SparringCapturePhase.fighting;
    _remaining = _settings.roundSeconds;
    _roundStartedAt = DateTime.now();
    _cue('audio/bell.wav');
    try {
      final recorder = _recorder;
      if (recorder is CameraRoundRecorder) {
        // Lock the file to the landscape orientation the phone is in now.
        await recorder.controller?.lockCaptureOrientation();
      }
      await _recorder.startRecording();
    } on Object catch (error) {
      DebugLog.instance.log('sparring record start failed: $error', tag: 'sparring');
    }
    if (!mounted) return;
    setState(() {});
    _tick(() {
      _remaining--;
      if (_remaining == 10) _cue('audio/warning.wav');
      if (_remaining <= 0) unawaited(_endRound());
    });
  }

  Future<void> _endRound({bool finishAfter = false}) async {
    if (_phase != SparringCapturePhase.fighting) return;
    _timer?.cancel();
    _cue('audio/end_bell.wav');
    setState(() => _saving = true);
    final started = _roundStartedAt;
    final path = await _recorder.stopRecording();
    final seconds = started == null ? 0 : DateTime.now().difference(started).inSeconds;
    final number = _round;
    if (path != null && seconds >= minRoundSeconds) {
      await _store.adoptClip(widget.sessionId, number, path);
      final session = await _store.update(
        widget.sessionId,
        (s) => s.withRound(SparringRound(number: number, recordedAt: DateTime.now())),
      );
      _jobs.enqueueRound(widget.sessionId, number);
      _session = session ?? _session;
      _round = number + 1;
    } else if (path != null) {
      // Too short to be a round (a false start): discard.
      try {
        await File(path).delete();
      } on FileSystemException {
        // Already gone.
      }
    }
    if (!mounted) return;
    _saving = false;
    final done = finishAfter || _round > _settings.rounds;
    if (done) {
      _finish();
      return;
    }
    setState(() {
      _phase = SparringCapturePhase.rest;
      _remaining = _settings.restSeconds;
    });
    _tick(() {
      _remaining--;
      if (_remaining == 10) _cue('audio/warning.wav');
      if (_remaining <= countdownSeconds && _remaining > 0) _cue('audio/tick.wav');
      if (_remaining <= 0) unawaited(_startRound());
    });
  }

  void _finish() {
    _timer?.cancel();
    setState(() => _phase = SparringCapturePhase.finished);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => SparringSessionScreen(sessionId: widget.sessionId),
      ),
    );
  }

  Future<void> _onFinishPressed() async {
    if (_phase == SparringCapturePhase.fighting) {
      await _endRound(finishAfter: true);
    } else {
      _finish();
    }
  }

  String _clock(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _preview() {
    final recorder = _recorder;
    if (_cameraError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Camera unavailable: $_cameraError',
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ),
      );
    }
    if (recorder is CameraRoundRecorder) {
      final controller = recorder.controller;
      if (controller != null && controller.value.isInitialized) {
        return Center(child: CameraPreview(controller));
      }
    }
    return const ColoredBox(color: Colors.black);
  }

  @override
  Widget build(BuildContext context) {
    final total = _settings.rounds;
    final roundShown = _round > total ? total : _round;
    final (String headline, Color color) = switch (_phase) {
      SparringCapturePhase.ready => ('Round $roundShown of $total', AppTheme.textPrimary),
      SparringCapturePhase.countdown => ('Get ready', AppTheme.work),
      SparringCapturePhase.fighting => ('Round $roundShown of $total', AppTheme.work),
      SparringCapturePhase.rest => ('Rest — round $roundShown next', AppTheme.rest),
      SparringCapturePhase.finished => ('Done', AppTheme.rest),
    };

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _preview(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      IconButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close),
                        tooltip: 'Leave',
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          headline,
                          style: TextStyle(
                            color: color,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            shadows: const <Shadow>[Shadow(blurRadius: 6)],
                          ),
                        ),
                      ),
                      if (_phase == SparringCapturePhase.fighting)
                        const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                        ),
                      if (_phase != SparringCapturePhase.countdown &&
                          (_phase == SparringCapturePhase.fighting ||
                              (_session?.rounds.isNotEmpty ?? false)))
                        TextButton(
                          onPressed: _saving ? null : _onFinishPressed,
                          child: const Text('Finish session'),
                        ),
                    ],
                  ),
                  const Spacer(),
                  if (_phase != SparringCapturePhase.ready)
                    Center(
                      child: Text(
                        _clock(_remaining),
                        style: TextStyle(
                          color: color,
                          fontSize: 64,
                          fontWeight: FontWeight.w800,
                          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                          shadows: const <Shadow>[Shadow(blurRadius: 10)],
                        ),
                      ),
                    ),
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (_phase == SparringCapturePhase.ready)
                        FilledButton.icon(
                          onPressed: _session == null || _cameraError != null
                              ? null
                              : _startCountdown,
                          icon: const Icon(Icons.play_arrow),
                          label: Text('Start round $roundShown'),
                        ),
                      if (_phase == SparringCapturePhase.rest)
                        FilledButton.icon(
                          onPressed: _startCountdown,
                          icon: const Icon(Icons.skip_next),
                          label: const Text('Start next round now'),
                        ),
                      if (_phase == SparringCapturePhase.fighting)
                        OutlinedButton.icon(
                          onPressed: _saving ? null : () => _endRound(),
                          icon: const Icon(Icons.stop),
                          label: const Text('End round'),
                        ),
                    ],
                  ),
                  if (_phase == SparringCapturePhase.ready)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Both fighters head-to-feet in frame, side-on.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70, shadows: <Shadow>[Shadow(blurRadius: 6)]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
