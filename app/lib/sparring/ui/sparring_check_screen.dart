import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../ui/theme.dart';
import '../data/sparring_store.dart';
import '../jobs/sparring_jobs.dart';
import '../model/fighter.dart';
import '../model/sparring_session.dart';
import '../tracking/fighter_tracker.dart';
import 'sparring_orientation.dart';
import 'widgets/sparring_video_view.dart';
import 'widgets/two_skeleton_painter.dart';

/// "Check who's who": each stretch the tracker wasn't sure of, shown on the
/// video with the body in question outlined, so the user can confirm it or
/// say who it really is. The round is then re-tracked and re-measured from the
/// stored poses — a second, no re-extraction.
class SparringCheckScreen extends StatefulWidget {
  const SparringCheckScreen({
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
  State<SparringCheckScreen> createState() => _SparringCheckScreenState();
}

class _SparringCheckScreenState extends State<SparringCheckScreen> with SparringLandscape {
  late final SparringStore _store = widget.store ?? SparringStore();
  late final SparringJobs _jobs = widget.jobs ?? SparringJobs.instance;
  VideoPlayerController? _video;
  SparringSession? _session;
  TrackedRound? _tracked;
  int _index = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SparringStore.revision.addListener(_reload);
    _jobs.progress.addListener(_onProgress);
    _reload();
    _openVideo();
  }

  void _onProgress() {
    if (!mounted) return;
    final busy = _jobs.isBusy(widget.sessionId, widget.round);
    if (busy == _busy) return;
    if (busy) {
      setState(() => _busy = true);
    } else {
      _reload(); // the re-track finished: show the new state
    }
  }

  @override
  void dispose() {
    SparringStore.revision.removeListener(_reload);
    _jobs.progress.removeListener(_onProgress);
    _video?.dispose();
    super.dispose();
  }

  Future<void> _openVideo() async {
    final clip = await _store.clipPath(widget.sessionId, widget.round);
    if (!await File(clip).exists()) return;
    final video = VideoPlayerController.file(File(clip));
    try {
      await video.initialize();
    } on Object {
      await video.dispose();
      return;
    }
    if (!mounted) {
      await video.dispose();
      return;
    }
    setState(() => _video = video);
    _show();
  }

  Future<void> _reload() async {
    final session = await _store.loadSession(widget.sessionId);
    final tracked = await _store.loadTracked(widget.sessionId, widget.round);
    if (!mounted) return;
    setState(() {
      _session = session;
      _tracked = tracked;
      _busy = _jobs.isBusy(widget.sessionId, widget.round);
      final count = tracked?.toReview.length ?? 0;
      if (_index >= count) _index = count == 0 ? 0 : count - 1;
    });
    _show();
  }

  List<TrackletInfo> get _items => _tracked?.toReview ?? const <TrackletInfo>[];

  TrackletInfo? get _current => _items.isEmpty ? null : _items[_index];

  void _show() {
    final video = _video;
    final tracked = _tracked;
    final current = _current;
    if (video == null || tracked == null || current == null) return;
    final position = current.middle.clamp(0, tracked.frameCount - 1).toInt();
    video.pause();
    video.seekTo(Duration(milliseconds: tracked.timestampsMs[position].round()));
  }

  Future<void> _decide(FighterLabel? label, {bool confirm = false}) async {
    final current = _current;
    if (current == null) return;
    setState(() => _busy = true);
    if (confirm) {
      await _jobs.confirm(widget.sessionId, widget.round, current);
    } else {
      await _jobs.decide(widget.sessionId, widget.round, current.id, label);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final tracked = _tracked;
    final current = _current;
    final video = _video;
    return Scaffold(
      appBar: AppBar(title: const Text("Check who's who")),
      body: SafeArea(
        child: session == null || tracked == null
            ? const Center(child: CircularProgressIndicator())
            : current == null
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const Text('All checked — nothing left that the tracker was unsure of.'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  )
                : Row(
                    children: <Widget>[
                      Expanded(
                        flex: 3,
                        child: Center(
                          child: video == null
                              ? const Text(
                                  'The video for this round has been deleted.',
                                  style: TextStyle(color: AppTheme.textSecondary),
                                )
                              : SparringVideoView(
                                  controller: video,
                                  tracked: tracked,
                                  labels: <FighterLabel, String>{
                                    for (final l in FighterLabel.values) l: session.nameOf(l),
                                  },
                                  question: current.box,
                                ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: <Widget>[
                            Text(
                              '${_index + 1} of ${_items.length}',
                              style: const TextStyle(color: AppTheme.textSecondary),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              current.label == null
                                  ? 'The tracker thinks the outlined person is neither fighter. '
                                      'Who is it?'
                                  : 'The tracker thinks the outlined person is '
                                      '${session.nameOf(current.label!)}'
                                      '${current.status == TrackletStatus.excluded ? ', but too unsure to use it' : ''}. '
                                      'Is that right?',
                              style: const TextStyle(height: 1.35),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${((tracked.timestampsMs[current.start.clamp(0, tracked.frameCount - 1).toInt()]) / 1000).toStringAsFixed(1)}–'
                              '${((tracked.timestampsMs[current.end.clamp(0, tracked.frameCount - 1).toInt()]) / 1000).toStringAsFixed(1)} s',
                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                            ),
                            const SizedBox(height: 14),
                            if (current.label != null)
                              FilledButton(
                                onPressed: _busy ? null : () => _decide(current.label, confirm: true),
                                child: const Text('Yes, that’s right'),
                              ),
                            for (final l in FighterLabel.values)
                              if (l != current.label)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(foregroundColor: fighterColor(l)),
                                    onPressed: _busy ? null : () => _decide(l),
                                    child: Text("It's ${session.nameOf(l)}"),
                                  ),
                                ),
                            if (current.label != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: TextButton(
                                  onPressed: _busy ? null : () => _decide(null),
                                  child: const Text('Neither of us'),
                                ),
                              ),
                            const SizedBox(height: 12),
                            Row(
                              children: <Widget>[
                                IconButton(
                                  onPressed: _index > 0
                                      ? () {
                                          setState(() => _index--);
                                          _show();
                                        }
                                      : null,
                                  icon: const Icon(Icons.chevron_left),
                                ),
                                const Spacer(),
                                if (_busy)
                                  const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                const Spacer(),
                                IconButton(
                                  onPressed: _index < _items.length - 1
                                      ? () {
                                          setState(() => _index++);
                                          _show();
                                        }
                                      : null,
                                  icon: const Icon(Icons.chevron_right),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
