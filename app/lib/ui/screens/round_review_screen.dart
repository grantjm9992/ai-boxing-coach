import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../domain/round_clip.dart';
import '../../services/clip_store.dart';
import '../theme.dart';

/// The list of technical rounds recorded this session, and a scrubber to look
/// back at them.
///
/// In 0.2 this is just video — no skeleton overlay, no flagged moments. Those
/// arrive in 0.3/0.5. The point here is only that the clips exist, are labelled
/// by round, and can be scrubbed, which doubles as the honest "we recorded you"
/// confirmation.
class RoundReviewScreen extends StatefulWidget {
  const RoundReviewScreen({
    required this.clipStore,
    required this.sessionId,
    super.key,
  });

  final ClipStore clipStore;
  final String sessionId;

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
            itemBuilder: (context, i) => _ClipTile(clip: clips[i]),
          );
        },
      ),
    );
  }
}

class _ClipTile extends StatelessWidget {
  const _ClipTile({required this.clip});

  final RoundClip clip;

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
                  builder: (_) => _RoundPlayerScreen(clip: clip),
                ),
              )
            : null,
      ),
    );
  }
}

class _RoundPlayerScreen extends StatefulWidget {
  const _RoundPlayerScreen({required this.clip});

  final RoundClip clip;

  @override
  State<_RoundPlayerScreen> createState() => _RoundPlayerScreenState();
}

class _RoundPlayerScreenState extends State<_RoundPlayerScreen> {
  late final VideoPlayerController _controller;
  bool _ready = false;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.clip.title ?? widget.clip.positionLabel),
      ),
      body: Center(
        child: _ready
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                  const SizedBox(height: 8),
                  VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true,
                    colors: const VideoProgressColors(
                      playedColor: AppTheme.accent,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ],
              )
            : const CircularProgressIndicator(),
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
}
