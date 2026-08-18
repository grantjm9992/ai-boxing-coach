import 'dart:convert';
import 'dart:typed_data';

import 'package:boxing_coach/services/ai/openai_compatible_vision_model.dart';
import 'package:boxing_coach/services/ai/vision_model.dart';
import 'package:boxing_coach/services/ai/vision_model_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('VisionModelConfig', () {
    test('isConfigured needs a base URL and a model', () {
      expect(const VisionModelConfig().isConfigured, isFalse);
      expect(
        const VisionModelConfig(baseUrl: 'http://x/v1').isConfigured,
        isFalse,
      );
      expect(
        const VisionModelConfig(baseUrl: 'http://x/v1', model: 'm').isConfigured,
        isTrue,
      );
    });

    test('JSON round-trips', () {
      const c = VisionModelConfig(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-x',
        model: 'gpt-4o-mini',
      );
      final back = VisionModelConfig.fromJson(c.toJson());
      expect(back.baseUrl, c.baseUrl);
      expect(back.apiKey, c.apiKey);
      expect(back.model, c.model);
    });
  });

  group('OpenAiCompatibleVisionModel', () {
    const config = VisionModelConfig(
      baseUrl: 'https://host/v1',
      apiKey: 'sk-test',
      model: 'qwen3-vl-8b-instruct',
    );

    test('buildBody has system + user messages and an image data URI', () {
      final model = OpenAiCompatibleVisionModel(config);
      final body = model.buildBody(
        VisionRequest(
          systemPrompt: 'be a coach',
          userPrompt: 'look',
          images: <VisionImage>[
            VisionImage(bytes: Uint8List.fromList(<int>[1, 2, 3])),
          ],
        ),
      );
      expect(body['model'], 'qwen3-vl-8b-instruct');
      final messages = body['messages'] as List<Object?>;
      expect((messages.first as Map)['role'], 'system');
      final user = messages[1] as Map<String, Object?>;
      final content = user['content'] as List<Object?>;
      expect((content.first as Map)['type'], 'text');
      final image = content[1] as Map<String, Object?>;
      expect((image['image_url'] as Map)['url'],
          startsWith('data:image/jpeg;base64,'));
    });

    test('parseContent extracts the message text', () {
      final body = jsonEncode(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{'content': '  Snap the jab back.  '},
          },
        ],
      });
      expect(OpenAiCompatibleVisionModel.parseContent(body), 'Snap the jab back.');
    });

    test('complete posts to /chat/completions with the bearer token', () async {
      late http.Request captured;
      final client = MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{'content': 'Good work.'},
              },
            ],
          }),
          200,
        );
      });
      final model = OpenAiCompatibleVisionModel(config, client: client);

      final reply = await model.complete(
        const VisionRequest(systemPrompt: 's', userPrompt: 'u'),
      );

      expect(reply, 'Good work.');
      expect(captured.url.toString(), 'https://host/v1/chat/completions');
      expect(captured.headers['Authorization'], 'Bearer sk-test');
    });

    test('a non-2xx response throws VisionModelException', () async {
      final client = MockClient((_) async => http.Response('nope', 500));
      final model = OpenAiCompatibleVisionModel(config, client: client);
      expect(
        () => model.complete(
          const VisionRequest(systemPrompt: 's', userPrompt: 'u'),
        ),
        throwsA(isA<VisionModelException>()),
      );
    });

    test('an unconfigured model refuses to call', () async {
      final model = OpenAiCompatibleVisionModel(const VisionModelConfig());
      expect(
        () => model.complete(
          const VisionRequest(systemPrompt: 's', userPrompt: 'u'),
        ),
        throwsA(isA<VisionModelException>()),
      );
    });
  });
}
