import 'package:boxing_coach/services/ai/ai_quota_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiQuotaService', () {
    test('weekly limit matches the server default (3)', () {
      expect(kWeeklyAiLimit, 3);
      expect(AiQuotaService().weeklyLimit, 3);
    });

    test('remaining is null when Supabase is unavailable', () async {
      // Supabase isn't initialised in unit tests, so there's no session to read
      // a quota for — the indicator hides rather than throwing.
      expect(await AiQuotaService().remaining(), isNull);
    });
  });
}
