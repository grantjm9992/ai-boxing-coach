import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../ui/theme.dart';
import '../data/sparring_store.dart';
import '../jobs/sparring_jobs.dart';
import '../model/fighter.dart';
import '../tracking/fighter_tracker.dart';
import 'sparring_orientation.dart';
import 'widgets/sparring_video_view.dart';
import 'widgets/two_skeleton_painter.dart';

/// "Which one is you?" — a clear frame with both fighters' skeletons; the user
/// taps themselves (or the button for their colour). The session then knows
/// what they and their partner look like, and labels every round You / Partner.
class SparringIdentifyScreen extends StatefulWidget {
  const SparringIdentifyScreen({
    required this.sessionId,
    required this.round,
    this.store,
    this.jobs,
    super.key,
  });

  final String sessionId;
  final int round;
  final SparringStore? store;
  final SparringJobs? jobs;

  @override
  State<SparringIdentifyScreen> createState() => _SparringIdentifyScreenState();
}

class _SparringIdentifyScreenState extends State<SparringIdentifyScreen> with SparringLandscape {
  late final SparringStore _store = widget.store ?? SparringStore();
  late final SparringJobs _jobs = widget.jobs ?? SparringJobs.instance;
  VideoPlayerController? _video;
  TrackedRound? _tracked;
  String? _problem;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final tracked = await _store.loadTracked(widget.sessionId, widget.round);
    final clip = await _store.clipPath(widget.sessionId, widget.round);
    final clipExists = await File(clip).exists();
    if (!mounted) return;
    if (tracked == null) {
      setState(() => _problem = 'This round has not been tracked yet.');
      return;
    }
    final frame = tracked.clearestFrame();
    if (frame == null) {
      setState(() => _problem = "Couldn't find a moment with both fighters clearly apart.");
      return;
    }
    if (!clipExists) {
      setState(() {
        _tracked = tracked;
        _problem = 'The video for this round has been deleted, so there is no frame to show.';
      });
      return;
    }
    final video = VideoPlayerController.file(File(clip));
    await video.initialize();
    await video.seekTo(Duration(milliseconds: tracked.timestampsMs[frame].round()));
    await video.pause();
    if (!mounted) {
      await video.dispose();
      return;
    }
    setState(() {
      _tracked = tracked;
      _video = video;
    });
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _choose(FighterLabel you) async {
    setState(() => _saving = true);
    await _jobs.identify(widget.sessionId, widget.round, you);
    if (mounted) Navigator.of(context).pop(you);
  }

  String _colourName(FighterLabel label) => label == FighterLabel.a ? 'red' : 'blue';

  @override
  Widget build(BuildContext context) {
    final video = _video;
    final tracked = _tracked;
    return Scaffold(
      appBar: AppBar(title: const Text('Which one is you?')),
      body: SafeArea(
        child: _problem != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_problem!, textAlign: TextAlign.center),
                ),
              )
            : video == null || tracked == null
                ? const Center(child: CircularProgressIndicator())
                : Row(
                    children: <Widget>[
                      Expanded(
                        flex: 3,
                        child: Center(
                          child: SparringVideoView(
                            controller: video,
                            tracked: tracked,
                            labels: const <FighterLabel, String>{
                              FighterLabel.a: 'Red',
                              FighterLabel.b: 'Blue',
                            },
                            onTapFighter: _saving ? null : _choose,
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const Text(
                                'Tap yourself, or pick your colour. Every round of '
                                'this session is then labelled You and Partner.',
                                style: TextStyle(color: AppTheme.textSecondary, height: 1.35),
                              ),
                              const SizedBox(height: 16),
                              for (final label in FighterLabel.values) ...<Widget>[
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                    backgroundColor: fighterColor(label),
                                  ),
                                  onPressed: _saving ? null : () => _choose(label),
                                  child: Text("I'm ${_colourName(label)}"),
                                ),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
