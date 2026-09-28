import 'dart:async';

import 'package:flutter/material.dart';

import '../../analysis/analysis_mode.dart';
import '../../analysis/session_type.dart';
import '../../domain/imported_round.dart';
import '../../domain/round_clip.dart';
import '../../domain/shadow_round.dart';
import '../../domain/user_profile.dart';
import '../../services/analytics.dart';
import '../../services/background_analysis.dart';
import '../../services/clip_store.dart';
import '../../services/profile_store.dart';
import '../../services/session_history_store.dart';
import '../../services/video_import.dart';
import '../format.dart';
import '../theme.dart';
import 'round_capture_screen.dart';
import 'round_review_screen.dart';

/// Runs a standalone shadow-boxing round: framing check + count-in + record
/// (via [RoundCaptureScreen]), then analyse it IN THE BACKGROUND so the user can
/// start the next round without waiting. The round is filed to History and the
/// user lands on the same review screen a session round uses — video with pose
/// overlay, corrections, AI coaching, save-video and re-run. A toast fires when
/// the background analysis finishes.
///
/// [store]/[clipStore] are injectable for tests; production uses the defaults.
Future<void> startShadowRound(
  BuildContext context, {
  Duration duration = const Duration(minutes: 2),
  SessionHistoryStore? store,
  ClipStore? clipStore,
  DateTime Function()? now,
}) async {
  final at = (now ?? DateTime.now)();
  final sessionId = 'shadow_${at.millisecondsSinceEpoch}';
  final clips = clipStore ?? ClipStore();

  final capture = await Navigator.of(context).push<RoundCaptureResult>(
    MaterialPageRoute<RoundCaptureResult>(
      builder: (_) => RoundCaptureScreen(
        title: 'Shadow boxing',
        framingSubtitle:
            'A shadow round coming up. Get your whole body in frame — head to '
            'feet — so the coach can read your work.',
        sessionType: SessionType.shadowBoxing,
        maxDuration: duration,
        // Keep the video and defer analysis: the slow pose+AI+upload runs in the
        // background so the next round can start immediately.
        clipStore: clips,
        sessionId: sessionId,
        deferAnalysis: true,
      ),
    ),
  );
  if (capture == null || !context.mounted) return;

  final clip = capture.clip;
  if (clip == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Couldn't record that round — check your camera and try again.",
        ),
      ),
    );
    return;
  }

  await _fileAndAnalyse(
    clip: clip,
    sessionId: sessionId,
    durationMs: capture.durationMs,
    completedAt: at,
    label: 'Shadow boxing',
    store: store,
  );

  if (!context.mounted) return;
  await _openReview(
    context,
    clips: clips,
    sessionId: sessionId,
    onAnotherRound: () => startShadowRound(context,
        duration: duration, store: store, clipStore: clipStore, now: now),
  );
}

/// Imports an already-filmed video from the gallery as a shadow round.
///
/// Same destination as [startShadowRound] — the clip is filed to the
/// [ClipStore], the session lands in History, and the analysis runs in the
/// background at whatever [AnalysisMode] the profile is set to (offline rules,
/// key-frame AI, or Full AI review). The only difference is where the video came
/// from, so everything downstream — review, re-run, sync, export — is unchanged.
///
/// [picker], [probe], [store], [clipStore] and [analytics] are injectable so the
/// flow is testable without a gallery, a decoder or a camera.
Future<void> importShadowRound(
  BuildContext context, {
  SessionHistoryStore? store,
  ClipStore? clipStore,
  VideoPicker? picker,
  VideoProbe? probe,
  ProfileStore profileStore = const ProfileStore(),
  Analytics? analytics,
  DateTime Function()? now,
}) async {
  final picked = await (picker ?? GalleryVideoPicker()).pickFromGallery();
  if (picked == null || !context.mounted) return; // user backed out

  // Measuring needs to decode the file, which can take a beat on a long clip —
  // hold the UI with a blocking spinner rather than leave the tap looking dead.
  final measured = await _withBlockingSpinner(
    context,
    'Reading that video…',
    () => (probe ?? const PlayerVideoProbe()).duration(picked.path),
  );
  if (!context.mounted) return;

  final check = checkImportedVideo(measured);
  if (check is ImportRejected) {
    _snack(context, check.message);
    return;
  }
  final duration = (check as ImportOk).duration;

  // Which analysis the profile asks for — shown before anything is spent, since
  // the AI modes cost a weekly analysis and (Full AI) an upload.
  final profile = await profileStore.load();
  if (!context.mounted) return;
  final confirmed = await _confirmImport(
    context,
    picked: picked,
    duration: duration,
    mode: profile.analysisMode,
  );
  if (confirmed != true || !context.mounted) return;

  final at = (now ?? DateTime.now)();
  final sessionId = 'shadow_${at.millisecondsSinceEpoch}';
  final clips = clipStore ?? ClipStore();

  final clip = await fileImportedClip(
    picked,
    clips: clips,
    sessionId: sessionId,
    durationMs: duration.inMilliseconds,
    at: at,
  );
  if (clip == null) {
    if (context.mounted) {
      _snack(context, "Couldn't copy that video into the app. Check your free "
          'storage and try again.');
    }
    return;
  }
  // Past this point the video is filed, so the round is seen through even if
  // the user has navigated away — _fileAndAnalyse only needs the context for
  // the final push to the review screen.

  (analytics ?? AnalyticsScope.instance).log(
    AnalyticsEvent.shadowVideoImported,
    <String, Object?>{
      'mode': profile.analysisMode.value,
      'seconds': duration.inSeconds,
    },
  );

  await _fileAndAnalyse(
    clip: clip,
    sessionId: sessionId,
    durationMs: duration.inMilliseconds.toDouble(),
    completedAt: at,
    label: 'Imported round',
    templateName: 'Shadow boxing (imported)',
    roundTitle: 'Imported round',
    profile: profile,
    store: store,
  );

  if (!context.mounted) return;
  // No "Another round" here: that action means *record* one. Importing again is
  // a tap away on Home.
  await _openReview(context, clips: clips, sessionId: sessionId);
}

