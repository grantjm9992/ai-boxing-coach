import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../analysis/analysis_mode.dart';
import '../../analysis/pose_estimation.dart';
import '../../analysis/pose_only_adapter.dart';
import '../../analysis/round_analysis.dart';
import '../../domain/round_clip.dart';
import '../../domain/user_profile.dart';
import '../../services/ai/ai_settings_store.dart';
import '../../services/ai/coaching_prompt.dart';
import '../../services/ai/openai_compatible_vision_model.dart';
import '../../services/ai/vision_model.dart';
import '../../services/analysis_store.dart';
import '../../services/clip_store.dart';
import '../../services/debug_log.dart';
import '../../services/frame_grabber.dart';
import '../../services/pose_estimator.dart';
import '../../services/profile_store.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/skeleton_painter.dart';

/// The list of technical rounds recorded this session, and — per round — a
/// scrubber, the on-device pose analysis (skeleton overlay, mechanical facts)
/// and the rule-based corrections drawn from it.
class RoundReviewScreen extends StatefulWidget {
  const RoundReviewScreen({
    required this.clipStore,
    required this.sessionId,
    this.estimator,
    super.key,
  });

  final ClipStore clipStore;
  final String sessionId;

  /// Injectable so tests / no-camera platforms can supply a fake. Defaults to
  /// the real MediaPipe estimator.
  final PoseEstimator? estimator;

  @override
  State<RoundReviewScreen> createState() => _RoundReviewScreenState();
}

class _RoundReviewScreenState extends State<RoundReviewScreen> {
  late Future<List<RoundClip>> _clips;

  @override
  void initState() {
    super.initState();
    _clips = widget.clipStore.listForSession(widget.sessionId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Round recordings')),
      body: FutureBuilder<List<RoundClip>>(
        future: _clips,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final clips = snapshot.data ?? const <RoundClip>[];
          if (clips.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No rounds were recorded this session.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: clips.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) =>
                _ClipTile(clip: clips[i], estimator: widget.estimator),
          );
        },
      ),
    );
  }
}

class _ClipTile extends StatelessWidget {
  const _ClipTile({required this.clip, this.estimator});

  final RoundClip clip;
  final PoseEstimator? estimator;

  @override
  Widget build(BuildContext context) {
    final exists = File(clip.path).existsSync();
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: const Icon(Icons.play_circle_outline, color: AppTheme.accent),
        title: Text(clip.title ?? clip.positionLabel),
        subtitle: Text(
          exists ? clip.positionLabel : 'File missing',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        enabled: exists,
        onTap: exists
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      _RoundPlayerScreen(clip: clip, estimator: estimator),
                ),
              )
            : null,
      ),
    );
  }
}

enum _AnalysisState { idle, running, done, failed }

class _RoundPlayerScreen extends StatefulWidget {
  const _RoundPlayerScreen({required this.clip, this.estimator});

  final RoundClip clip;
  final PoseEstimator? estimator;

  @override
  State<_RoundPlayerScreen> createState() => _RoundPlayerScreenState();
}

class _RoundPlayerScreenState extends State<_RoundPlayerScreen> {
  late final VideoPlayerController _controller;
  late final PoseEstimator _estimator =
      widget.estimator ?? MediaPipePoseEstimator();
  final AnalysisStore _store = AnalysisStore();
  bool _ready = false;

  _AnalysisState _state = _AnalysisState.idle;
  double _progress = 0;
  String? _error;
  PoseAnalysisResult? _result;
  RoundAnalysis? _analysis;

  /// The flagged moments and the frames the model reviewed for each — grabbed
  /// from the local clip so the review shows them moment by moment.
  List<_ReviewMoment> _moments = const <_ReviewMoment>[];
  bool _loadingMoments = false;

  UserProfile _profile = const UserProfile();

