import 'package:boxing_coach/services/ai/ai_quota_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AiQuotaService', () {
    test('weekly limit is the alpha allowance (50)', () {
      // ALPHA: bumped from 3. Server enforcement must match via AI_WEEKLY_LIMIT.
      expect(kWeeklyAiLimit, 50);
      expect(AiQuotaService().weeklyLimit, 50);
    });

    test('remaining is null when Supabase is unavailable', () async {
      // Supabase isn't initialised in unit tests, so there's no session to read
      // a quota for — the indicator hides rather than throwing.
      expect(await AiQuotaService().remaining(), isNull);
    });
  });
}
