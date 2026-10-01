import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../domain/user_profile.dart';
import '../../services/ai/vision_model.dart';
import '../../services/debug_log.dart';
import '../../services/keep_awake.dart';
import '../../services/profile_store.dart';
import '../ai/sparring_coach.dart';
import '../ai/sparring_prompt.dart';
import '../ai/sparring_review.dart';
import '../analysis/fighter_analysis.dart';
import '../analysis/sparring_analyzer.dart';
import '../data/sparring_store.dart';
import '../data/sparring_sync.dart';
import '../model/fighter.dart';
import '../model/sparring_session.dart';
import '../pose/multi_pose.dart';
import '../pose/sparring_pose_service.dart';
import '../tracking/fighter_tracker.dart';
import '../tracking/identity_linker.dart';

/// What a running sparring job is doing, for the UI.
class SparringJobProgress {
  const SparringJobProgress({
    required this.status,
    required this.startedAt,
    this.fraction,
  });

  final SparringRoundStatus status;
  final DateTime startedAt;

  /// 0..1 when the stage can measure itself.
  final double? fraction;
}

/// Sparring's background work, separate from the single-person
/// `BackgroundAnalysis`: per round, extract every body → track both fighters →
/// measure each and the two together → (optionally) the AI coach's review →
/// save → sync. One job at a time, with the screen kept awake (the same
/// pattern as the single-person pipeline, its own state).
///
/// Also re-applies identity: the user saying which fighter they are, or
/// swapping a tracklet, re-tracks from the stored frames in a second — no
/// re-extraction, and the AI review isn't re-run unless asked.
class SparringJobs {
  SparringJobs({
    SparringStore? store,
    SparringPoseSource? poseSource,
    SparringCoach? Function()? coach,
    Future<UserProfile> Function()? profile,
    SparringSyncQueue? sync,
    FighterTracker tracker = const FighterTracker(),
    SparringAnalyzer analyzer = const SparringAnalyzer(),
  }) : _store = store ?? SparringStore(),
       _poseSource = poseSource,
       _coach = coach ?? SparringCoach.resolve,
       _profile = profile ?? (() => const ProfileStore().load()),
       _sync = sync,
       _tracker = tracker,
       _analyzer = analyzer;

  static final SparringJobs instance = SparringJobs();

  final SparringStore _store;
  SparringPoseSource? _poseSource;
  final SparringCoach? Function() _coach;
  final Future<UserProfile> Function() _profile;
  final SparringSyncQueue? _sync;
  final FighterTracker _tracker;
  final SparringAnalyzer _analyzer;

  SparringPoseSource get _pose => _poseSource ??= SparringPoseService();
  SparringSyncQueue get _syncQueue => _sync ?? SparringSyncQueue.instance;

  /// Running and queued rounds, keyed by [key].
  final ValueNotifier<Map<String, SparringJobProgress>> progress =
      ValueNotifier<Map<String, SparringJobProgress>>(const <String, SparringJobProgress>{});

  static String key(String sessionId, int round) => '$sessionId#$round';

  final List<Future<void> Function()> _queue = <Future<void> Function()>[];
  bool _working = false;
  Completer<void>? _idle;

  /// Completes when the queue is empty (tests, and the capture screen's
  /// "finish" can await it if it wants).
  Future<void> get idle => _working ? (_idle ??= Completer<void>()).future : Future<void>.value();

  bool isBusy(String sessionId, int round) => progress.value.containsKey(key(sessionId, round));

  /// Full processing of a freshly recorded round.
  void enqueueRound(String sessionId, int round) {
    _setProgress(sessionId, round, SparringRoundStatus.recorded, null);
    _push(() => _processRound(sessionId, round));
  }

  /// Re-track and re-measure from stored frames (after a who's-who change).
  /// An existing AI review is kept when the labels didn't move, swapped when
  /// A and B flipped wholesale, and marked stale otherwise.
  void enqueueRelink(String sessionId, int round) {
    _setProgress(sessionId, round, SparringRoundStatus.tracking, null);
    _push(() => _relink(sessionId, round));
  }

