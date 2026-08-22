import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'vision_model.dart';
import 'vision_model_config.dart';

/// A [VisionModel] that speaks the OpenAI `/chat/completions` protocol with
/// image content parts. Works unchanged against OpenAI, DashScope (Qwen),
/// OpenRouter, Together, or a self-hosted vLLM/TGI server — only [config]
/// changes.
class OpenAiCompatibleVisionModel implements VisionModel {
  OpenAiCompatibleVisionModel(this.config, {http.Client? client})
    : _client = client ?? http.Client();

  final VisionModelConfig config;
  final http.Client _client;

  @override
  String get label => config.model;

  Uri get _endpoint {
    final base = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/chat/completions');
  }

  /// Builds the request body. Exposed for tests so the wire shape is pinned.
  Map<String, Object?> buildBody(VisionRequest request) {
    final content = <Map<String, Object?>>[
      <String, Object?>{'type': 'text', 'text': request.userPrompt},
      for (final image in request.images)
        <String, Object?>{
          'type': 'image_url',
          'image_url': <String, Object?>{
            'url': 'data:${image.mime};base64,${base64Encode(image.bytes)}',
          },
        },
    ];
    return <String, Object?>{
      'model': config.model,
      'messages': <Map<String, Object?>>[
        <String, Object?>{'role': 'system', 'content': request.systemPrompt},
        <String, Object?>{'role': 'user', 'content': content},
      ],
      'max_tokens': request.maxTokens,
      'temperature': request.temperature,
    };
  }

  @override
  Future<String> complete(VisionRequest request) async {
    if (!config.isConfigured) {
      throw const VisionModelException('No model configured.');
    }
    final http.Response response;
    try {
      response = await _client.post(
        _endpoint,
        headers: <String, String>{
          'Content-Type': 'application/json',
          if (config.apiKey.trim().isNotEmpty)
            'Authorization': 'Bearer ${config.apiKey.trim()}',
        },
        body: jsonEncode(buildBody(request)),
      );
    } on Object catch (error) {
      throw VisionModelException('Could not reach the model: $error');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VisionModelException(
        'Model returned ${response.statusCode}: ${_briefly(response.body)}',
      );
    }
    return parseContent(response.body);
  }

  /// Pulls `choices[0].message.content` out of an OpenAI-shaped response.
  /// Exposed for tests.
  static String parseContent(String body) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map) throw const VisionModelException('Bad response shape.');
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const VisionModelException('No choices in response.');
    }
    final choice = choices.first as Map;
    final message = choice['message'];
    final content = message is Map ? message['content'] : null;
    if (content is String && content.trim().isNotEmpty) {
      if (choice['finish_reason'] == 'length') {
        // Returned text, but the model hit max_tokens mid-thought — surface it
        // so a clipped coaching read is diagnosable rather than silent.
        debugPrint('AI response truncated (finish_reason: length).');
      }
      return content.trim();
    }
    // Some servers return content as a list of parts.
    if (content is List) {
      final text = content
          .whereType<Map>()
          .map((p) => p['text'])
          .whereType<String>()
          .join()
          .trim();
      if (text.isNotEmpty) return text;
    }
    // No usable text. Surface finish_reason — it's the difference between "the
    // server misbehaved" and the common Gemini case: a thinking model spends a
    // tight max_tokens budget entirely on reasoning and returns null content
    // with finish_reason "length". Raising max_tokens fixes that.
    final reason = choice['finish_reason'];
    throw VisionModelException(
      reason == null
          ? 'No text content in response.'
          : 'No text content in response (finish_reason: $reason).',
    );
  }

  static String _briefly(String body) =>
      body.length > 200 ? '${body.substring(0, 200)}…' : body;

  void close() => _client.close();
}
