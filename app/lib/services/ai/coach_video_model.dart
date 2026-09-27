import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'coach_vision_model.dart';
import 'video_vision_model.dart';
import 'vision_model.dart';
import 'vision_model_config.dart';

/// The hosted Full AI review model. Three steps, so the provider key never
/// touches the device and the round's video never passes through our function:
///
///  1. `POST analyze/video/upload` — the proxy opens a Gemini upload session and
///     returns its (self-authorising) upload URL;
///  2. the video is streamed straight to that URL;
///  3. `POST analyze/video/generate` — the proxy runs Gemini over the uploaded
///     file at [VideoVisionRequest.fps], spends one weekly analysis, deletes the
///     upload and returns the coaching text.
///
/// See `supabase/functions/analyze/` and docs/AI_PROXY.md.
class CoachVideoModel implements VideoVisionModel {
  CoachVideoModel({
    String? Function()? accessToken,
    http.Client? httpClient,
    String? endpointBaseUrl,
    Future<int> Function(String path)? fileLength,
    Stream<List<int>> Function(String path)? openRead,
    this.processingRetries = 4,
    this.retryDelay = const Duration(seconds: 2),
  }) : _accessToken =
           accessToken ??
           (() => Supabase.instance.client.auth.currentSession?.accessToken),
       _client = httpClient,
       _base = endpointBaseUrl ?? CoachVisionModel.endpointBaseUrl,
       _fileLength = fileLength ?? ((p) => File(p).length()),
       _openRead = openRead ?? ((p) => File(p).openRead());

  final String? Function() _accessToken;
  final http.Client? _client;
  final String _base;
  final Future<int> Function(String path) _fileLength;
  final Stream<List<int>> Function(String path) _openRead;

  /// How many more times to ask for the review while Google is still
  /// processing the upload (the proxy answers 503 and keeps the file).
  final int processingRetries;
  final Duration retryDelay;

  @override
  String get label => 'AI Coach (full video)';

  @override
  Future<String> completeVideo(VideoVisionRequest request) async {
    final token = _accessToken();
    if (token == null || token.isEmpty) {
      throw const VisionModelException('Sign in to get AI coaching.');
    }
    final client = _client ?? http.Client();
    try {
      final bytes = await _fileLength(request.videoPath);
      final uploadUrl = await _startUpload(client, token, bytes, request.mimeType);
      final fileName = await _upload(client, uploadUrl, request.videoPath, bytes);
      return await _generate(client, token, fileName, request);
    } finally {
      if (_client == null) client.close();
    }
  }

  Future<String> _startUpload(
    http.Client client,
    String token,
    int bytes,
    String mimeType,
  ) async {
    final body = await _postJson(client, token, 'video/upload', <String, Object?>{
      'bytes': bytes,
      'mimeType': mimeType,
    });
    final url = body['uploadUrl'];
    if (url is! String || url.isEmpty) {
      throw const VisionModelException('No upload URL from the coach.');
    }
    return url;
  }

  /// Streams the file to Google's upload URL (no key: the URL authorises
  /// itself) and returns the Files API name, e.g. `files/abc123`.
  Future<String> _upload(
    http.Client client,
    String uploadUrl,
    String path,
    int bytes,
  ) async {
    final request = http.StreamedRequest('POST', Uri.parse(uploadUrl))
      ..contentLength = bytes
      ..headers.addAll(<String, String>{
        'X-Goog-Upload-Offset': '0',
        'X-Goog-Upload-Command': 'upload, finalize',
      });
    // Start sending before piping, so the file streams rather than being
    // buffered whole in memory. `ignore()` only stops an early network error
    // counting as unhandled while we pipe — it's still rethrown below.
    final sending = client.send(request)..ignore();

    final http.Response response;
    try {
      await request.sink.addStream(_openRead(path));
      await request.sink.close();
      response = await http.Response.fromStream(await sending);
    } on Object catch (error) {
      throw VisionModelException('Could not upload the round: $error');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VisionModelException(
        'Upload failed (${response.statusCode}): ${_briefly(response.body)}',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    final file = decoded is Map ? decoded['file'] : null;
    final name = file is Map ? file['name'] : null;
    if (name is! String || name.isEmpty) {
      throw const VisionModelException('Upload finished without a file name.');
    }
    return name;
  }

  Future<String> _generate(
    http.Client client,
    String token,
    String fileName,
    VideoVisionRequest request,
  ) async {
    final payload = <String, Object?>{
      'fileName': fileName,
      'fps': request.fps,
      'systemPrompt': request.systemPrompt,
      'userPrompt': request.userPrompt,
      'maxTokens': request.maxTokens,
      'temperature': request.temperature,
    };
    for (var attempt = 0; ; attempt++) {
      try {
        final body = await _postJson(client, token, 'video/generate', payload);
        final text = body['text'];
        if (text is! String || text.trim().isEmpty) {
          throw const VisionModelException('No text content in response.');
        }
        return text.trim();
      } on _StillProcessing {
        if (attempt >= processingRetries) {
          throw const VisionModelException(
            'The round video is taking too long to process — try again shortly.',
          );
        }
        await Future<void>.delayed(retryDelay);
      }
    }
  }

  Future<Map<String, Object?>> _postJson(
    http.Client client,
    String token,
    String route,
    Map<String, Object?> payload,
  ) async {
    final http.Response response;
    try {
      response = await client.post(
        Uri.parse('${_base.replaceAll(RegExp(r'/+$'), '')}/$route'),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(payload),
      );
    } on Object catch (error) {
      throw VisionModelException('Could not reach the coach: $error');
    }
    if (response.statusCode == 429 ||
        response.body.contains('ai_quota_exceeded')) {
      throw const VisionModelException(
        "You've used all your AI analyses this week — resets Monday.",
      );
    }
    if (response.statusCode == 503 && route == 'video/generate') {
      throw const _StillProcessing();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VisionModelException(
        'Coach returned ${response.statusCode}: ${_briefly(response.body)}',
      );
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const VisionModelException('Bad response shape.');
    return decoded.cast<String, Object?>();
  }

  static String _briefly(String body) =>
      body.length > 200 ? '${body.substring(0, 200)}…' : body;
}

/// The proxy's "upload still processing" answer — retried, never surfaced.
class _StillProcessing implements Exception {
  const _StillProcessing();
}

/// Picks the Full AI review model: the hosted coach when signed in. Null when
/// the user routes AI to their own endpoint (an OpenAI-compatible server can't
/// take a whole video, and we shouldn't silently send it to ours instead) or
/// isn't signed in — the round then gets key-moment coaching, or stays offline.
VideoVisionModel? resolveCoachVideoModel({required VisionModelConfig config}) {
  if (config.useCustomEndpoint) return null;
  try {
    if (Supabase.instance.client.auth.currentSession != null) {
      return CoachVideoModel();
    }
  } on Object {
    // Supabase not initialised (e.g. unit tests) — no hosted AI available.
  }
  return null;
}