  /// Runs the AI review again (e.g. after correcting who's who).
  void enqueueAiReview(String sessionId, int round) {
    _setProgress(sessionId, round, SparringRoundStatus.reviewing, null);
    _push(() => _aiOnly(sessionId, round));
  }

  /// The user says they are [you] in [round]: the session learns what they
  /// and their partner look like (A = user from now on) and every round is
  /// re-linked against that.
  Future<void> identify(String sessionId, int round, FighterLabel you) async {
    final tracked = await _store.loadTracked(sessionId, round);
    if (tracked == null) return;
    final mine = tracked.templates[you];
    final theirs = tracked.templates[you.other];
    if (mine == null || theirs == null) return;
    final session = await _store.update(sessionId, (s) => s.copyWith(
      identified: true,
      templates: <FighterLabel, IdentityTemplate>{FighterLabel.a: mine, FighterLabel.b: theirs},
    ));
    if (session == null) return;
    for (final r in session.rounds) {
      if (r.number == round) {
        // This round's labels flip wholesale if the user was B; its own
        // decisions are kept relative to the new labels.
        if (you == FighterLabel.b) {
          final decisions = await _store.loadDecisions(sessionId, round);
          await _store.saveDecisions(sessionId, round, <int, FighterLabel?>{
            for (final e in decisions.entries) e.key: e.value?.other,
          });
        }
        enqueueRelink(sessionId, round);
      } else if (r.status == SparringRoundStatus.done || r.status == SparringRoundStatus.failed) {
        // Linked without the reference before: let the reference decide.
        await _store.saveDecisions(sessionId, r.number, const <int, FighterLabel?>{});
        enqueueRelink(sessionId, r.number);
      }
    }
  }

  /// Forces one tracklet's label (the user's "swap" / "this is …"). A swap
  /// between the fighters is a swap: whoever held [label] alongside that
  /// tracklet takes its old label, so both are corrected at once.
  Future<void> decide(String sessionId, int round, int trackletId, FighterLabel? label) async {
    final decisions = Map<int, FighterLabel?>.of(await _store.loadDecisions(sessionId, round));
    decisions[trackletId] = label;
    final tracked = await _store.loadTracked(sessionId, round);
    TrackletInfo? info;
    for (final t in tracked?.tracklets ?? const <TrackletInfo>[]) {
      if (t.id == trackletId) info = t;
    }
    final previous = info?.label;
    if (info != null && label != null && previous != null && previous != label) {
      for (final t in tracked!.tracklets) {
        if (t.id == trackletId || t.label != label) continue;
        if (t.start <= info.end && info.start <= t.end) decisions[t.id] = previous;
      }
    }
    await _store.saveDecisions(sessionId, round, decisions);
    enqueueRelink(sessionId, round);
  }

  /// Confirms the tracker's label for a tracklet without changing it.
  Future<void> confirm(String sessionId, int round, TrackletInfo tracklet) =>
      decide(sessionId, round, tracklet.id, tracklet.label);

  // -- queue ------------------------------------------------------------------

  void _push(Future<void> Function() job) {
    _queue.add(job);
    if (!_working) unawaited(_drain());
  }