  // TEMP (debug): a human-readable note of where the analysis shown below came
  // from — "offline rules" vs "AI · <model> · <mode>". Surfaced in the results.
  String? _source;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.clip.path));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.setLooping(true);
    });
    const ProfileStore().load().then((profile) {
      if (mounted) _profile = profile;
    });
    _loadSaved();
  }

  /// The session already ran pose (and, in an AI mode, the model) and saved both
  /// to the [AnalysisStore]. Read that back and show it instantly — no second,
  /// redundant analysis pass. Only if nothing was saved (analysis failed live,
  /// or an old clip) do we fall back to the on-demand "Analyse pose" button.
  Future<void> _loadSaved() async {
    final sessionId = widget.clip.sessionId;
    final segment = widget.clip.segmentIndex;
    final analysis = await _store.loadAnalysis(sessionId, segment);
    final pose = await _store.loadPose(sessionId, segment);
    if (!mounted) return;
    if (analysis == null || pose == null) {
      DebugLog.instance.log(
        'review seg$segment: no saved analysis — offering recompute',
        tag: 'review',
      );
      return; // stays idle → user can recompute on demand
    }
    DebugLog.instance.log(
      'review seg$segment: showing saved analysis'
      '${analysis.modelCoaching != null ? " (incl. AI)" : ""}',
      tag: 'review',
    );
    setState(() {
      _result = PoseAnalysisResult(
        sequence: pose,
        framesAnalysed: pose.length,
        fullBodyVisibleFraction: fullBodyVisibleFraction(pose),
        elapsed: Duration.zero, // not recomputed — nothing to time
      );
      _analysis = analysis;
      _state = _AnalysisState.done;
      _source = 'saved from session'
          '${analysis.modelCoaching != null ? ' · incl. AI' : ''}';
    });
    unawaited(_loadMoments(analysis, pose.durationMs.toDouble()));
  }

  /// Grab the burst of frames around each flagged moment (the same the model
  /// reviews) from the local clip, grouped moment by moment.
  Future<void> _loadMoments(RoundAnalysis analysis, double durationMs) async {
    final bursts =
        CoachingPrompt.keyframeBursts(analysis, durationMs: durationMs);
    if (bursts.isEmpty) return;
    setState(() => _loadingMoments = true);
    try {
      // One grab for the whole round; keep each burst's length so we can slice
      // the flat result back into moments.
      final counts = <int>[for (final b in bursts) b.timestamps.length];
      final timestamps = <double>[for (final b in bursts) ...b.timestamps];
      final images = await PluginFrameGrabber().grab(widget.clip.path, timestamps);
      final moments = <_ReviewMoment>[];
      var offset = 0;
      for (var i = 0; i < bursts.length; i++) {
        final end = offset + counts[i];
        if (offset >= images.length) break;
        moments.add(_ReviewMoment(
          label: bursts[i].label ?? 'Flagged moment',
          centerMs: bursts[i].centerMs,
          frames: images.sublist(offset, end.clamp(0, images.length)),
        ));
        offset = end;
      }
      if (mounted) setState(() => _moments = moments);
    } on Object catch (error) {
      DebugLog.instance.log('review moments grab failed: $error', tag: 'review');
    } finally {
      if (mounted) setState(() => _loadingMoments = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _analyse() async {
    setState(() {
      _state = _AnalysisState.running;
      _progress = 0;
      _error = null;
    });
    try {
      await for (final progress in _estimator.analyse(widget.clip.path)) {
        if (!mounted) return;
        final result = progress.result;
        if (result == null) {
          setState(() => _progress = progress.fraction);
        } else {
          final analysis =
              PoseOnlyAdapter().analyse(result.sequence, _profile.toDrill());
          setState(() {
            _result = result;
            _analysis = analysis;
            _state = _AnalysisState.done;
          });
          unawaited(_loadMoments(analysis, result.sequence.durationMs.toDouble()));
          await _maybeEnrichWithAi(result, analysis);
        }
      }
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _state = _AnalysisState.failed;
        _error = '$error';
      });
    }
  }

  /// TEMP (debug): mirror the live session's AI step here so the review screen
  /// reflects the selected analysis mode and shows where coaching comes from.
  /// Offline pose+rules stays the base; in an AI mode with a configured
  /// endpoint we grab the same frames the session would and call the model.
  Future<void> _maybeEnrichWithAi(
    PoseAnalysisResult result,
    RoundAnalysis analysis,
  ) async {
    // Load fresh so a slow initState future can't leave us reading the default
    // (offline) profile / an empty config.
    final profile = await const ProfileStore().load();
    final config = await const AiSettingsStore().load();
    final mode = profile.analysisMode;
    // Diagnostic: each bail-out names itself, so the SOURCE badge says exactly
    // why AI was or wasn't used.
    void setSource(String s) {
      if (mounted) setState(() => _source = s);
    }

    if (!mode.usesAi) {
      setSource('offline rules (mode=${mode.value})');
      return;
    }
    if (!config.isConfigured) {
      setSource('offline (AI config not set: base/model missing)');
      return;
    }
    setSource('AI (${mode.value}) running…');
    try {
      final drill = profile.toDrill();
      final bursts = mode == AnalysisMode.keyframe
          ? CoachingPrompt.keyframeBursts(
              analysis,
              durationMs: result.sequence.durationMs,
            )
          : const <KeyframeBurst>[];
      final timestamps = mode == AnalysisMode.keyframe
          ? <double>[for (final b in bursts) ...b.timestamps]
          : CoachingPrompt.sampledTimestamps(result.sequence.durationMs);
      if (timestamps.isEmpty) {
        setSource('offline (mode=${mode.value}: no frames to send)');
        return;
      }
      final images = await PluginFrameGrabber().grab(
        widget.clip.path,
        timestamps,
      );
      if (images.isEmpty) {
        setSource('offline (frame grab returned 0 of ${timestamps.length})');
        return;
      }
      final request = mode == AnalysisMode.keyframe
          ? CoachingPrompt.keyframeRequest(analysis, drill, bursts, images)
          : CoachingPrompt.fullFrameRequest(drill, images);
      final model = OpenAiCompatibleVisionModel(config);
      final coaching = await model.complete(request);
      model.close();
      if (!mounted) return;
      setState(() {
        _analysis = analysis.withModelCoaching(coaching.trim());
        _source = 'AI · ${config.model} · ${mode.value} · ${images.length} '
            'frames';
      });
    } on VisionModelException catch (error) {
      setSource('AI failed: ${error.message}');
    } on Object catch (error) {
      setSource('AI failed: $error');
    }
  }

  /// Writes the round's pose sequence to a `.pose.json` and hands it to the OS
  /// share sheet — the phone end of the calibration loop. Pose only, no video:
  /// a few KB, de-identified, and the same wire format
  /// `scripts/analyse_pose_json.py` reads on the desktop.
  Future<void> _exportPose() async {
    final result = _result;
    if (result == null) return;
    try {
      final dir = await getTemporaryDirectory();
      final stem = '${widget.clip.sessionId}_seg${widget.clip.segmentIndex}';
      final file = File('${dir.path}/$stem.pose.json');
      await file.writeAsString(jsonEncode(result.sequence.toJson()));
      await SharePlus.instance.share(
        ShareParams(
          files: <XFile>[XFile(file.path)],
          subject: 'Boxing round pose data',
          text: 'Pose data for ${widget.clip.title ?? widget.clip.positionLabel}'
              ' — run through scripts/analyse_pose_json.py',
        ),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not export: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.clip.title ?? widget.clip.positionLabel),
        actions: <Widget>[
          if (_result != null)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: 'Export pose data',
              onPressed: _exportPose,
            ),
        ],
      ),
      body: !_ready
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: <Widget>[
                _videoWithOverlay(),
                VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(playedColor: AppTheme.accent),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  child: _analysisPanel(),
                ),
              ],
            ),
      floatingActionButton: _ready
          ? FloatingActionButton(
              backgroundColor: AppTheme.accent,
              onPressed: () => setState(() {
                _controller.value.isPlaying
                    ? _controller.pause()
                    : _controller.play();
              }),
              child: Icon(
                _controller.value.isPlaying ? Icons.pause : Icons.play_arrow,
              ),
            )
          : null,
    );
  }

  Widget _videoWithOverlay() {
    return AspectRatio(
      aspectRatio: _controller.value.aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          VideoPlayer(_controller),
          if (_analysis != null && _result != null)
            ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _controller,
              builder: (context, value, _) {
                final frame = _result!.sequence
                    .frameAtTimestamp(value.position.inMilliseconds.toDouble());
                return SkeletonOverlay(frame: frame);
              },
            ),
        ],
      ),
    );
  }

  Widget _analysisPanel() {
    switch (_state) {
      case _AnalysisState.idle:
        return FilledButton.icon(
          onPressed: _analyse,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Analyse pose'),
        );
      case _AnalysisState.running:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Analysing… ${(_progress * 100).round()}%',
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _progress == 0 ? null : _progress,
              backgroundColor: AppTheme.surfaceAlt,
              color: AppTheme.accent,
            ),
          ],
        );
      case _AnalysisState.failed:
        return Text(
          'Pose analysis unavailable: $_error',
          style: const TextStyle(color: AppTheme.textSecondary),
        );
      case _AnalysisState.done:
        return _results();
    }
  }

  Widget _results() {
    final result = _result!;
    final analysis = _analysis!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _FactsRow(result: result),
        const SizedBox(height: 16),
        if (_source != null) ...<Widget>[
          // TEMP (debug): where the analysis below came from.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
            ),
            child: Text(
              'SOURCE: ${_source!.toUpperCase()}',
              style: const TextStyle(
                fontSize: 11,
                letterSpacing: 0.8,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                color: AppTheme.accent,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text(
          analysis.overallSummary,
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
        if (analysis.modelCoaching != null &&
            analysis.modelCoaching!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          const Text(
            'AI COACH',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            analysis.modelCoaching!,
            style: const TextStyle(fontSize: 15, height: 1.4),
          ),
        ],
        if (_moments.isNotEmpty || _loadingMoments) ...<Widget>[
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              const Text(
                'MOMENTS',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  color: AppTheme.textSecondary,
                ),
              ),
              if (_loadingMoments) ...<Widget>[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _moments.length; i++) _reviewMoment(i),
        ] else if (analysis.correctionPriorities.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          const Text(
            'CORRECTIONS',
            style: TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          for (final c in analysis.correctionPriorities)
            _CorrectionTile(
              correction: c,
              onSeek: c.exampleTimestampMs == null
                  ? null
                  : () => _controller.seekTo(
                      Duration(milliseconds: c.exampleTimestampMs!.round()),
                    ),
            ),
        ],
        if (analysis.positiveNotes.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          for (final note in analysis.positiveNotes)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Icon(Icons.check, size: 16, color: AppTheme.rest),
                  const SizedBox(width: 8),
                  Expanded(child: Text(note)),
                ],
              ),
            ),
        ],
      ],
    );
  }

  /// One flagged moment: its numbered correction text, a jump-to-video button,
  /// and the strip of frames the model reviewed. Tap a frame to open it full.
  Widget _reviewMoment(int i) {
    final m = _moments[i];
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Text(
                  '${i + 1}. ${m.label}',
                  style: const TextStyle(fontWeight: FontWeight.w600, height: 1.3),
                ),
              ),
              TextButton(
                onPressed: () => _controller
                    .seekTo(Duration(milliseconds: m.centerMs.round())),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                ),
                child: Text('${(m.centerMs / 1000).toStringAsFixed(1)}s'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: m.frames.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, j) => GestureDetector(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        _MemoryKeyframeViewer(frames: m.frames, initialIndex: j),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    m.frames[j].bytes,
                    width: 128,
                    height: 96,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A flagged moment in the review screen: correction text + the frames grabbed
/// for it from the local clip.
class _ReviewMoment {
  const _ReviewMoment({
    required this.label,
    required this.centerMs,
    required this.frames,
  });

  final String label;
  final double centerMs;
  final List<VisionImage> frames;
}

/// Full-screen, swipeable, pinch-to-zoom viewer over in-memory frames.
class _MemoryKeyframeViewer extends StatelessWidget {
  const _MemoryKeyframeViewer({required this.frames, required this.initialIndex});

  final List<VisionImage> frames;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: frames.length,
        itemBuilder: (context, i) => InteractiveViewer(
          child: Center(child: Image.memory(frames[i].bytes, fit: BoxFit.contain)),
        ),
      ),
    );
  }
}

