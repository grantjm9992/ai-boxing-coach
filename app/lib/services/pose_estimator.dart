import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pose_landmarker/pose_landmarker.dart';

import '../analysis/pose.dart';
import '../analysis/pose_estimation.dart';

/// Progress of a pose-estimation run, and — when done — its result.
class PoseAnalysisProgress {
  const PoseAnalysisProgress({required this.fraction, this.result});

  final double fraction; // 0..1
  final PoseAnalysisResult? result;

  bool get isDone => result != null;
}

/// The outcome of estimating pose over one clip: the sequence the rules consume,
/// plus the mechanical facts stage 0.3 surfaces (no coaching yet).
class PoseAnalysisResult {
  const PoseAnalysisResult({
    required this.sequence,
    required this.framesAnalysed,
    required this.fullBodyVisibleFraction,
    required this.elapsed,
  });

  final PoseSequence sequence;
  final int framesAnalysed;
  final double fullBodyVisibleFraction; // 0..1
  final Duration elapsed;
}

/// Runs pose estimation over a recorded clip. The app talks to this interface so
/// the rest-period flow can be driven by a fake in tests, and so a no-camera
/// platform degrades cleanly.
abstract class PoseEstimator {
  Stream<PoseAnalysisProgress> analyse(
    String videoPath, {
    Duration sampleEvery,
    PoseModel model,
  });
}

/// The real estimator: provisions the model, then drives the `pose_landmarker`
/// plugin and maps its raw output into a [PoseSequence] with the stage-0.3 stats.
class MediaPipePoseEstimator implements PoseEstimator {
  MediaPipePoseEstimator({
    PoseLandmarker? landmarker,
    PoseModelProvisioner? provisioner,
  }) : _landmarker = landmarker ?? PoseLandmarker(),
       _provisioner = provisioner ?? const PoseModelProvisioner();

  final PoseLandmarker _landmarker;
  final PoseModelProvisioner _provisioner;

  @override
  Stream<PoseAnalysisProgress> analyse(
    String videoPath, {
    Duration sampleEvery = const Duration(milliseconds: 33),
    PoseModel model = PoseModel.lite,
  }) async* {
    final modelPath = await _provisioner.ensureModel(model);
    final stopwatch = Stopwatch()..start();
    final fps = sampleEvery.inMilliseconds > 0
        ? 1000.0 / sampleEvery.inMilliseconds
        : 30.0;

    final stream = _landmarker.estimate(
      videoPath,
      modelPath: modelPath,
      sampleEvery: sampleEvery,
      model: model,
    );

    await for (final progress in stream) {
      final rawFrames = progress.frames;
      if (rawFrames == null) {
        yield PoseAnalysisProgress(fraction: progress.fraction);
        continue;
      }
      final sequence = rawFramesToSequence(
        rawFrames,
        fps: fps,
        source: 'mediapipe/${model.name}',
        meta: <String, Object?>{
          'model': 'pose_landmarker_${model.name}',
          'sampleEveryMs': sampleEvery.inMilliseconds,
        },
      );
      yield PoseAnalysisProgress(
        fraction: 1,
        result: PoseAnalysisResult(
          sequence: sequence,
          framesAnalysed: sequence.length,
          fullBodyVisibleFraction: fullBodyVisibleFraction(sequence),
          elapsed: stopwatch.elapsed,
        ),
      );
    }
  }
}

/// Copies the bundled `.task` model out of Flutter assets to a real file, which
/// is what MediaPipe's model loader wants. Cached after the first run.
class PoseModelProvisioner {
  const PoseModelProvisioner();

  static String assetFor(PoseModel model) =>
      'assets/models/pose_landmarker_${model.name}.task';

  Future<String> ensureModel(PoseModel model) async {
    final name = 'pose_landmarker_${model.name}.task';
    final dir = await getApplicationSupportDirectory();
    final file = File('${dir.path}/$name');
    if (await file.exists() && await file.length() > 0) return file.path;
    final data = await rootBundle.load(assetFor(model));
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file.path;
  }
}