  Future<void> _drain() async {
    _working = true;
    final release = KeepAwake.instance.acquire('sparring analysis');
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeAt(0);
        try {
          await job();
        } on Object catch (error, stack) {
          DebugLog.instance.log('sparring job failed: $error\n$stack', tag: 'sparring');
        }
      }
    } finally {
      release();
      _working = false;
      _idle?.complete();
      _idle = null;
    }
    unawaited(_syncQueue.process().catchError((Object _) {}));
  }

  void _setProgress(String sessionId, int round, SparringRoundStatus status, double? fraction) {
    final k = key(sessionId, round);
    final current = progress.value[k];
    progress.value = <String, SparringJobProgress>{
      ...progress.value,
      k: SparringJobProgress(
        status: status,
        fraction: fraction,
        startedAt: current?.status == status ? current!.startedAt : DateTime.now(),
      ),
    };
  }

  void _clearProgress(String sessionId, int round) {
    final next = Map<String, SparringJobProgress>.of(progress.value)..remove(key(sessionId, round));
    progress.value = next;
  }

  Future<void> _status(String sessionId, int round, SparringRoundStatus status,
      {String? error, double? durationMs}) async {
    if (status.isBusy) _setProgress(sessionId, round, status, null);
    await _store.update(sessionId, (s) {
      final r = s.round(round);
      if (r == null) return s;
      return s.withRound(r.copyWith(
        status: status,
        error: error,
        clearError: error == null,
        durationMs: durationMs,
      ));
    });
  }

  // -- jobs -------------------------------------------------------------------

  Future<void> _processRound(String sessionId, int round) async {
    void trace(String s) => DebugLog.instance.log('$sessionId/r$round $s', tag: 'sparring');
    try {
      var frames = await _store.loadFrames(sessionId, round);
      if (frames == null) {
        await _status(sessionId, round, SparringRoundStatus.extracting);
        final clip = await _store.clipPath(sessionId, round);
        frames = await _pose.extract(
          clip,
          onProgress: (f) => _setProgress(sessionId, round, SparringRoundStatus.extracting, f),
        );
        await _store.saveFrames(sessionId, round, frames);
      }
      final analysis = await _trackAndMeasure(sessionId, round, frames);
      if (analysis == null) return;
      await _maybeAi(sessionId, round, analysis);
      await _status(sessionId, round, SparringRoundStatus.done,
          durationMs: analysis.durationMs);
      await _syncQueue.enqueue(sessionId, round);
      trace('done');
    } on Object catch (error) {
      trace('failed: $error');
      await _status(sessionId, round, SparringRoundStatus.failed, error: _brief(error));
    } finally {
      _clearProgress(sessionId, round);
    }
  }

  /// Tracks and measures [frames]; saves both. Null if the session is gone.
  Future<SparringRoundAnalysis?> _trackAndMeasure(
    String sessionId,
    int round,
    MultiPoseRound frames,
  ) async {
    final session = await _store.loadSession(sessionId);
    if (session == null) return null;
    await _status(sessionId, round, SparringRoundStatus.tracking);
    final decisions = await _store.loadDecisions(sessionId, round);
    final tracked = _tracker.track(
      frames,
      forced: decisions,
      reference: session.identified && session.templates.length == 2 ? session.templates : null,
    );
    await _store.saveTracked(sessionId, round, tracked);

    await _status(sessionId, round, SparringRoundStatus.analysing);
    final analysis = _analyzer.analyse(tracked, setups: await _setups(session));
    await _store.saveAnalysis(sessionId, round, analysis);
    return analysis;
  }

  Future<Map<FighterLabel, FighterSetup>> _setups(SparringSession session) async {
    if (!session.identified) return const <FighterLabel, FighterSetup>{};
    final profile = await _profile();
    return <FighterLabel, FighterSetup>{
      FighterLabel.a: FighterSetup(
        stance: profile.stance,
        style: profile.style,
        school: profile.school,
      ),
    };
  }

  Future<void> _maybeAi(String sessionId, int round, SparringRoundAnalysis analysis, {bool force = false}) async {
    final session = await _store.loadSession(sessionId);
    if (session == null) return;
    if (!force && !session.settings.aiReview) return;
    final coach = _coach();
    if (coach == null) {
      await _store.saveAnalysis(sessionId, round,
          analysis.copyWith(aiError: 'Sign in to get the AI coach’s review.'));
      return;
    }
    final tracked = await _store.loadTracked(sessionId, round);
    if (tracked == null) return;
    await _status(sessionId, round, SparringRoundStatus.reviewing);
    final request = SparringPrompt.request(
      session: session,
      roundNumber: round,
      tracked: tracked,
      analysis: analysis,
      videoPath: await _store.clipPath(sessionId, round),
      setups: await _setups(session),
    );
    try {
      final reviewed = await coach.review(
        request,
        analysis,
        onProgress: (phase, f) =>
            _setProgress(sessionId, round, SparringRoundStatus.reviewing, f),
      );
      await _store.saveAnalysis(sessionId, round, reviewed);
    } on VisionModelException catch (error) {
      await _store.saveAnalysis(sessionId, round, analysis.copyWith(aiError: error.message));
    } on Object catch (error) {
      await _store.saveAnalysis(sessionId, round, analysis.copyWith(aiError: _brief(error)));
    }
  }

  Future<void> _relink(String sessionId, int round) async {
    try {
      final frames = await _store.loadFrames(sessionId, round);
      if (frames == null) return;
      final previous = await _store.loadAnalysis(sessionId, round);
      final before = await _store.loadTracked(sessionId, round);
      final fresh = await _trackAndMeasure(sessionId, round, frames);
      if (fresh == null) return;
      final ai = previous?.ai;
      if (ai != null) {
        final after = await _store.loadTracked(sessionId, round);
        final mapping = before == null || after == null
            ? LabelMapping.changed
            : compareLabels(before, after);
        final report = mapping == LabelMapping.swapped ? ai.swapped() : ai;
        final applied = SparringReview.apply(fresh, report);
        await _store.saveAnalysis(
          sessionId,
          round,
          applied.copyWith(aiStale: mapping == LabelMapping.changed || previous!.aiStale),
        );
      }
      await _status(sessionId, round, SparringRoundStatus.done, durationMs: fresh.durationMs);
      await _syncQueue.enqueue(sessionId, round);
    } on Object catch (error) {
      await _status(sessionId, round, SparringRoundStatus.failed, error: _brief(error));
    } finally {
      _clearProgress(sessionId, round);
    }
  }

  Future<void> _aiOnly(String sessionId, int round) async {
    try {
      final analysis = await _store.loadAnalysis(sessionId, round);
      if (analysis == null) return;
      await _maybeAi(sessionId, round, analysis.copyWith(clearAiError: true), force: true);
      await _status(sessionId, round, SparringRoundStatus.done, durationMs: analysis.durationMs);
      await _syncQueue.enqueue(sessionId, round);
    } on Object catch (error) {
      await _status(sessionId, round, SparringRoundStatus.failed, error: _brief(error));
    } finally {
      _clearProgress(sessionId, round);
    }
  }

  static String _brief(Object error) {
    final text = '$error';
    return text.length > 300 ? '${text.substring(0, 300)}…' : text;
  }
}

