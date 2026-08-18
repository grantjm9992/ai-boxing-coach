import 'dart:typed_data';

/// Provider-agnostic seam for a vision-language model. The coaching pipeline
/// talks only to this interface, so the concrete provider (a hosted API today,
/// a self-hosted vLLM endpoint later) is a swap of implementation — and, for the
/// OpenAI-compatible one, just a change of base URL + model.

/// One image handed to the model (JPEG/PNG bytes + mime).
class VisionImage {
  const VisionImage({required this.bytes, this.mime = 'image/jpeg'});

  final Uint8List bytes;
  final String mime;
}

/// A single request: instructions + prompt + the frames to look at.
class VisionRequest {
  const VisionRequest({
    required this.systemPrompt,
    required this.userPrompt,
    this.images = const <VisionImage>[],
    this.maxTokens = 600,
    this.temperature = 0.4,
  });

  final String systemPrompt;
  final String userPrompt;
  final List<VisionImage> images;
  final int maxTokens;
  final double temperature;
}

/// Thrown when the model can't be reached or returns an error. The pipeline
/// treats this as "no AI enrichment this round" — never a broken session.
class VisionModelException implements Exception {
  const VisionModelException(this.message);
  final String message;
  @override
  String toString() => 'VisionModelException: $message';
}

/// A vision-language model that turns a [VisionRequest] into coaching text.
abstract class VisionModel {
  /// Human-readable name of the configured model, for the UI.
  String get label;

  Future<String> complete(VisionRequest request);
}

/// Records requests and returns canned text. The test double, and the fallback
/// when no model is configured.
class FakeVisionModel implements VisionModel {
  FakeVisionModel({this.response = 'Solid work — keep the jab snapping back.'});

  final String response;
  final List<VisionRequest> requests = <VisionRequest>[];

  @override
  String get label => 'Fake model';

  @override
  Future<String> complete(VisionRequest request) async {
    requests.add(request);
    return response;
  }
}
