import 'dart:convert';

import 'round_analysis.dart';

/// The structured output contract for the advanced AI coach (brief §18).
///
/// The model is required to return JSON matching this shape. We do **not** parse
/// arbitrary prose: [AiCoachReport.tryParse] validates the structure and returns
/// null on anything malformed, so unschematic output is rejected (falls back to
/// the on-device analysis) rather than shown as if it were coaching.

/// A single prioritised issue in the AI report.
class AiPriorityIssue {
  const AiPriorityIssue({
    required this.code,
    required this.severity,
    required this.observation,
    required this.correction,
    this.confidence = 1.0,
    this.timestamps = const <double>[],
    this.whyItMatters = '',
    this.suggestedDrill = '',
  });

  /// Stable fault code (taxonomy, error_codes.dart) — identity, not display.
  final String code;
  final Severity severity;
  final double confidence;
  final List<double> timestamps;
  final String observation;
  final String whyItMatters;
  final String correction;
  final String suggestedDrill;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code,
    'severity': severity.value,
    'confidence': confidence,
    'timestamps': timestamps,
    'observation': observation,
    'why_it_matters': whyItMatters,
    'correction': correction,
    'suggested_drill': suggestedDrill,
  };

  /// Strict per-issue parse. Requires a code, a mappable severity and a
  /// correction; returns null otherwise so a bad issue can't slip through.
  static AiPriorityIssue? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, Object?>();
    final code = map['code'];
    final correction = map['correction'];
    final severity = _severityFrom(map['severity']);
    if (code is! String || code.isEmpty) return null;
    if (correction is! String || correction.isEmpty) return null;
    if (severity == null) return null;
    return AiPriorityIssue(
      code: code,
      severity: severity,
      confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
      timestamps: <double>[
        for (final t in (map['timestamps'] as List<Object?>? ?? const []))
          if (t is num) t.toDouble(),
      ],
      observation: map['observation'] as String? ?? '',
      whyItMatters: map['why_it_matters'] as String? ?? '',
      correction: correction,
      suggestedDrill: map['suggested_drill'] as String? ?? '',
    );
  }

  factory AiPriorityIssue.fromJson(Map<String, Object?> json) =>
      tryFrom(json) ??
      (throw const FormatException('invalid AiPriorityIssue'));
}

/// Per-combination feedback in the AI report (brief §10/§18).
class AiCombinationFeedback {
  const AiCombinationFeedback({
    required this.sequence,
    this.sequenceMatch = true,
    this.score,
    this.comment = '',
  });

  final List<int> sequence;
  final bool sequenceMatch;
  final int? score;
  final String comment;

  Map<String, Object?> toJson() => <String, Object?>{
    'sequence': sequence,
    'sequence_match': sequenceMatch,
    'score': score,
    'comment': comment,
  };

  static AiCombinationFeedback? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, Object?>();
    return AiCombinationFeedback(
      sequence: <int>[
        for (final n in (map['sequence'] as List<Object?>? ?? const []))
          if (n is num) n.toInt(),
      ],
      sequenceMatch: map['sequence_match'] as bool? ?? true,
      score: (map['score'] as num?)?.toInt(),
      comment: map['comment'] as String? ?? '',
    );
  }
}

/// The full structured AI coaching report.
class AiCoachReport {
  const AiCoachReport({
    required this.summary,
    this.strengths = const <String>[],
    this.priorityIssues = const <AiPriorityIssue>[],
    this.combinationFeedback = const <AiCombinationFeedback>[],
    this.nextSessionFocus = const <String>[],
  });

  final String summary;
  final List<String> strengths;
  final List<AiPriorityIssue> priorityIssues;
  final List<AiCombinationFeedback> combinationFeedback;
  final List<String> nextSessionFocus;

  Map<String, Object?> toJson() => <String, Object?>{
    'summary': summary,
    'strengths': strengths,
    'priority_issues': priorityIssues.map((i) => i.toJson()).toList(),
    'combination_feedback':
        combinationFeedback.map((c) => c.toJson()).toList(),
    'next_session_focus': nextSessionFocus,
  };

  factory AiCoachReport.fromJson(Map<String, Object?> json) =>
      _fromMap(json) ??
      (throw const FormatException('invalid AiCoachReport'));

  /// Parses a model response into a report, or returns null if it isn't valid
  /// (brief §18: reject, don't guess). Tolerates a markdown ```json fence and
  /// surrounding prose by extracting the first JSON object.
  static AiCoachReport? tryParse(String raw) {
    final jsonText = _extractJsonObject(raw);
    if (jsonText == null) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      return null;
    }
    if (decoded is! Map) return null;
    return _fromMap(decoded.cast<String, Object?>());
  }

  static AiCoachReport? _fromMap(Map<String, Object?> map) {
    final summary = map['summary'];
    if (summary is! String || summary.trim().isEmpty) return null;

    // A malformed issue rejects the whole report — we don't show a half-parsed
    // list of corrections.
    final rawIssues = map['priority_issues'];
    if (rawIssues != null && rawIssues is! List) return null;
    final issues = <AiPriorityIssue>[];
    for (final raw in (rawIssues as List<Object?>? ?? const [])) {
      final issue = AiPriorityIssue.tryFrom(raw);
      if (issue == null) return null;
      issues.add(issue);
    }

    final combos = <AiCombinationFeedback>[];
    for (final raw
        in (map['combination_feedback'] as List<Object?>? ?? const [])) {
      final c = AiCombinationFeedback.tryFrom(raw);
      if (c == null) return null;
      combos.add(c);
    }

    return AiCoachReport(
      summary: summary.trim(),
      strengths: _stringList(map['strengths']),
      priorityIssues: issues,
      combinationFeedback: combos,
      nextSessionFocus: _stringList(map['next_session_focus']),
    );
  }

  static List<String> _stringList(Object? raw) => <String>[
    for (final s in (raw as List<Object?>? ?? const []))
      if (s is String) s,
  ];
}

/// Extracts the first balanced `{...}` JSON object from [text], or null.
String? _extractJsonObject(String text) {
  final start = text.indexOf('{');
  if (start < 0) return null;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < text.length; i++) {
    final ch = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == '\\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '{') {
      depth++;
    } else if (ch == '}') {
      depth--;
      if (depth == 0) return text.substring(start, i + 1);
    }
  }
  return null;
}

/// Maps a model severity string to a [Severity]. Accepts the brief's
/// HIGH/MEDIUM/LOW (§18) as well as our own enum values. Null if unmappable.
Severity? _severityFrom(Object? raw) {
  if (raw is! String) return null;
  switch (raw.toLowerCase()) {
    case 'high':
    case 'major':
      return Severity.major;
    case 'medium':
    case 'moderate':
      return Severity.moderate;
    case 'low':
    case 'minor':
      return Severity.minor;
    case 'positive':
      return Severity.positive;
    default:
      return null;
  }
}