class _FactsRow extends StatelessWidget {
  const _FactsRow({required this.result});

  final PoseAnalysisResult result;

  @override
  Widget build(BuildContext context) {
    final visible = (result.fullBodyVisibleFraction * 100).round();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          _Fact(label: 'Frames', value: '${result.framesAnalysed}'),
          // Only meaningful for a fresh run; saved analyses carry no timing.
          if (result.elapsed > Duration.zero)
            _Fact(
              label: 'Took',
              value:
                  '${(result.elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s',
            ),
          _Fact(label: 'You in frame', value: '$visible%'),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 0.6,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _CorrectionTile extends StatelessWidget {
  const _CorrectionTile({required this.correction, this.onSeek});

  final Correction correction;
  final VoidCallback? onSeek;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          dense: true,
          leading: CircleAvatar(
            radius: 13,
            backgroundColor: AppTheme.accent,
            child: Text(
              '${correction.priority}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          title: Text(correction.description, style: const TextStyle(fontSize: 14)),
          subtitle: correction.exampleTimestampMs == null
              ? null
              : Text(
                  'Tap to jump to '
                  '${TimeFormat.clock(Duration(milliseconds: correction.exampleTimestampMs!.round()))}',
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
          trailing: onSeek == null
              ? null
              : const Icon(Icons.my_location, size: 18, color: AppTheme.textSecondary),
          onTap: onSeek,
        ),
      ),
    );
  }
}