/// How a re-track's labels relate to the previous ones.
enum LabelMapping { same, swapped, changed }

/// Compares two trackings of the same frames: [LabelMapping.same] when A is
/// still the same body (hip within 1% of the frame) on nearly every frame both
/// resolve, [LabelMapping.swapped] when A is now the old B, else changed.
LabelMapping compareLabels(TrackedRound before, TrackedRound after, {double agree = 0.97}) {
  var same = 0, swapped = 0, compared = 0;
  final n = before.frameCount < after.frameCount ? before.frameCount : after.frameCount;
  List<double>? hip(TrackedRound r, FighterLabel l, int p) =>
      PoseCandidate(keypoints: r.fighters[l]!.frames[p].keypoints).hip;
  bool near(List<double>? x, List<double>? y) =>
      x != null && y != null && (x[0] - y[0]).abs() < 0.01 && (x[1] - y[1]).abs() < 0.01;
  for (var p = 0; p < n; p++) {
    for (final label in FighterLabel.values) {
      final now = hip(after, label, p);
      if (now == null) continue;
      final wasSame = hip(before, label, p);
      final wasOther = hip(before, label.other, p);
      if (wasSame == null && wasOther == null) continue;
      compared++;
      if (near(now, wasSame)) {
        same++;
      } else if (near(now, wasOther)) {
        swapped++;
      }
    }
  }
  if (compared == 0) return LabelMapping.changed;
  if (same / compared >= agree) return LabelMapping.same;
  if (swapped / compared >= agree) return LabelMapping.swapped;
  return LabelMapping.changed;
}
