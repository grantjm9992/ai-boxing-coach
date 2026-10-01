import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:sparring_pose/sparring_pose.dart';

import '../../services/app_foreground.dart';
import '../../services/debug_log.dart';
import 'multi_pose.dart';

/// Extracts a sparring round's multi-pose frames from its clip, on the
/// `sparring_pose` plugin.
abstract class SparringPoseSource {
  Future<MultiPoseRound> extract(
    String videoPath, {
    void Function(double fraction)? onProgress,
  });
}

/// The real source: provisions the full pose model, runs the native
/// extractor at [sampleEvery] and collects the streamed batches.
class SparringPoseService implements SparringPoseSource {
  SparringPoseService({SparringPoseExtractor? extractor})
    : _extractor = extractor ?? SparringPoseExtractor();

  final SparringPoseExtractor _extractor;

  /// 20 fps: identity tracking gets unreliable much below that, and two
  /// bodies per frame on the full model already cost ~2× a shadow round.
  static const Duration sampleEvery = Duration(milliseconds: 50);

  /// A silent native stream (in the foreground) fails after this long.
  static const Duration stallLimit = Duration(seconds: 60);

  /// The full model: two smaller figures in a landscape frame need it.
  static const String modelAsset = 'assets/models/pose_landmarker_full.task';

  // One extraction at a time: the native side is one shared worker.
  static Future<void> _gate = Future<void>.value();

  @override
  Future<MultiPoseRound> extract(
    String videoPath, {
    void Function(double fraction)? onProgress,
  }) async {
    final previous = _gate;
    final release = Completer<void>();
    _gate = release.future;
    await previous;
    try {
      return await _run(videoPath, onProgress);
    } finally {
      release.complete();
    }
  }

  Future<MultiPoseRound> _run(String videoPath, void Function(double)? onProgress) async {
    final name = videoPath.split('/').last;
    void trace(String s) => DebugLog.instance.log('$name $s', tag: 'sparring');
    final modelPath = await _provisionModel();
    final stopwatch = Stopwatch()..start();
    final frames = <MultiPoseFrame>[];
    final done = Completer<void>();
    var lastEvent = DateTime.now();

    final watchdog = Timer.periodic(const Duration(seconds: 5), (timer) {
      final silent = DateTime.now().difference(lastEvent);
      if (silent < stallLimit || done.isCompleted) return;
      if (AppForeground.instance.foregroundFor() < stallLimit) return; // paused by the OS
      done.completeError(TimeoutException('Pose extraction stalled', stallLimit));
    });

    late final StreamSubscription<SparringExtractionEvent> sub;
    sub = _extractor
        .extract(videoPath, modelPath: modelPath, sampleEvery: sampleEvery)
        .listen(
          (event) {
            lastEvent = DateTime.now();
            if (event.reset) {
              trace('native decoder restarted — dropping ${frames.length} frames');
              frames.clear();
            }
            for (final raw in event.frames) {
              frames.add(MultiPoseFrame.fromRaw(raw));
            }
            onProgress?.call(event.fraction);
            if (event.done && !done.isCompleted) done.complete();
          },
          onError: (Object error) {
            if (!done.isCompleted) done.completeError(error);
          },
          onDone: () {
            if (!done.isCompleted) done.complete();
          },
        );
    try {
      await done.future;
    } finally {
      watchdog.cancel();
      await sub.cancel();
    }
    trace('extracted ${frames.length} frames in ${stopwatch.elapsed.inSeconds}s');
    if (frames.isEmpty) {
      throw const SparringPoseException('No frames could be read from the clip.');
    }
    return MultiPoseRound(frames: frames, fps: 1000 / sampleEvery.inMilliseconds);
  }

  static Future<String> _provisionModel() async {
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/sparring_pose_landmarker_full.task');
    if (await file.exists() && await file.length() > 0) return file.path;
    final data = await rootBundle.load(modelAsset);
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file.path;
  }
}
