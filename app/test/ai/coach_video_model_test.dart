import 'dart:convert';

import 'package:boxing_coach/services/ai/coach_video_model.dart';
import 'package:boxing_coach/services/ai/video_vision_model.dart';
import 'package:boxing_coach/services/ai/vision_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const base = 'https://proj.supabase.co/functions/v1/analyze';
  const uploadUrl = 'https://upload.googleapis.test/upload?upload_id=abc';
  final videoBytes = utf8.encode('fake-mp4-bytes');

  const request = VideoVisionRequest(
    systemPrompt: 'You are a boxing coach.',
    userPrompt: 'Watch the round.',
    videoPath: '/clips/round.mp4',
  );

  CoachVideoModel modelWith(MockClient client, {String? token = 'user-token'}) =>
      CoachVideoModel(
        accessToken: () => token,
        httpClient: client,
        endpointBaseUrl: base,
        fileLength: (_) async => videoBytes.length,
        openRead: (_) => Stream<List<int>>.value(videoBytes),
        retryDelay: Duration.zero,
      );

  test('uploads straight to Google, then asks the coach to review it', () async {
    final seen = <http.Request>[];
    final client = MockClient((req) async {
      seen.add(req);
      if (req.url.toString() == '$base/video/upload') {
        return http.Response(jsonEncode(<String, Object?>{'uploadUrl': uploadUrl}), 200);
      }
      if (req.url.toString() == uploadUrl) {
        return http.Response(
          jsonEncode(<String, Object?>{
            'file': <String, Object?>{'name': 'files/abc123'},
          }),
          200,
        );
      }
      if (req.url.toString() == '$base/video/generate') {
        return http.Response(
          jsonEncode(<String, Object?>{'text': '  Keep the rear hand home.  '}),
          200,
        );
      }
      return http.Response('unexpected ${req.url}', 404);
    });

    final text = await modelWith(client).completeVideo(request);

    expect(text, 'Keep the rear hand home.');
    expect(seen, hasLength(3));

    final start = jsonDecode(seen[0].body) as Map<String, Object?>;
    expect(start, <String, Object?>{
      'bytes': videoBytes.length,
      'mimeType': 'video/mp4',
    });
    expect(seen[0].headers['Authorization'], 'Bearer user-token');

    // The bytes go to Google's URL with no bearer — the URL authorises itself.
    expect(seen[1].bodyBytes, videoBytes);
    expect(seen[1].headers['X-Goog-Upload-Command'], 'upload, finalize');
    expect(seen[1].headers.containsKey('Authorization'), isFalse);

    final generate = jsonDecode(seen[2].body) as Map<String, Object?>;
    expect(generate['fileName'], 'files/abc123');
    expect(generate['fps'], 24);
    expect(generate['userPrompt'], 'Watch the round.');
  });

  test('refuses to start without a signed-in token', () async {
    final client = MockClient((_) async => fail('should not call the network'));
    expect(
      () => modelWith(client, token: null).completeVideo(request),
      throwsA(isA<VisionModelException>()),
    );
  });

  test('maps the weekly cap to a friendly message', () async {
    final client = MockClient(
      (_) async => http.Response(
        '{"error":{"code":"ai_quota_exceeded","message":"cap"}}',
        429,
      ),
    );
    expect(
      () => modelWith(client).completeVideo(request),
      throwsA(
        isA<VisionModelException>().having(
          (e) => e.message,
          'message',
          contains('resets Monday'),
        ),
      ),
    );
  });

  test('a failed upload surfaces as a VisionModelException', () async {
    final client = MockClient((req) async {
      if (req.url.toString() == '$base/video/upload') {
        return http.Response(jsonEncode(<String, Object?>{'uploadUrl': uploadUrl}), 200);
      }
      return http.Response('boom', 500);
    });
    expect(
      () => modelWith(client).completeVideo(request),
      throwsA(isA<VisionModelException>()),
    );
  });

  test('retries generate while Google is still processing the upload', () async {
    var generateCalls = 0;
    final client = MockClient((req) async {
      final url = req.url.toString();
      if (url == '$base/video/upload') {
        return http.Response(jsonEncode(<String, Object?>{'uploadUrl': uploadUrl}), 200);
      }
      if (url == uploadUrl) {
        return http.Response('{"file":{"name":"files/abc123"}}', 200);
      }
      generateCalls++;
      return generateCalls < 3
          ? http.Response('{"error":{"message":"still processing"}}', 503)
          : http.Response('{"text":"Done."}', 200);
    });

    expect(await modelWith(client).completeVideo(request), 'Done.');
    expect(generateCalls, 3);
  });

  test('reports upload progress, then reviewing, and asks for JSON when the '
      'request has a schema', () async {
    final seen = <http.Request>[];
    final client = MockClient((req) async {
      seen.add(req);
      final url = req.url.toString();
      if (url == '$base/video/upload') {
        return http.Response(jsonEncode(<String, Object?>{'uploadUrl': uploadUrl}), 200);
      }
      if (url == uploadUrl) {
        return http.Response('{"file":{"name":"files/abc123"}}', 200);
      }
      return http.Response('{"text":"{\\"summary\\":\\"ok\\"}"}', 200);
    });
    final phases = <(VideoReviewPhase, double?)>[];

    await modelWith(client).completeVideo(
      const VideoVisionRequest(
        systemPrompt: 's',
        userPrompt: 'u',
        videoPath: '/clips/round.mp4',
        responseSchema: <String, Object?>{'type': 'OBJECT'},
      ),
      onProgress: (phase, fraction) => phases.add((phase, fraction)),
    );

    expect(phases.first, (VideoReviewPhase.uploading, 0.0));
    expect(phases, contains((VideoReviewPhase.uploading, 1.0)));
    expect(phases.last, (VideoReviewPhase.reviewing, null));

    final generate = jsonDecode(seen.last.body) as Map<String, Object?>;
    expect(generate['responseMimeType'], 'application/json');
    expect(generate['responseSchema'], <String, Object?>{'type': 'OBJECT'});
  });
}
