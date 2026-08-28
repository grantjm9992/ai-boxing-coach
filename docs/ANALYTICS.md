# Analytics & validation

The V2 event taxonomy and the regression-dataset scaffold (brief §23, §26).
There is intentionally **no third-party tracker wired yet** — the event stream is
real and inspectable, ready to point at a sink when one is chosen.

Code: `app/lib/services/analytics.dart`,
`app/lib/analysis/regression_dataset.dart`.

## Events

`AnalyticsEvent` enumerates the §23 events with stable wire names (identity — add
events, don't rename):

`session_started`, `session_completed`, `analysis_started`,
`analysis_completed`, `analysis_failed`, `shadow_boxing_started`,
`technical_round_started`, `combination_selected`,
`combination_attempt_detected`, `combination_match_success`,
`combination_match_failure`, `advanced_analysis_requested`, `feedback_viewed`,
`video_example_viewed`.

The app talks only to the `Analytics` sink interface:

- `LoggingAnalytics` — the default; prints in debug, no-op in release.
- `FakeAnalytics` — records events for test assertions.
- `AnalyticsScope.instance` — the app-wide sink, swappable in tests, so call
  sites stay free of dependency plumbing.

Wired at natural points: `RoundAnalyzer` (analysis started / completed / failed,
advanced-request), the combination detail screen (`combination_selected`), and
the drill screen (`technical_round_started`, and per attempt
`combination_attempt_detected` + `combination_match_success|failure`).

## Regression dataset

`RegressionCase` is one labelled clip — `{video, expected_punches, known_issues}`
— and `RegressionDataset` loads/dumps a JSON list of them. Two accuracy measures
track combination classification as the algorithm changes:

- `sequenceMatchAccuracy` — fraction of clips whose detected sequence exactly
  matches the expected one (the headline number);
- `punchTokenAccuracy` — fraction of individual punch positions classified
  correctly (a more forgiving measure for tuning).

The clips and labels are collected over time; this is the model + scoring so the
data has somewhere to live and a way to be judged.
