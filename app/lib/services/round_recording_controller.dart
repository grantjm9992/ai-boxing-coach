import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/round_clip.dart';
import '../domain/session_phase.dart';
import '../domain/session_plan.dart';
import 'clip_store.dart';
import 'round_recorder.dart';

/// Which segments get recorded. v0.5 stage 0.2 records **technical work rounds
/// only** — the phase whose whole point is one technique done properly, and the
/// one the spec's v1 detections (guard return, punch retraction) are about. Rest
/// periods, warm-ups and conditioning are left alone.
///
/// A pure function so the decision can be unit-tested without a camera.
bool shouldRecordSegment(SessionSegment? segment) =>
    segment != null &&
    segment.isWork &&
    segment.phase == SessionPhase.technical;

/// Turns the session's segment transitions into camera start/stop calls, and
/// files each finished recording in the [ClipStore].
///
/// It owns no clock and no timer — it is driven by [onSegment], which the
/// session screen calls whenever the engine's current segment changes. That
/// keeps it a plain state machine over [RoundRecorder] + [ClipStore], testable
/// with [FakeRoundRecorder] and a temp-dir store.
class RoundRecordingController {
  RoundRecordingController({
    required this.recorder,
    required this.clipStore,
    required this.sessionId,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final RoundRecorder recorder;
  final ClipStore clipStore;

  /// Identifies this session run, so a review screen can gather its clips.
  final String sessionId;

  final DateTime Function() _now;

  /// Recordings shorter than this are thrown away rather than filed. They come
  /// from segments that started and ended almost immediately — skipping through
  /// rounds while setting up, mostly — and produce empty or unplayable files
  /// that are only clutter in the review screen. A real technical round is
  /// minutes long, so this never touches a genuine recording.
  static const Duration minClipDuration = Duration(seconds: 2);

  SessionSegment? _recordingSegment;
  DateTime? _startedAt;

  bool get isRecording => _recordingSegment != null;

  /// Reacts to the current segment becoming [segment]. Stops any recording that
  /// no longer matches the current segment, then starts one if the new segment
  /// should be recorded. Safe to call repeatedly with the same segment.
  Future<void> onSegment(SessionSegment? segment) async {
    final recording = _recordingSegment;
    if (recording != null && recording.index != segment?.index) {
      await _stopAndSave();
    }
    if (_recordingSegment == null && shouldRecordSegment(segment)) {
      await _start(segment!);
    }
  }

  /// Stops and files any recording in progress. Called when the session ends or
  /// the screen is torn down, so the last technical round is not lost.
  Future<void> finish() => _stopAndSave();

  Future<void> _start(SessionSegment segment) async {
    try {
      if (!recorder.isReady) await recorder.initialize();
      await recorder.startRecording();
      _recordingSegment = segment;
      _startedAt = _now();
    } on RecorderUnavailable catch (error) {
      // No camera / no permission: the session goes on uncoached, exactly as it
      // did before v0.5. Recording is additive, never a blocker.
      debugPrint('Skipping recording for segment ${segment.index}: $error');
    }
  }

  Future<void> _stopAndSave() async {
    final segment = _recordingSegment;
    _recordingSegment = null;
    final startedAt = _startedAt;
    _startedAt = null;
    if (segment == null) return;

    final tempPath = await recorder.stopRecording();
    if (tempPath == null) return;

    final recordedAt = startedAt ?? _now();
    final durationMs = _now().difference(recordedAt).inMilliseconds;

    // Drop recordings that are too short or empty rather than filing a broken
    // entry — see [minClipDuration].
    final tempFile = File(tempPath);
    final empty = !await tempFile.exists() || await tempFile.length() == 0;
    if (durationMs < minClipDuration.inMilliseconds || empty) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } on Object catch (_) {
          // Nothing we can do; it will be swept eventually if it lands in clips.
        }
      }
      return;
    }

    final target = await clipStore.allocatePath(sessionId, segment.index);
    final moved = await _move(tempPath, target);
    if (!moved) return;

    await clipStore.add(
      RoundClip(
        sessionId: sessionId,
        segmentIndex: segment.index,
        phase: segment.phase,
        path: target,
        recordedAt: recordedAt,
        roundNumber: segment.roundNumber,
        roundsInPhase: segment.roundsInPhase,
        durationMs: durationMs,
        title: segment.title,
      ),
    );
  }

  /// Moves the camera's temp file to its permanent path. Tries a rename first
  /// (cheap, same-volume) and falls back to copy+delete across volumes.
  Future<bool> _move(String from, String to) async {
    final source = File(from);
    if (!await source.exists()) return false;
    try {
      await source.rename(to);
      return true;
    } on FileSystemException {
      try {
        await source.copy(to);
        await source.delete();
        return true;
      } on Object catch (error) {
        debugPrint('Could not move clip $from -> $to: $error');
        return false;
      }
    }
  }
}
