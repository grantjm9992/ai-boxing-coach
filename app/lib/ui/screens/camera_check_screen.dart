import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../services/camera_round_recorder.dart';
import '../../services/round_recorder.dart';
import '../theme.dart';

/// The pre-flight framing check, shown once before the first technical round.
///
/// This is the whole point of stage 0.2: the spec calls camera setup a top-three
/// risk and it is entirely a UX problem — *can a person get themselves in frame
/// in a living room?* There is no pose estimation here yet (that is 0.3); the
/// check is the athlete's own eyes on a live preview, with framing guidance.
///
/// Pops `true` if the athlete confirms they are in frame (record this session),
/// or `false` if there is no usable camera or they choose to train without
/// recording. The session never blocks on it — recording is additive.
class CameraCheckScreen extends StatefulWidget {
  const CameraCheckScreen({required this.recorder, super.key});

  final CameraRoundRecorder recorder;

  @override
  State<CameraCheckScreen> createState() => _CameraCheckScreenState();
}

class _CameraCheckScreenState extends State<CameraCheckScreen> {
  bool _initializing = true;
  String? _error;

  /// Once the athlete confirms framing we count down before recording starts —
  /// time to prop the phone and step into position, so the first round isn't
  /// analysed while they're still setting up. Null until the countdown runs.
  int? _countdown;
  Timer? _timer;

  static const int _countdownFrom = 5;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Count down [_countdownFrom]→1, then confirm (pop true → recording starts).
  void _startCountdown() {
    setState(() => _countdown = _countdownFrom);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final next = (_countdown ?? 1) - 1;
      if (next <= 0) {
        timer.cancel();
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      if (mounted) setState(() => _countdown = next);
    });
  }

  Future<void> _init() async {
    try {
      await widget.recorder.initialize();
      if (!mounted) return;
      setState(() => _initializing = false);
    } on RecorderUnavailable catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text(
                'Camera check',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text(
                'Technical rounds coming up. Get yourself in frame so the '
                'coach can see your work.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),
              Expanded(child: _preview()),
              const SizedBox(height: 16),
              ..._guidanceOrError(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _preview() {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator());
    }
    final controller = widget.recorder.controller;
    if (_error != null || controller == null || !controller.value.isInitialized) {
      return Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.videocam_off, size: 40, color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            Text(
              'No camera available on this device.\nYou can still train — this '
              'session just will not be recorded.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: controller.value.previewSize?.height ?? 9,
              height: controller.value.previewSize?.width ?? 16,
              child: CameraPreview(controller),
            ),
          ),
          // A framing guide: the athlete should fill the box head to feet.
          IgnorePointer(
            child: Center(
              child: FractionallySizedBox(
                heightFactor: 0.9,
                widthFactor: 0.55,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white70, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ),
          if (_countdown != null)
            Container(
              color: Colors.black.withValues(alpha: 0.55),
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Text(
                    'Get in position',
                    style: TextStyle(fontSize: 18, color: Colors.white70),
                  ),
                  Text(
                    '$_countdown',
                    style: const TextStyle(
                      fontSize: 96,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _guidanceOrError() {
    final noCamera = _error != null || widget.recorder.controller == null;
    if (noCamera && !_initializing) {
      return <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Continue without recording'),
        ),
      ];
    }
    if (_countdown != null) {
      return <Widget>[
        const Text(
          'Recording starts when the countdown ends — step into the box.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
      ];
    }
    return <Widget>[
      const Text(
        'Prop the phone 2–3 m away, portrait, at hip height. Fit your whole '
        'body — head to feet — inside the box.',
        style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
      ),
      const SizedBox(height: 12),
      Row(
        children: <Widget>[
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Skip recording'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: _initializing ? null : _startCountdown,
              child: const Text("I'm in frame"),
            ),
          ),
        ],
      ),
    ];
  }
}
