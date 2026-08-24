import 'package:flutter/material.dart';

import '../../analysis/analysis_mode.dart';
import '../../analysis/drill.dart';
import '../../analysis/landmarks.dart';
import '../../analysis/school.dart';
import '../../domain/user_profile.dart';
import '../../services/ai/ai_quota_service.dart';
import '../../services/ai/ai_settings_store.dart';
import '../../services/ai/openai_compatible_vision_model.dart';
import '../../services/ai/vision_model.dart';
import '../../services/ai/vision_model_config.dart';
import '../../services/auth/auth_service.dart';
import '../../services/profile_store.dart';
import '../theme.dart';
import 'debug_log_screen.dart';

/// Pick the athlete's stance, guard style and the school they're training
/// toward. This is what turns the (fully-ported) style/school coaching on: every
/// technical round is analysed against the profile chosen here.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    this.store,
    this.aiStore,
    this.auth,
    this.quota,
    super.key,
  });

  final ProfileStore? store;
  final AiSettingsStore? aiStore;
  final AuthService? auth;
  final AiQuotaService? quota;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileStore _store = widget.store ?? const ProfileStore();
  late final AiSettingsStore _aiStore = widget.aiStore ?? const AiSettingsStore();
  late final AuthService? _auth = widget.auth ?? _tryAuth();

  /// AuthService reads Supabase.instance, which isn't initialised in widget
  /// tests — degrade to no account section rather than throwing.
  static AuthService? _tryAuth() {
    try {
      return AuthService();
    } on Object {
      return null;
    }
  }

  late final AiQuotaService _quota = widget.quota ?? AiQuotaService();
  int? _aiRemaining;

  bool _deleting = false;
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
    _refreshQuota();
  }

  void _refreshQuota() {
    _quota.remaining().then((n) {
      if (mounted) setState(() => _aiRemaining = n);
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
    _config = _config.copyWith(
      baseUrl: _baseUrl.text.trim(),
      model: _model.text.trim(),
      apiKey: _apiKey.text.trim(),
    );
    _aiStore.save(_config);
  }

  void _setUseCustomEndpoint(bool value) {
    setState(() => _config = _config.copyWith(useCustomEndpoint: value));
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
                  const _Label('AI coaching'),
                  const SizedBox(height: 4),
                  const Text(
                    'Included — 3 detailed AI analyses per week on the free tier, '
                    'nothing to set up. Runs on our servers when you\'re signed '
                    'in; your allowance resets every Monday.',
                    style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  ),
                  if (!_config.useCustomEndpoint && _aiRemaining != null) ...<Widget>[
                    const SizedBox(height: 12),
                    _QuotaBadge(remaining: _aiRemaining!, limit: kWeeklyAiLimit),
                  ],
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _config.useCustomEndpoint,
                    onChanged: _setUseCustomEndpoint,
                    title: const Text(
                      'Use my own model endpoint',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    subtitle: const Text(
                      'Advanced — send coaching to your own OpenAI-compatible '
                      'server (dev / self-hosted) instead of the hosted coach.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  if (_config.useCustomEndpoint) ...<Widget>[
                    const SizedBox(height: 8),
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
                if (_auth?.isSignedIn ?? false) ..._accountSection(),
              ],
            ),
    );
  }

  List<Widget> _accountSection() {
    final email = _auth?.currentEmail;
    return <Widget>[
      const SizedBox(height: 32),
      const Divider(),
      const SizedBox(height: 12),
      const _Label('Account'),
      const SizedBox(height: 8),
      if (email != null)
        Text(
          'Signed in as $email',
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: _deleting ? null : _signOut,
        icon: const Icon(Icons.logout, size: 18),
        label: const Text('Sign out'),
      ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: _deleting ? null : _confirmDeleteAccount,
        icon: _deleting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.delete_forever, size: 18, color: AppTheme.accent),
        label: const Text(
          'Delete account & data',
          style: TextStyle(color: AppTheme.accent),
        ),
      ),
      const SizedBox(height: 4),
      const Text(
        'Deletes your account and everything stored for it — sessions, '
        'analyses and uploaded frames. This cannot be undone.',
        style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
      ),
    ];
  }

  Future<void> _signOut() async {
    try {
      await _auth?.signOut();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not sign out: $e')));
      }
    }
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This permanently deletes your account and all your data — '
          'sessions, analyses and uploaded frames. It cannot be undone.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: AppTheme.accent),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await _auth?.deleteAccount();
      // AuthGate listens to auth state and returns to the sign-in screen once
      // the account is deleted and signed out.
    } on Object catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
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

/// "N of 3 AI analyses left this week" — reads the server-side weekly quota.
class _QuotaBadge extends StatelessWidget {
  const _QuotaBadge({required this.remaining, required this.limit});

  final int remaining;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final none = remaining <= 0;
    final color = none ? AppTheme.accent : AppTheme.rest;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(none ? Icons.hourglass_bottom : Icons.bolt, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textPrimary,
                ),
                children: none
                    ? const <InlineSpan>[
                        TextSpan(text: 'No AI analyses left'),
                        TextSpan(
                          text: ' — resets Monday',
                          style: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ]
                    : <InlineSpan>[
                        TextSpan(
                          text: '$remaining of $limit',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const TextSpan(text: ' AI analyses left this week'),
                      ],
              ),
            ),
          ),
        ],
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
