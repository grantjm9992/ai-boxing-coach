import 'package:flutter/foundation.dart';

/// V2 analytics events (brief §23). Stable wire names — treated as identity by
/// any downstream sink, so add events but don't rename them.
enum AnalyticsEvent {
  sessionStarted('session_started'),
  sessionCompleted('session_completed'),
  analysisStarted('analysis_started'),
  analysisCompleted('analysis_completed'),
  analysisFailed('analysis_failed'),
  shadowBoxingStarted('shadow_boxing_started'),
  technicalRoundStarted('technical_round_started'),
  combinationSelected('combination_selected'),
  combinationAttemptDetected('combination_attempt_detected'),
  combinationMatchSuccess('combination_match_success'),
  combinationMatchFailure('combination_match_failure'),
  advancedAnalysisRequested('advanced_analysis_requested'),
  feedbackViewed('feedback_viewed'),
  videoExampleViewed('video_example_viewed');

  const AnalyticsEvent(this.name);

  /// Wire name for the sink.
  final String name;
}

/// A sink for analytics events. The app talks only to this; the concrete
/// destination (log, or a hosted analytics service later) is a swap of
/// implementation.
abstract class Analytics {
  void log(AnalyticsEvent event, [Map<String, Object?> properties]);
}

/// Default sink: prints in debug, no-op in release. There is intentionally no
/// third-party analytics wired yet — this makes the event stream real and
/// inspectable without shipping a tracker.
class LoggingAnalytics implements Analytics {
  const LoggingAnalytics();

  @override
  void log(AnalyticsEvent event, [Map<String, Object?> properties = const {}]) {
    if (kReleaseMode) return;
    debugPrint('analytics: ${event.name} $properties');
  }
}

/// Records events for assertions in tests.
class FakeAnalytics implements Analytics {
  final List<(AnalyticsEvent, Map<String, Object?>)> events =
      <(AnalyticsEvent, Map<String, Object?>)>[];

  @override
  void log(AnalyticsEvent event, [Map<String, Object?> properties = const {}]) {
    events.add((event, properties));
  }

  /// Every event of a given type that was logged.
  Iterable<AnalyticsEvent> get names => events.map((e) => e.$1);

  int count(AnalyticsEvent event) => events.where((e) => e.$1 == event).length;
}

/// App-wide analytics sink. Swap in tests; defaults to logging. This keeps
/// call sites free of dependency plumbing while staying injectable.
class AnalyticsScope {
  const AnalyticsScope._();

  static Analytics instance = const LoggingAnalytics();
}
