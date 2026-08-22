import 'package:flutter/material.dart';

import '../../analysis/analysis_mode.dart';
import '../../analysis/drill.dart';
import '../../analysis/landmarks.dart';
import '../../analysis/school.dart';
import '../../domain/user_profile.dart';
import '../../services/ai/ai_settings_store.dart';
import '../../services/ai/openai_compatible_vision_model.dart';
import '../../services/ai/vision_model.dart';
import '../../services/ai/vision_model_config.dart';
import '../../services/profile_store.dart';
import '../theme.dart';
import 'debug_log_screen.dart';

/// Pick the athlete's stance, guard style and the school they're training
/// toward. This is what turns the (fully-ported) style/school coaching on: every
/// technical round is analysed against the profile chosen here.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({this.store, this.aiStore, super.key});

  final ProfileStore? store;
  final AiSettingsStore? aiStore;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileStore _store = widget.store ?? const ProfileStore();
  late final AiSettingsStore _aiStore = widget.aiStore ?? const AiSettingsStore();
  UserProfile _profile = const UserProfile();
  VisionModelConfig _config = const VisionModelConfig();
  final TextEditingController _baseUrl = TextEditingController();
  final TextEditingController _model = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();
  String? _testResult;
  bool _testing = false;
  bool _loaded = false;

  static const Map<Style, String> _styleLabels = <Style, String>{
    Style.highGuard: 'High guard',
    Style.phillyShell: 'Philly shell',
    Style.peekABoo: 'Peek-a-boo',
    Style.outBoxer: 'Out-boxer',
  };

  static const Map<Style, String> _styleBlurbs = <Style, String>{
    Style.highGuard: 'Textbook hands-up guard. Every check at its default.',
    Style.phillyShell: 'Lead hand low across the body — guard checks judge the rear hand only.',
    Style.peekABoo: 'Hands by the cheeks, constant head movement — held to a higher head bar.',
    Style.outBoxer: 'Range and footwork over slips — head-movement off, footwork bar raised.',
  };

  static const Map<School?, String> _schoolLabels = <School?, String>{
    null: 'None',
    School.soviet: 'Soviet',
    School.mexican: 'Mexican',
    School.european: 'European',
    School.american: 'American',
  };

  @override
  void initState() {
    super.initState();
    Future.wait(<Future<Object>>[_store.load(), _aiStore.load()]).then((values) {
      if (!mounted) return;
      setState(() {
        _profile = values[0] as UserProfile;
        _config = values[1] as VisionModelConfig;
        _baseUrl.text = _config.baseUrl;
        _model.text = _config.model;
        _apiKey.text = _config.apiKey;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _update(UserProfile next) {
    setState(() => _profile = next);
    _store.save(next);
  }

  void _updateConfig() {
    _config = VisionModelConfig(
      baseUrl: _baseUrl.text.trim(),
      model: _model.text.trim(),
      apiKey: _apiKey.text.trim(),
    );
    _aiStore.save(_config);
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final model = OpenAiCompatibleVisionModel(_config);
    try {
      final reply = await model.complete(
        const VisionRequest(
          systemPrompt: 'You are a boxing coach.',
          userPrompt: 'Reply with the single word: ready.',
          // Not 8: thinking models (e.g. Gemini 2.5) spend the token budget on
          // reasoning first and return empty content with finish_reason=length.
          maxTokens: 512,
        ),
      );
      if (mounted) setState(() => _testResult = 'Connected — model said: "$reply"');
    } on Object catch (error) {
      if (mounted) setState(() => _testResult = 'Failed: $error');
    } finally {
      model.close();
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your profile'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Debug log',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const DebugLogScreen(),
              ),
            ),
          ),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: <Widget>[
                const Text(
                  'Rounds are coached against this. Change it and the next '
                  'round is judged in that game.',
                  style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
                ),
                const SizedBox(height: 24),
                const _Label('Stance'),
                const SizedBox(height: 8),
                SegmentedButton<Stance>(
                  segments: const <ButtonSegment<Stance>>[
                    ButtonSegment<Stance>(
                      value: Stance.orthodox,
                      label: Text('Orthodox'),
                    ),
                    ButtonSegment<Stance>(
                      value: Stance.southpaw,
                      label: Text('Southpaw'),
                    ),
                  ],
                  selected: <Stance>{_profile.stance},
                  onSelectionChanged: (s) =>
                      _update(_profile.copyWith(stance: s.first)),
                ),
                const SizedBox(height: 24),
                const _Label('Guard style'),
                const SizedBox(height: 8),
                for (final style in Style.values)
                  _StyleTile(
                    label: _styleLabels[style]!,
                    blurb: _styleBlurbs[style]!,
                    selected: _profile.style == style,
                    onTap: () => _update(_profile.copyWith(style: style)),
                  ),
                const SizedBox(height: 16),
                const _Label('School to coach toward'),
                const SizedBox(height: 4),
                const Text(
                  'Optional. Adds tactical nudges toward that national game.',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final entry in _schoolLabels.entries)
                      ChoiceChip(
                        label: Text(entry.value),
                        selected: _profile.school == entry.key,
                        onSelected: (_) => _update(
                          entry.key == null
                              ? _profile.copyWith(clearSchool: true)
                              : _profile.copyWith(school: entry.key),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 28),
                const _Label('Analysis mode'),
                const SizedBox(height: 8),
                for (final mode in AnalysisMode.values)
                  _StyleTile(
                    label: mode.label,
                    blurb: mode.blurb,
                    selected: _profile.analysisMode == mode,
                    enabled: mode.available,
                    badge: mode.available ? null : 'Coming soon',
                    onTap: mode.available
                        ? () => _update(_profile.copyWith(analysisMode: mode))
                        : null,
                  ),
                if (_profile.analysisMode.usesAi) ...<Widget>[
                  const SizedBox(height: 16),
                  const _Label('Model endpoint'),
                  const SizedBox(height: 4),
                  const Text(
                    'OpenAI-compatible. Works with a hosted API now (OpenAI, '
                    'Qwen/DashScope, OpenRouter) or your own vLLM server later — '
                    'just point the base URL + model at it.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                  _field(_baseUrl, 'Base URL', 'https://api.openai.com/v1'),
                  const SizedBox(height: 10),
                  _field(_model, 'Model', 'qwen3-vl-8b-instruct'),
                  const SizedBox(height: 10),
                  _field(_apiKey, 'API key', 'sk-…', obscure: true),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      OutlinedButton.icon(
                        onPressed: _testing || !_config.isConfigured
                            ? null
                            : _testConnection,
                        icon: _testing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.wifi_tethering, size: 18),
                        label: const Text('Test connection'),
                      ),
                    ],
                  ),
                  if (_testResult != null) ...<Widget>[
                    const SizedBox(height: 10),
                    Text(
                      _testResult!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label,
    String hint, {
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: (_) => _updateConfig(),
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _StyleTile extends StatelessWidget {
  const _StyleTile({
    required this.label,
    required this.blurb,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.badge,
  });

  final String label;
  final String blurb;
  final bool selected;
  final VoidCallback? onTap;

  /// When false the tile is dimmed and can't be tapped (e.g. a parked mode).
  final bool enabled;

  /// Optional pill next to the label, e.g. 'Coming soon'.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: enabled ? 1 : 0.55,
        child: Material(
          color: selected ? AppTheme.surfaceAlt : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    !enabled
                        ? Icons.lock_outline
                        : selected
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                    color: selected ? AppTheme.accent : AppTheme.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Flexible(
                              child: Text(
                                label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (badge != null) ...<Widget>[
                              const SizedBox(width: 8),
                              _Badge(badge!),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          blurb,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A small pill label, e.g. the 'Coming soon' marker on a parked mode.
class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.textSecondary.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 9,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w700,
          color: AppTheme.textSecondary,
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      fontSize: 12,
      letterSpacing: 1,
      fontWeight: FontWeight.w700,
      color: AppTheme.textSecondary,
    ),
  );
}
