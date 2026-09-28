import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../domain/round_clip.dart';
import '../domain/session_phase.dart';
import 'clip_store.dart';

/// Picking a video off the device and measuring it — the two plugin-backed
/// steps of importing an already-filmed round. Both are interfaces so the
/// import flow is testable without a gallery or a decoder.

/// A file the user chose from their gallery.
class PickedVideo {
  const PickedVideo({required this.path, required this.name});

  /// Absolute path to the file the picker handed us. On Android this is a copy
  /// in the app's cache, not the original in the media store.
  final String path;

  /// The original file name, for showing back to the user.
  final String name;

  /// Lower-case extension without the dot (`mp4`, `mov`), defaulting to `mp4`
  /// when the name carries none. The clip keeps this so the Full AI review
  /// upload declares the right mime type.
  String get extension {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'mp4';
    final ext = path.substring(dot + 1).toLowerCase();
    return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(ext) ? ext : 'mp4';
  }

  /// Size on disk in bytes, or null if it can't be read.
  Future<int?> sizeBytes() async {
    try {
      return await File(path).length();
    } on Object {
      return null;
    }
  }
}

abstract class VideoPicker {
  /// Opens the gallery. Null when the user backs out without choosing.
  Future<PickedVideo?> pickFromGallery();
}

/// Real picker — the system photo picker (Android Photo Picker / iOS PHPicker),
/// neither of which needs a storage permission.
class GalleryVideoPicker implements VideoPicker {
  GalleryVideoPicker({ImagePicker? picker}) : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  @override
  Future<PickedVideo?> pickFromGallery() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return null;
    return PickedVideo(path: file.path, name: file.name);
  }
}

/// Returns a canned file; records that it was asked. The test double.
class FakeVideoPicker implements VideoPicker {
  FakeVideoPicker(this.video);

  final PickedVideo? video;
  int calls = 0;

  @override
  Future<PickedVideo?> pickFromGallery() async {
    calls++;
    return video;
  }
}

/// Reads a video file's length without playing it.
abstract class VideoProbe {
  /// The clip's duration, or null if the file couldn't be opened or decoded.
  Future<Duration?> duration(String path);
}

/// Real probe, via `video_player` — the decoder already shipped for the review
/// screen, so no new native dependency.
class PlayerVideoProbe implements VideoProbe {
  const PlayerVideoProbe();

  @override
  Future<Duration?> duration(String path) async {
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      final value = controller.value;
      if (!value.isInitialized) return null;
      final d = value.duration;
      return d <= Duration.zero ? null : d;
    } on Object {
      return null;
    } finally {
      await controller.dispose();
    }
  }
}

/// Answers with a fixed duration. The test double.
class FakeVideoProbe implements VideoProbe {
  const FakeVideoProbe(this.value);

  final Duration? value;

  @override
  Future<Duration?> duration(String path) async => value;
}

/// Moves a picked video into the managed [ClipStore] and indexes it as round 1
/// of [sessionId], so everything downstream — review, re-analysis, retention
/// sweep, cloud sync — treats it exactly like a recorded round.
///
/// The picker hands over a copy in the app's cache, so a rename suffices on the
/// same volume; copy (then drop the source) covers a cross-mount cache. Returns
/// null if the file couldn't be filed at all.
///
/// [at] is the import moment, not when the video was filmed: History orders by
/// it and the 7-day retention sweep counts from it, so a clip filmed last month
/// still gets its full week in the review screen.
Future<RoundClip?> fileImportedClip(
  PickedVideo picked, {
  required ClipStore clips,
  required String sessionId,
  required int durationMs,
  required DateTime at,
  String title = 'Imported round',
}) async {
  try {
    final target =
        await clips.allocatePath(sessionId, 0, extension: picked.extension);
    final source = File(picked.path);
    try {
      await source.rename(target);
    } on FileSystemException {
      await source.copy(target);
      try {
        await source.delete(); // the cache copy; the gallery original is safe
      } on FileSystemException {
        // Cache cleanup is best-effort.
      }
    }
    final clip = RoundClip(
      sessionId: sessionId,
      segmentIndex: 0,
      phase: SessionPhase.shadow,
      path: target,
      recordedAt: at,
      roundNumber: 1,
      durationMs: durationMs,
      title: title,
    );
    await clips.add(clip);
    return clip;
  } on Object {
    return null;
  }
}
