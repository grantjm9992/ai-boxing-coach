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
    this.useCustomEndpoint = false,
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

  /// Advanced: send coaching to [baseUrl] directly instead of the hosted proxy.
  /// Off by default — the shipped app routes AI through the Supabase `analyze`
  /// function (server-side key + weekly cap). Turn this on to use your own
  /// OpenAI-compatible endpoint (dev / self-hosted Qwen).
  final bool useCustomEndpoint;

  /// Enough to attempt a call: we have somewhere to send it and something to run.
  bool get isConfigured => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  VisionModelConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    bool? useCustomEndpoint,
  }) => VisionModelConfig(
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    model: model ?? this.model,
    useCustomEndpoint: useCustomEndpoint ?? this.useCustomEndpoint,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'model': model,
    'useCustomEndpoint': useCustomEndpoint,
  };

  factory VisionModelConfig.fromJson(Map<String, Object?> json) =>
      VisionModelConfig(
        baseUrl: json['baseUrl'] as String? ?? '',
        apiKey: json['apiKey'] as String? ?? '',
        model: json['model'] as String? ?? '',
        useCustomEndpoint: json['useCustomEndpoint'] as bool? ?? false,
      );
}
