import 'dart:convert';

import '../../analysis/ai_coach_report.dart';
import '../model/fighter.dart';

/// The AI coach's structured read of one sparring round — both fighters. The
/// model must answer with JSON matching `SparringPrompt.responseSchema`;
/// anything that doesn't parse is rejected ([SparringAiReport.tryParse] returns
/// null) and the round keeps its on-device analysis.

/// The AI's read of one fighter.
class SparringAiFighter {
  const SparringAiFighter({
    this.summary = '',
    this.strengths = const <String>[],
    this.issues = const <AiPriorityIssue>[],
    this.landedEstimate,
    this.patterns = const <String>[],
  });

  final String summary;
  final List<String> strengths;

  /// Same shape as the single-person review's findings (parsed with the same,
  /// unmodified [AiPriorityIssue.tryFrom]).
  final List<AiPriorityIssue> issues;

  /// The model's estimate of clean punches landed — an estimate, never a count.
  final int? landedEstimate;

  /// Tendencies ("kept dropping the left after the jab").
  final List<String> patterns;

  Map<String, Object?> toJson() => <String, Object?>{
    'summary': summary,
    'strengths': strengths,
    'priority_issues': <Object?>[for (final i in issues) i.toJson()],
    'landed_estimate': landedEstimate,
    'patterns': patterns,
  };

  static SparringAiFighter fromMap(Object? raw) {
    if (raw is! Map) return const SparringAiFighter();
    final map = raw.cast<String, Object?>();
    return SparringAiFighter(
      summary: map['summary'] as String? ?? '',
      strengths: _strings(map['strengths']),
      issues: <AiPriorityIssue>[
        for (final i in (map['priority_issues'] as List<Object?>? ?? const <Object?>[]))
          ?AiPriorityIssue.tryFrom(i),
      ],
      landedEstimate: (map['landed_estimate'] as num?)?.toInt(),
      patterns: _strings(map['patterns']),
    );
  }
}

/// An exchange as the AI saw it.
class SparringAiExchange {
  const SparringAiExchange({
    required this.startSeconds,
    required this.endSeconds,
    required this.startedBy,
    required this.summary,
  });

  final double startSeconds;
  final double endSeconds;
  final FighterLabel? startedBy;
  final String summary;

  Map<String, Object?> toJson() => <String, Object?>{
    'start': startSeconds,
    'end': endSeconds,
    'started_by': startedBy?.letter,
    'summary': summary,
  };

  static SparringAiExchange? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final start = raw['start'];
    final summary = raw['summary'];
    if (start is! num || summary is! String) return null;
    return SparringAiExchange(
      startSeconds: start.toDouble(),
      endSeconds: (raw['end'] as num?)?.toDouble() ?? start.toDouble(),
      startedBy: _label(raw['started_by']),
      summary: summary,
    );
  }
}

/// One sampled attack and how it was defended.
class SparringAiDefence {
  const SparringAiDefence({
    required this.timeSeconds,
    required this.defender,
    required this.response,
    required this.verdict,
  });

  final double timeSeconds;
  final FighterLabel? defender;

  /// 'slip', 'roll', 'block', 'parry', 'step back', 'none', …
  final String response;

  /// 'good', 'late', 'none', …
  final String verdict;

  Map<String, Object?> toJson() => <String, Object?>{
    'time': timeSeconds,
    'defender': defender?.letter,
    'response': response,
    'verdict': verdict,
  };

  static SparringAiDefence? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final time = raw['time'];
    if (time is! num) return null;
    return SparringAiDefence(
      timeSeconds: time.toDouble(),
      defender: _label(raw['defender']),
      response: raw['response'] as String? ?? '',
      verdict: raw['verdict'] as String? ?? '',
    );
  }
}

/// The whole report.
class SparringAiReport {
  const SparringAiReport({
    required this.summary,
    required this.fighters,
    this.exchanges = const <SparringAiExchange>[],
    this.defence = const <SparringAiDefence>[],
  });

  final String summary;
  final Map<FighterLabel, SparringAiFighter> fighters;
  final List<SparringAiExchange> exchanges;
  final List<SparringAiDefence> defence;

  SparringAiFighter fighter(FighterLabel label) =>
      fighters[label] ?? const SparringAiFighter();

  /// The same report with A and B exchanged — for when the user turns out to
  /// be the fighter the tracker had called B.
  SparringAiReport swapped() => SparringAiReport(
    summary: summary,
    fighters: <FighterLabel, SparringAiFighter>{
      FighterLabel.a: fighter(FighterLabel.b),
      FighterLabel.b: fighter(FighterLabel.a),
    },
    exchanges: <SparringAiExchange>[
      for (final e in exchanges)
        SparringAiExchange(
          startSeconds: e.startSeconds,
          endSeconds: e.endSeconds,
          startedBy: e.startedBy?.other,
          summary: e.summary,
        ),
    ],
    defence: <SparringAiDefence>[
      for (final d in defence)
        SparringAiDefence(
          timeSeconds: d.timeSeconds,
          defender: d.defender?.other,
          response: d.response,
          verdict: d.verdict,
        ),
    ],
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'summary': summary,
    'fighter_a': fighter(FighterLabel.a).toJson(),
    'fighter_b': fighter(FighterLabel.b).toJson(),
    'exchanges': <Object?>[for (final e in exchanges) e.toJson()],
    'defence': <Object?>[for (final d in defence) d.toJson()],
  };

  factory SparringAiReport.fromJson(Map<String, Object?> json) =>
      _fromMap(json) ?? const SparringAiReport(summary: '', fighters: <FighterLabel, SparringAiFighter>{});

  /// Strict parse of the model's text: JSON (optionally fenced) with a
  /// summary and both fighters. Null on anything else.
  static SparringAiReport? tryParse(String raw) {
    var text = raw.trim();
    final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$');
    final match = fence.firstMatch(text);
    if (match != null) text = match.group(1)!.trim();
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      return _fromMap(decoded.cast<String, Object?>());
    } on FormatException {
      return null;
    }
  }

  static SparringAiReport? _fromMap(Map<String, Object?> map) {
    final summary = map['summary'];
    if (summary is! String) return null;
    if (map['fighter_a'] is! Map || map['fighter_b'] is! Map) return null;
    return SparringAiReport(
      summary: summary,
      fighters: <FighterLabel, SparringAiFighter>{
        FighterLabel.a: SparringAiFighter.fromMap(map['fighter_a']),
        FighterLabel.b: SparringAiFighter.fromMap(map['fighter_b']),
      },
      exchanges: <SparringAiExchange>[
        for (final e in (map['exchanges'] as List<Object?>? ?? const <Object?>[]))
          ?SparringAiExchange.tryFrom(e),
      ],
      defence: <SparringAiDefence>[
        for (final d in (map['defence'] as List<Object?>? ?? const <Object?>[]))
          ?SparringAiDefence.tryFrom(d),
      ],
    );
  }
}

List<String> _strings(Object? raw) => <String>[
  for (final s in (raw as List<Object?>? ?? const <Object?>[]))
    if (s is String && s.trim().isNotEmpty) s.trim(),
];

FighterLabel? _label(Object? raw) {
  if (raw is! String) return null;
  return FighterLabel.fromValue(raw.trim().toLowerCase());
}
