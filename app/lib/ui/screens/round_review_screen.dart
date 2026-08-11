import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import '../../analysis/drill.dart';
import '../../analysis/pose_only_adapter.dart';
import '../../analysis/round_analysis.dart';
import '../../domain/round_clip.dart';
import '../../services/clip_store.dart';
import '../../services/pose_estimator.dart';
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
  bool _ready = false;

  _AnalysisState _state = _AnalysisState.idle;
  double _progress = 0;
  String? _error;
  PoseAnalysisResult? _result;
  RoundAnalysis? _analysis;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.clip.path));
    _controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.setLooping(true);
    });
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
              PoseOnlyAdapter().analyse(result.sequence, const DrillContext());
          setState(() {
            _result = result;
            _analysis = analysis;
            _state = _AnalysisState.done;
          });
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
        Text(
          analysis.overallSummary,
          style: const TextStyle(fontSize: 15, height: 1.4),
        ),
        if (analysis.correctionPriorities.isNotEmpty) ...<Widget>[
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
          _Fact(
            label: 'Took',
            value: '${(result.elapsed.inMilliseconds / 1000).toStringAsFixed(1)}s',
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
