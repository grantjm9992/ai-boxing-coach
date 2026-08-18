/// Where the AI model lives and how to talk to it. Deliberately shaped around
/// the OpenAI chat-completions protocol, because hosted providers (OpenAI,
/// DashScope/Qwen, OpenRouter, Together) **and** self-hosted vLLM/TGI all speak
/// it — so moving from "test against an API" to "run my own model" is a change
/// of [baseUrl] + [model], nothing else.
class VisionModelConfig {
  const VisionModelConfig({
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
  });

  /// The OpenAI-compatible base, ending in `/v1`, e.g.
  ///   https://api.openai.com/v1
  ///   https://dashscope-intl.aliyuncs.com/compatible-mode/v1   (Qwen)
  ///   http://10.0.0.5:8000/v1                                  (self-hosted vLLM)
  final String baseUrl;

  /// Bearer token. Empty is allowed for a local endpoint that needs none.
  final String apiKey;

  /// Model id, e.g. `gpt-4o-mini`, `qwen3-vl-8b-instruct`, or whatever a
  /// self-hosted server was launched with.
  final String model;

  /// Enough to attempt a call: we have somewhere to send it and something to run.
  bool get isConfigured => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  VisionModelConfig copyWith({String? baseUrl, String? apiKey, String? model}) =>
      VisionModelConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
  };

  factory VisionModelConfig.fromJson(Map<String, Object?> json) =>
      VisionModelConfig(
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        model: json['model'] as String? ?? '',
      );
}
