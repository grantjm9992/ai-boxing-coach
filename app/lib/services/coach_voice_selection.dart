/// Picks the most natural-sounding installed TTS voice for the coach.
///
/// Every phone ships several voices per language of very different quality — from
/// the old robotic "compact"/eloquence voices up to the modern neural ones
/// (Google's *network* voices on Android; Apple's *enhanced* / *premium* / Siri
/// voices on iOS). The OS default is frequently one of the low-quality ones,
/// which is exactly what makes text-to-speech sound robotic.
///
/// This scores the installed voices and returns the best English match to hand
/// to `FlutterTts.setVoice`, or `null` when there's nothing clearly better than
/// the default to choose (in which case the caller leaves the default alone).
///
/// Pure and plugin-free so it can be unit-tested without a device.
library;

/// Each voice is the map `FlutterTts.getVoices` yields, coerced to strings.
/// `name` and `locale` are always present; `quality` / `identifier` appear on
/// some platforms (notably iOS) and sharpen the ranking when they do.
Map<String, String>? pickBestVoice(
  List<Map<String, String>> voices, {
  required String preferredLocale,
}) {
  final wantLocale = _norm(preferredLocale);
  final wantLang = wantLocale.split('-').first;

  Map<String, String>? best;
  var bestScore = 0; // must beat 0 — i.e. be genuinely better than a default

  for (final voice in voices) {
    final locale = _norm(voice['locale'] ?? '');
    if (!locale.startsWith(wantLang)) continue; // right language only

    final score = _score(voice, wantLocale: wantLocale);
    if (score > bestScore) {
      bestScore = score;
      best = voice;
    }
  }
  return best;
}

int _score(Map<String, String> voice, {required String wantLocale}) {
  final locale = _norm(voice['locale'] ?? '');
  // Name + identifier + quality all carry quality hints depending on platform.
  final blob = <String>[
    _norm(voice['name'] ?? ''),
    _norm(voice['identifier'] ?? ''),
    _norm(voice['quality'] ?? ''),
  ].join(' ');

  var score = 0;

  // Quality tiers (Apple exposes these as `quality`; both platforms leak them
  // into the name/identifier).
  if (blob.contains('premium')) {
    score += 6;
  } else if (blob.contains('enhanced') ||
      blob.contains('neural') ||
      blob.contains('wavenet')) {
    score += 5;
  }
  // Apple's Siri voices are the most natural of all.
  if (blob.contains('siri')) score += 6;
  // Android's online "network" voices clearly beat the on-device "local" ones.
  if (blob.contains('network')) score += 3;

  // Known-robotic / low-fi voices: actively avoid.
  if (blob.contains('eloquence')) score -= 6;
  if (blob.contains('compact')) score -= 3;
  if (blob.contains('-local') || blob.contains(' local')) score -= 1;

  // Prefer the exact requested locale (accent match) over the same language.
  if (locale == wantLocale) score += 3;

  return score;
}

String _norm(String s) => s.toLowerCase().replaceAll('_', '-').trim();