/// The tail both paths share, and the half of it that needs no UI: file the
/// session to History so it shows up at once, then kick the slow pose+AI+sync
/// off the critical path at whatever [AnalysisMode] the profile is set to.
///
/// Deliberately context-free — once the clip is on disk the round is seen
/// through whether or not the user is still looking at the screen that started
/// it. [BackgroundAnalysis] toasts them when it lands.
Future<void> _fileAndAnalyse({
  required RoundClip clip,
  required String sessionId,
  required double durationMs,
  required DateTime completedAt,
  required String label,
  String templateName = 'Shadow boxing',
  String roundTitle = 'Shadow round',
  UserProfile? profile,
  SessionHistoryStore? store,
}) async {
  // File the session now (pending summary) so it shows in History immediately;
  // the background analysis + cloud sync fill in the detail.
  final record = shadowSessionRecord(
    null,
    durationMs: durationMs,
    sessionId: sessionId,
    completedAt: completedAt,
    templateName: templateName,
    roundTitle: roundTitle,
  );
  await (store ?? SessionHistoryStore()).save(record);

  // Analyse off the critical path: pose + AI + keyframes + cloud sync, with a
  // toast on completion. BackgroundAnalysis reads the profile's AnalysisMode
  // itself, so an imported round gets exactly the treatment a recorded one does.
  final resolved = profile ?? await const ProfileStore().load();
  final drill = resolved.toDrill(sessionType: SessionType.shadowBoxing);
  BackgroundAnalysis.instance
      .analyse(clip,
          drill: drill, label: label, finalizeRollup: record.rollupJson)
      .ignore();
}

/// Lands the user on the same review a full session uses — watch back with the
/// pose overlay, corrections, AI, save video, and re-run. It reflects the
/// background analysis as it completes.
Future<void> _openReview(
  BuildContext context, {
  required ClipStore clips,
  required String sessionId,
  VoidCallback? onAnotherRound,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => RoundReviewScreen(
        clipStore: clips,
        sessionId: sessionId,
        onAnotherRound: onAnotherRound,
      ),
    ),
  );
}

/// The pre-flight sheet: what was picked, how long it is, and — the point of it
/// — which analysis the profile will spend on it.
Future<bool?> _confirmImport(
  BuildContext context, {
  required PickedVideo picked,
  required Duration duration,
  required AnalysisMode mode,
}) async {
  final sizeBytes = await picked.sizeBytes();
  if (!context.mounted) return false;
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text(
              'Import as a shadow round',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              picked.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              <String>[
                TimeFormat.clock(duration),
                if (sizeBytes != null) _megabytes(sizeBytes),
              ].join(' · '),
              style: const TextStyle(color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceAlt,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.auto_awesome,
                          size: 18, color: AppTheme.accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          mode.label,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    mode.blurb,
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      height: 1.35,
                      fontSize: 13,
                    ),
                  ),
                  if (mode.usesAi) ...<Widget>[
                    const SizedBox(height: 6),
                    const Text(
                      'Uses one of your weekly AI analyses. Change this in '
                      'Profile → Analysis.',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Best results when your whole body — head to feet — is in frame '
              'for the whole clip.',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(sheetContext).pop(true),
              icon: const Icon(Icons.insights),
              label: const Text('Analyse this round'),
            ),
            TextButton(
              onPressed: () => Navigator.of(sheetContext).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Runs [work] behind a modal spinner, dismissing it whatever the outcome.
Future<T> _withBlockingSpinner<T>(
  BuildContext context,
  String label,
  Future<T> Function() work,
) async {
  // The root navigator is where showDialog puts the route, and the finally
  // block below has to pop the one it actually pushed.
  final navigator = Navigator.of(context, rootNavigator: true);
  // Not awaited on purpose: the dialog stays up until the finally block pops it.
  // The push is synchronous, so the route exists before `work` is awaited.
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      content: Row(
        children: <Widget>[
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(label)),
        ],
      ),
    ),
  ).ignore();
  try {
    return await work();
  } finally {
    if (navigator.canPop()) navigator.pop();
  }
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String _megabytes(int bytes) =>
    '${(bytes / (1024 * 1024)).toStringAsFixed(bytes < 1024 * 1024 * 10 ? 1 : 0)} MB';
