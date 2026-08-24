import 'dart:convert';

import 'package:boxing_coach/services/ai/coach_vision_model.dart';
import 'package:boxing_coach/services/ai/openai_compatible_vision_model.dart';
import 'package:boxing_coach/services/ai/vision_model.dart';
import 'package:boxing_coach/services/ai/vision_model_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const request = VisionRequest(
    systemPrompt: 'You are a boxing coach.',
    userPrompt: 'Reply: ready.',
  );

  group('VisionModelConfig.useCustomEndpoint', () {
    test('defaults off and JSON round-trips', () {
      expect(const VisionModelConfig().useCustomEndpoint, isFalse);
      const c = VisionModelConfig(
        baseUrl: 'https://host/v1',
        model: 'm',
        useCustomEndpoint: true,
      );
      expect(VisionModelConfig.fromJson(c.toJson()).useCustomEndpoint, isTrue);
    });

    test('copyWith preserves the flag when not overridden', () {
      const c = VisionModelConfig(useCustomEndpoint: true);
      expect(c.copyWith(model: 'x').useCustomEndpoint, isTrue);
    });
  });

  group('CoachVisionModel', () {
    test('refuses to call when there is no signed-in token', () async {
      final model = CoachVisionModel(accessToken: () => null);
      expect(
        () => model.complete(request),
        throwsA(isA<VisionModelException>()),
      );
    });

    test('posts to the proxy endpoint with the user token as bearer', () async {
      late http.Request captured;
      final client = MockClient((req) async {
        captured = req;
        return http.Response(
          jsonEncode({
            'choices': [
              {'message': {'content': 'Tighten the guard.'}},
            ],
          }),
          200,
        );
      });
      final model = CoachVisionModel(
        accessToken: () => 'jwt-123',
        httpClient: client,
      );

      final reply = await model.complete(request);

      expect(reply, 'Tighten the guard.');
      expect(captured.url.toString(),
          '${CoachVisionModel.endpointBaseUrl}/chat/completions');
      expect(captured.headers['Authorization'], 'Bearer jwt-123');
    });

    test('maps a 429 to a friendly weekly-limit message', () async {
      final client = MockClient((req) async {
        return http.Response(
          jsonEncode({'error': {'code': 'ai_quota_exceeded'}}),
          429,
        );
      });
      final model = CoachVisionModel(
        accessToken: () => 'jwt-123',
        httpClient: client,
      );

      await expectLater(
        () => model.complete(request),
        throwsA(
          isA<VisionModelException>().having(
            (e) => e.message,
            'message',
            contains('this week'),
          ),
        ),
      );
    });
  });

  group('resolveCoachVisionModel', () {
    test('uses the custom endpoint when enabled and configured', () {
      const config = VisionModelConfig(
        baseUrl: 'https://host/v1',
        model: 'qwen',
        useCustomEndpoint: true,
      );
      expect(
        resolveCoachVisionModel(config: config),
        isA<OpenAiCompatibleVisionModel>(),
      );
    });

    test('is null with no custom endpoint and no Supabase session', () {
      // Supabase is not initialised in unit tests, so the hosted path is
      // unavailable and the round stays offline.
      expect(
        resolveCoachVisionModel(config: const VisionModelConfig()),
        isNull,
      );
    });

    test('custom endpoint enabled but blank falls through to offline', () {
      const config = VisionModelConfig(useCustomEndpoint: true);
      expect(resolveCoachVisionModel(config: config), isNull);
    });
  });
}
