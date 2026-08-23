import 'package:boxing_coach/services/coach_voice_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pickBestVoice', () {
    Map<String, String>? pick(List<Map<String, String>> voices,
            {String locale = 'en-GB'}) =>
        pickBestVoice(voices, preferredLocale: locale);

    test('Android: prefers the online "network" voice over the local one', () {
      final best = pick(<Map<String, String>>[
        {'name': 'en-gb-x-gba-local', 'locale': 'en-GB'},
        {'name': 'en-gb-x-gbb-network', 'locale': 'en-GB'},
        {'name': 'en-us-x-sfg-local', 'locale': 'en-US'},
      ]);
      expect(best?['name'], 'en-gb-x-gbb-network');
    });

    test('iOS: prefers an exact-locale enhanced voice over an off-locale premium',
        () {
      final best = pick(<Map<String, String>>[
        {'name': 'Daniel', 'locale': 'en-GB', 'quality': 'default', 'identifier': 'com.apple.ttsbundle.Daniel-compact'},
        {'name': 'Serena', 'locale': 'en-GB', 'quality': 'enhanced', 'identifier': 'com.apple.voice.enhanced.en-GB.Serena'},
        {'name': 'Nicky', 'locale': 'en-US', 'quality': 'premium', 'identifier': 'com.apple.voice.premium.en-US.Nicky'},
      ]);
      expect(best?['name'], 'Serena');
    });

    test('a Siri voice outranks a plain enhanced one', () {
      final best = pick(<Map<String, String>>[
        {'name': 'Martha', 'locale': 'en-GB', 'quality': 'enhanced', 'identifier': 'com.apple.voice.enhanced.en-GB.Martha'},
        {'name': 'Siri Voice 2', 'locale': 'en-GB', 'quality': 'premium', 'identifier': 'com.apple.ttsbundle.siri_female_en-GB_premium'},
      ]);
      expect(best?['name'], 'Siri Voice 2');
    });

    test('accepts a same-language premium when the exact locale is only robotic',
        () {
      final best = pick(<Map<String, String>>[
        {'name': 'Daniel', 'locale': 'en-GB', 'quality': 'default', 'identifier': 'com.apple.ttsbundle.Daniel-compact'},
        {'name': 'Ava', 'locale': 'en-US', 'quality': 'premium', 'identifier': 'com.apple.voice.premium.en-US.Ava'},
      ]);
      expect(best?['name'], 'Ava'); // premium en-US beats compact en-GB
    });

    test('returns null when only low-quality voices exist (keep OS default)', () {
      final best = pick(<Map<String, String>>[
        {'name': 'Albert', 'locale': 'en-US', 'quality': 'default', 'identifier': 'com.apple.speech.synthesis.voice.eloquence'},
        {'name': 'en-us-x-sfg-compact', 'locale': 'en-US'},
      ]);
      expect(best, isNull);
    });

    test('ignores other languages entirely', () {
      final best = pick(<Map<String, String>>[
        {'name': 'Amelie', 'locale': 'fr-FR', 'quality': 'premium', 'identifier': 'premium.fr'},
        {'name': 'Kyoko', 'locale': 'ja-JP', 'quality': 'enhanced', 'identifier': 'enhanced.ja'},
      ]);
      expect(best, isNull);
    });

    test('empty list returns null', () {
      expect(pick(const <Map<String, String>>[]), isNull);
    });
  });
}
